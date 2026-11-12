"""Six required checker configurations over one export, with pinned Lake sandbox semantics."""
from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor
import json
import os
from pathlib import Path
import re
import shutil
import sys
import tempfile
import time

from check_resources import GIB
from check_scheduler import command_lease, execution_scope
from provision import local_env

EXTERNAL = {
    'Lean paranoid': ('leanchecker-paranoid', '--silent', '--from-export'),
    'lean4lean': ('lean4lean', '--import'),
    'nanoda': ('nanoda_bin',),
    'con-leche': ('con-leche',),
    'con-ron': ('con-ron',),
}


def sandbox_command(export: Path, name: str, directory: Path, prefix: Path, axioms) -> list[str]:
    sandbox = shutil.which(os.environ.get('COMPARATOR_BWRAP', 'bwrap'))
    environment = shutil.which('env')
    if not sandbox or not environment:
        raise RuntimeError('env and bwrap are required; sandbox bypass is not supported')
    directory.mkdir(parents=True, exist_ok=True)
    config = directory / 'config.json'
    config.write_text(json.dumps({'use_stdin': False, 'export_file_path': str(export),
        'permitted_axioms': sorted(axioms), 'unpermitted_axiom_hard_error': False,
        'num_threads': 4, 'nat_extension': True, 'string_extension': True}) + '\n')
    executable, *flags = EXTERNAL[name]
    binary = prefix / 'bin' / executable
    if not binary.is_file():
        raise RuntimeError(f'Missing pinned checker binary: {binary}')
    argv = [environment, '-i', sandbox, '--ro-bind', '/', '/', '--tmpfs', '/home',
            '--tmpfs', '/root', '--tmpfs', '/run/user', '--tmpfs', '/tmp',
            '--dir', '/tmp/home', '--dev', '/dev', '--proc', '/proc', '--clearenv',
            '--tmpfs', '/run', '--tmpfs', '/var']
    for path in (config, export, binary, prefix):
        argv.extend(['--ro-bind', str(path), str(path)])
    argv.extend(['--setenv', 'LEAN_ABORT_ON_PANIC', '1', '--setenv', 'HOME', '/tmp/home',
                 '--unshare-all', '--die-with-parent', '--new-session', '--chdir', '/tmp',
                 '--', str(binary), *flags, str(config if name == 'nanoda' else export)])
    return argv


def accepted(results: dict, axioms, required, allowed) -> bool:
    return (set(results) == set(required) and all(record.get('accepted') is True for record in results.values())
            and bool(axioms) and set(axioms) <= allowed)


def check_export(export: Path, *, label: str, timeout: int) -> dict:
    from run_laws import ROOT, LOCAL_RUN, CHECKERS, REQUIRED_AXIOMS, _run
    if not export.is_file() or export.stat().st_size == 0:
        raise RuntimeError(f'Missing/empty independent export: {export}')
    export = export.resolve()
    base = ROOT / 'tmp/verification/checkers'
    base.mkdir(parents=True, exist_ok=True)
    directory = Path(tempfile.mkdtemp(prefix=label + '-', dir=base))
    prefix = (ROOT / '.local/lean-4.35.0-linux').resolve(strict=True)
    started = time.monotonic()

    def run_checker(name):
        folder = directory / name.replace(' ', '-')
        folder.mkdir()
        if name == 'Lean default':
            argv = [sys.executable, str(LOCAL_RUN), 'lake', '--dir', 'deps/lynx/Lean',
                    'check', '--from-export', str(export)]
        else:
            argv = sandbox_command(export, name, folder, prefix, REQUIRED_AXIOMS)
        with command_lease('checker:' + name, memory=(4 if name == 'nanoda' else 2) * GIB,
                           max_cpu=4 if name == 'nanoda' else 1, pids=4 if name == 'nanoda' else 1) as lease:
            record = _run(argv, cwd=ROOT, env=local_env(), log=folder / 'output.log', timeout=timeout, lease=lease)
        text = (folder / 'output.log').read_text()
        record['accepted'] = record['exit'] == 0 and not record['timeout']
        if name == 'Lean default':
            record['accepted'] &= 'Lean default kernel accepts the solution' in text
        return name, record, text

    with execution_scope(directory), ThreadPoolExecutor(max_workers=len(CHECKERS)) as pool:
        checked = list(pool.map(run_checker, CHECKERS))
        results = {name: record for name, record, _text in checked}
        logs = {name: text for name, _record, text in checked}
        match = re.search(r'^Uses axioms:\s*(.*)$', logs['Lean default'], re.MULTILINE)
        axioms = [part.strip() for part in match[1].split(',')] if match else None
        normal_results = {name: record['accepted'] for name, record in results.items()}
        nanoda_fallback = None
        if (not results['nanoda']['accepted'] and 'stack overflow' in logs['nanoda']
                and all(record['accepted'] for name, record in results.items() if name != 'nanoda')
                and axioms and set(axioms) <= REQUIRED_AXIOMS):
            with command_lease('checker:nanoda-stack-retry', memory=4 * GIB) as lease:
                nanoda_fallback = _run([sys.executable, str(ROOT / 'scripts/check_nanoda_serial.py'), str(export)],
                    cwd=ROOT, env=local_env(), log=directory / 'nanoda-retry.log', timeout=timeout, lease=lease)
            text = (directory / 'nanoda-retry.log').read_text()
            nanoda_fallback['passed'] = (nanoda_fallback['exit'] == 0 and not nanoda_fallback['timeout']
                and bool(re.search(r'Checked \d+ declarations with no (?:typechecker )?errors', text)))
            results['nanoda']['accepted'] = nanoda_fallback['passed']
    passed = accepted(results, axioms, CHECKERS, REQUIRED_AXIOMS)
    report = {'path': str(export.relative_to(ROOT)), 'exit': 0 if passed else 1,
              'timeout': any(item['timeout'] for item in results.values()),
              'wall_seconds': time.monotonic() - started,
              'log': str(directory.relative_to(ROOT)), 'results': results,
              'checker_acceptance': {name: result['accepted'] for name, result in results.items()},
              'axiom_list': axioms, 'allowed_axioms': bool(axioms) and set(axioms) <= REQUIRED_AXIOMS,
              'passed': passed}
    if nanoda_fallback is not None:
        report.update(bundled_checker_acceptance=normal_results, nanoda_serial_retry=nanoda_fallback)
    (directory / 'result.json').write_text(json.dumps(report, indent=2) + '\n')
    return report


def main() -> int:
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('export', type=Path)
    parser.add_argument('--timeout', type=int, default=900)
    args = parser.parse_args()
    if args.timeout < 1:
        parser.error('--timeout must be positive')
    result = check_export(args.export, label='direct', timeout=args.timeout)
    print(json.dumps(result, indent=2), flush=True)
    return 0 if result['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
