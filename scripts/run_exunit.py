#!/usr/bin/env python3
"""Balance test files across independent BEAM VMs with private builds and temp stores."""
from __future__ import annotations

import argparse
import fcntl
from concurrent.futures import ThreadPoolExecutor
import json
import os
from pathlib import Path
import re
import sys
import tempfile

from check_resources import GIB, resources
from check_runtime import copy_directory, worker_count, worker_environment
from check_scheduler import command_lease, managed_run
from run_laws import _run, run

ROOT = Path(__file__).resolve().parents[1]


def shard_files(files: list[Path], jobs: int, durations: dict) -> list[list[Path]]:
    """Greedy longest-first balancing; every selected file appears exactly once."""
    shards = [[] for _ in range(min(jobs, len(files)))]
    weights = [0.0] * len(shards)
    for file in sorted(files, key=lambda p: (-durations.get(str(p), p.stat().st_size), str(p))):
        index = min(range(len(shards)), key=lambda i: (weights[i], i))
        shards[index].append(file)
        weights[index] += durations.get(str(file), file.stat().st_size)
    return shards


def copy_test_build(project: Path, destination: Path):
    source = Path(os.environ.get('MIX_BUILD_PATH', str(project / '_build/test')))
    if not source.is_absolute():
        source = project / source
    copy_directory(source, destination)
    # Reflinks preserve relative symlinks; relocated priv/include links must still
    # address the original immutable source directories.
    for link in destination.rglob('*'):
        if link.is_symlink():
            target = (source / link.relative_to(destination)).resolve()
            link.unlink()
            link.symlink_to(target, target_is_directory=target.is_dir())


@managed_run
def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--project', type=Path, default=ROOT)
    parser.add_argument('--jobs', type=int)
    parser.add_argument('--prepared', action='store_true', help='caller already compiled the test build')
    parser.add_argument('--seed', type=int, default=12345)
    args = parser.parse_args()
    project = args.project.resolve()
    if args.jobs is not None and args.jobs < 1:
        parser.error('--jobs must be positive')
    files = sorted(p for p in (project / 'test').rglob('*_test.exs') if 'laws' not in p.relative_to(project / 'test').parts)
    if not files:
        raise RuntimeError('Empty ExUnit file inventory')
    base = ROOT / 'tmp/exunit-runs'
    base.mkdir(parents=True, exist_ok=True)
    directory = Path(tempfile.mkdtemp(prefix='run-', dir=base))
    if not args.prepared:
        prepared = run([sys.executable, str(ROOT / 'scripts/local_run.py'), '--cwd', str(project),
                        'mix', 'compile', '--warnings-as-errors'], cwd=ROOT,
                       env=dict(os.environ, MIX_ENV='test'), log=directory / 'compile.log', timeout=600)
        if prepared['exit'] != 0 or prepared['timeout']:
            return 1
    jobs = worker_count(resources(), len(files), 2 * GIB, args.jobs)
    history_path = ROOT / '.local/checks/exunit-durations.json'
    profile = str((os.uname().nodename, str(project.relative_to(ROOT)), resources()['cpus']))
    try:
        history = json.loads(history_path.read_text()).get(profile, {})
    except (OSError, ValueError):
        history = {}
    durations = {str(project / name): value for name, value in history.items()}
    shards = shard_files(files, jobs, durations)
    print(f'ExUnit run: {directory}; {len(files)} files in {len(shards)} private VMs', flush=True)

    def execute(index, selected):
        shard = directory / str(index)
        shard.mkdir()
        temp = shard / 'temp'
        temp.mkdir()
        with command_lease(f'exunit:{project.name}:{index}', memory=2 * GIB,
                           max_cpu=max(1, resources()['cpus'] // jobs)) as lease:
            build = shard / 'build'
            copy_test_build(project, build)
            env = worker_environment(1, cpu_budget=lease.allocation['cpu'])
            env.update(MIX_ENV='test', MIX_BUILD_PATH=str(build), TMPDIR=str(temp),
                       HOLD_LEDGER_EXUNIT_FORMATTER=str(ROOT / 'scripts/exunit_timing.exs'),
                       HOLD_LEDGER_EXUNIT_TIMINGS=str(shard / 'timings.json'))
            argv = [sys.executable, str(ROOT / 'scripts/local_run.py'), '--cwd', str(project),
                    'mix', 'test', '--no-compile', '--no-deps-check', '--exclude', 'laws',
                    '--warnings-as-errors', '--seed', str(args.seed),
                    *[str(file.relative_to(project)) for file in selected]]
            outcome = _run(argv, cwd=ROOT, env=env, log=shard / 'output.log', timeout=1800, lease=lease)
        text = (shard / 'output.log').read_text()
        count = re.search(r'Result: (\d+) passed', text)
        return {'files': [str(p.relative_to(project)) for p in selected], 'execution': outcome,
                'passed': outcome['exit'] == 0 and not outcome['timeout'] and count is not None,
                'tests': int(count[1]) if count else 0,
                'file_seconds': json.loads((shard / 'timings.json').read_text()) if (shard / 'timings.json').exists() else {}}

    report = {'state': 'running', 'project': str(project), 'seed': args.seed,
              'expected_files': [str(p.relative_to(project)) for p in files], 'shards': []}
    def save():
        pending = directory / 'status.json.tmp'
        pending.write_text(json.dumps(report, indent=2) + '\n')
        pending.replace(directory / 'status.json')
    save()
    try:
        with ThreadPoolExecutor(max_workers=jobs) as pool:
            futures = [pool.submit(execute, i, selected) for i, selected in enumerate(shards)]
            for future in futures:
                report['shards'].append(future.result())
                save()
        actual = [p for shard in report['shards'] for p in shard['files']]
        passed = sorted(actual) == sorted(report['expected_files']) and all(s['passed'] for s in report['shards'])
        report.update(state='passed' if passed else 'failed', tests=sum(s['tests'] for s in report['shards']))
        if passed:
            observed = {}
            for shard in report['shards']:
                for file, seconds in shard['file_seconds'].items():
                    path = Path(file)
                    path = path if path.is_absolute() else project / path
                    if path in files:
                        observed[str(path.relative_to(project))] = seconds
            history_path.parent.mkdir(parents=True, exist_ok=True)
            with history_path.with_suffix('.lock').open('a') as lock:
                fcntl.flock(lock, fcntl.LOCK_EX)
                try:
                    history = json.loads(history_path.read_text())
                except (OSError, ValueError):
                    history = {}
                history[profile] = observed
                pending = history_path.with_suffix('.tmp')
                pending.write_text(json.dumps(history, indent=2) + '\n')
                pending.replace(history_path)
    except BaseException:
        report['state'] = 'interrupted'
        raise
    finally:
        save()
    print(f'ExUnit aggregate: {report["state"]}; {report["tests"]} tests/properties; report {directory / "status.json"}', flush=True)
    return 0 if passed else 1


if __name__ == '__main__':
    raise SystemExit(main())
