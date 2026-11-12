#!/usr/bin/env python3
"""Browser file tasks with private Phoenix servers and global resource admission."""
from __future__ import annotations

import argparse
from contextlib import ExitStack
from concurrent.futures import ThreadPoolExecutor
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import uuid

from check_resources import GIB, resources
from check_runtime import cancellation_scope, stop_tree, tracked_process, worker_environment, worker_count
from check_scheduler import command_lease, managed_run
from run_laws import run as run_command

ROOT = Path(__file__).resolve().parents[1]
BROWSER = ROOT / 'apps/review_web/test/browser'
CONFIG = {'main': 'playwright.config.cjs', 'presentation': 'presentation.static.config.cjs',
          'questions': 'questions.controlled.config.cjs'}


def inventory(profile: str) -> list[Path]:
    if profile == 'main':
        return sorted(BROWSER.glob('*.spec.cjs'))
    return [BROWSER / ('presentation_help.spec.cjs' if profile == 'presentation' else 'questions_controlled.cjs')]


def browser_file(profile: str, file: Path, directory: Path) -> dict:
    directory.mkdir(parents=True)
    static = profile == 'presentation' or file.name == 'presentation_help.spec.cjs'
    memory = (2 if static else 4) * GIB
    with command_lease(f'browser:{profile}:{file.name}', memory=memory, max_cpu=2) as lease:
        env = worker_environment(1, cpu_budget=lease.allocation['cpu'])
        env.update(MIX_ENV='test', PLAYWRIGHT_JSON_OUTPUT_FILE=str(directory / 'results.json'))
        server = None
        with ExitStack() as stack, (directory / 'server.log').open('wb') as server_log, (directory / 'browser.log').open('wb') as browser_log:
            try:
                if not static:
                    token = uuid.uuid4().hex
                    ready = directory / 'ready.json'
                    env.update(HOLD_LEDGER_BROWSER_DIR=str(directory / 'stores'),
                               HOLD_LEDGER_BROWSER_PROFILE=profile, HOLD_LEDGER_BROWSER_TOKEN=token,
                               HOLD_LEDGER_BROWSER_READY=str(ready))
                    server = subprocess.Popen(
                        [sys.executable, str(ROOT / 'scripts/local_run.py'), '--cwd', 'apps/review_web',
                         'mix', 'run', '--no-compile', '--no-start', '--no-halt',
                         'test/support/question_browser_server.exs'],
                        cwd=ROOT, env=env, stdin=subprocess.DEVNULL, stdout=server_log,
                        stderr=subprocess.STDOUT, start_new_session=True)
                    stack.enter_context(tracked_process(server))
                    lease.started(server.pid)
                    deadline = time.monotonic() + 120
                    while not ready.exists():
                        if server.poll() is not None:
                            raise RuntimeError(f'Browser server exited {server.returncode}; see {directory / "server.log"}')
                        if time.monotonic() >= deadline:
                            raise TimeoutError('Browser server readiness timed out')
                        time.sleep(.1)
                    response = json.loads(ready.read_text())
                    if response['token'] != token or response['profile'] != profile:
                        raise RuntimeError('Wrong browser server readiness identity')
                    env['PLAYWRIGHT_BASE_URL'] = f'http://127.0.0.1:{response["port"]}'
                argv = ['npx', '--no-install', 'playwright', 'test', file.name, '--config', CONFIG[profile],
                        '--workers', '1', '--retries', '0', '--reporter', 'list,json',
                        '--output', str(directory / 'artifacts')]
                child = subprocess.Popen(argv, cwd=BROWSER, env=env, stdin=subprocess.DEVNULL,
                                         stdout=browser_log, stderr=subprocess.STDOUT, start_new_session=True)
                lease.started(child.pid)
                with tracked_process(child):
                    code = child.wait(timeout=1800)
                report_path = directory / 'results.json'
                report = json.loads(report_path.read_text()) if report_path.exists() else {}
                stats = report.get('stats', {})
                passed = (code == 0 and stats.get('expected', 0) > 0
                          and stats.get('unexpected') == 0 and stats.get('flaky') == 0)
                return {'profile': profile, 'file': file.name, 'passed': passed, 'exit': code,
                        'stats': stats, 'directory': str(directory)}
            except Exception as error:
                return {'profile': profile, 'file': file.name, 'passed': False,
                        'error': str(error), 'directory': str(directory)}
            finally:
                if server is not None:
                    stop_tree(server.pid)
                    server.wait()


@managed_run
def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('profile', choices=[*CONFIG, 'all'])
    parser.add_argument('--jobs', type=int)
    args = parser.parse_args()
    if args.jobs is not None and args.jobs < 1:
        parser.error('--jobs must be positive')
    profiles = list(CONFIG) if args.profile == 'all' else [args.profile]
    tasks = [(profile, file) for profile in profiles for file in inventory(profile)]
    if not tasks:
        raise RuntimeError('Empty browser inventory')
    base = ROOT / 'tmp/browser-runs'
    base.mkdir(parents=True, exist_ok=True)
    directory = Path(tempfile.mkdtemp(prefix='run-', dir=base))
    for step in ('assets.setup', 'assets.build'):
        prepared = run_command(
            [sys.executable, str(ROOT / 'scripts/local_run.py'), '--cwd', 'apps/review_web',
             'mix', step], cwd=ROOT, env=dict(os.environ, MIX_ENV='test'),
            log=directory / f'{step}.log', timeout=300)
        if prepared['exit'] != 0 or prepared['timeout']:
            raise RuntimeError(f'Browser preparation failed; see {directory / (step + ".log")}')
    jobs = worker_count(resources(), len(tasks), 4 * GIB, args.jobs)
    print(f'Browser run: {directory}; {len(tasks)} file tasks; worker ceiling={jobs}', flush=True)
    result = {'state': 'running', 'expected': [(p, f.name) for p, f in tasks], 'results': []}
    def save():
        pending = directory / 'status.json.tmp'
        pending.write_text(json.dumps(result, indent=2) + '\n')
        pending.replace(directory / 'status.json')
    save()
    try:
        with cancellation_scope(), ThreadPoolExecutor(max_workers=jobs) as pool:
            futures = [pool.submit(browser_file, profile, file, directory / profile / file.stem)
                       for profile, file in tasks]
            for future in futures:
                record = future.result()
                result['results'].append(record)
                print(f'{record["profile"]}/{record["file"]}: {"passed" if record["passed"] else "FAILED"}', flush=True)
                save()
        result['state'] = 'passed' if all(x['passed'] for x in result['results']) else 'failed'
    except BaseException:
        result['state'] = 'interrupted'
        raise
    finally:
        save()
    return 0 if result['state'] == 'passed' else 1


if __name__ == '__main__':
    raise SystemExit(main())
