#!/usr/bin/env python3
"""Implementation of the zero-argument check_*.sh helpers."""
from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor, wait, FIRST_COMPLETED, CancelledError
import datetime as dt
import fcntl
import json
import os
from pathlib import Path
import selectors
import shlex
import subprocess
import sys
import tempfile
import threading
import time

from check_runtime import (cancel_running, cancellation_scope, copy_project,
                           resources, tracked_process, worker_environment,
                           GROUP_MEMORY_GIB, MUTANT_MEMORY_BYTES, GIB)

from check_scheduler import Demand, ResourcePool

ROOT = Path(__file__).resolve().parents[1]
OUTPUT_LOCK = threading.Lock()


def say(label: str, message: str) -> None:
    with OUTPUT_LOCK:
        print(f'[{label}] {message}', flush=True)


def command(argv: list[str], project: Path, label: str, log: Path, jobs: int, *,
            cpu_budget: int | None = None) -> int:
    env = worker_environment(jobs, project, cpu_budget=cpu_budget)
    say(label, '+ ' + shlex.join(argv))
    started = time.monotonic()
    log.parent.mkdir(parents=True, exist_ok=True)
    with log.open('ab') as output:
        output.write(('\n+ ' + shlex.join(argv) + '\n').encode('utf8'))
        output.flush()
        child = subprocess.Popen(argv, cwd=project, env=env, stdout=subprocess.PIPE,
                                 stderr=subprocess.STDOUT, start_new_session=True)
        with tracked_process(child), selectors.DefaultSelector() as selector:
            selector.register(child.stdout, selectors.EVENT_READ)
            pending = b''
            while selector.get_map():
                events = selector.select(timeout=15)
                if not events:
                    message = f'Still running: {time.monotonic() - started:.0f}s elapsed'
                    say(label, message)
                    output.write((message + '\n').encode('utf8'))
                    output.flush()
                for key, _ in events:
                    chunk = os.read(key.fd, 65536)
                    if not chunk:
                        selector.unregister(key.fileobj)
                        break
                    pending += chunk
                    # Write all bytes promptly, even without a trailing newline.
                    output.write(chunk)
                    output.flush()
                    while b'\n' in pending:
                        line, pending = pending.split(b'\n', 1)
                        say(label, line.decode('utf8', errors='replace'))
            if pending:
                say(label, pending.decode('utf8', errors='replace'))
            child.stdout.close()
            code = child.wait()
        message = f'Finished in {time.monotonic() - started:.1f}s (exit {code})'
        say(label, message)
        output.write((message + '\n').encode('utf8'))
        return code


def commands(group: str) -> list[list[str]]:
    python = [sys.executable]
    local = python + ['scripts/local_run.py']
    mix = local + ['mix']
    web = local + ['--cwd', 'apps/review_web', 'mix']
    if group == 'quick':
        return [mix + ['format', '--check-formatted'], mix + ['compile', '--warnings-as-errors'],
                mix + ['test', '--exclude', 'laws', '--warnings-as-errors'],
                mix + ['credo', '--strict'], mix + ['dialyzer'],
                python + ['-m', 'unittest', 'discover', '-s', 'tooling_tests', '-v'],
                python + ['scripts/run_laws.py', '--supported-only', '--inspect-only'],
                python + ['scripts/run_mutants.py']]
    if group == 'full':
        return [python + ['scripts/run_laws.py', '--supported-only', '--stage', 'full',
                          '--report', 'tmp/verification/checked.json']]
    if group == 'mutants':
        return [python + ['scripts/run_mutants.py', '--execute', '--report',
                          'tmp/verification/mutants.json']]
    if group == 'web':
        return [web + ['precommit'], web + ['docs', '--warnings-as-errors'],
                web + ['assets.setup'], web + ['assets.build'],
                python + ['-m', 'unittest', 'discover', '-s', 'apps/review_web/scripts',
                          '-p', 'test_*.py', '-v']]
    if group == 'differential':
        return [python + ['scripts/run_differential.py', '--samples', '100', '--timeout', '300']]
    if group == 'tutorials':
        return [python + ['scripts/check_tutorials.py']]
    if group == 'package':
        return [mix + ['run', 'scripts/demo.exs'], mix + ['docs', '--warnings-as-errors'],
                mix + ['hex.build']]
    if group == 'readings':
        return [local + ['env', 'MIX_ENV=test', 'mix', 'run',
                         'apps/review_web/scripts/produce_claim_readings.exs']]
    raise ValueError(f'Unknown check group: {group}')


def run_group(group: str, snapshot: Path, run_dir: Path, cpu_budget: int) -> dict:
    project = run_dir / 'workers' / group
    say(group, f'Preparing isolated workspace: {project}')
    copy_project(snapshot, project)
    for argv in commands(group):
        code = command(argv, project, group, run_dir / 'logs' / f'{group}.log', 1,
                       cpu_budget=cpu_budget)
        if code:
            return {'state': 'failed', 'exit': code, 'workspace': str(project)}
    return {'state': 'passed', 'exit': 0, 'workspace': str(project)}


def run_mutation_group(snapshot: Path, run_dir: Path, jobs: int, cpu_budget: int,
                       baseline: Path | None) -> dict:
    project = baseline if baseline is not None else run_dir / 'workers/mutants'
    if baseline is None:
        copy_project(snapshot, project)
    argv = commands('mutants')[0]
    if baseline is not None:
        argv += ['--baseline-report', 'tmp/verification/checked.json']
    argv += ['--jobs', str(jobs)]
    code = command(argv, project, 'mutants', run_dir / 'logs/mutants.log', jobs,
                   cpu_budget=cpu_budget)
    return {'state': 'passed' if code == 0 else 'failed', 'exit': code,
            'workspace': str(project)}


def schedule_groups(mode: str, snapshot: Path, run_dir: Path, capacity: dict,
                    jobs: int, report: dict, save) -> None:
    """Dispatch ready work within shared CPU/estimated-memory budgets."""
    pending = (['full', 'quick', 'web', 'differential', 'tutorials', 'package', 'readings']
               if mode == 'all' else [mode])
    active = {}
    reservations = ResourcePool(capacity, jobs)
    failed = False
    with ThreadPoolExecutor(max_workers=jobs) as pool:
        while pending or active:
            for group in list(pending):
                free = reservations.available()
                free_cpu, free_slots, free_memory = free['cpu'], free['slots'], free['memory']
                if free_cpu < 1 or free_slots < 1:
                    break
                if group == 'mutants':
                    workers = min(10, free_slots, free_cpu,
                                  max(0, free_memory) // MUTANT_MEMORY_BYTES)
                    if workers < 1:
                        if active:
                            continue
                        workers = 1  # An oversized task runs alone, never deadlocks.
                    memory = workers * MUTANT_MEMORY_BYTES
                    cpu = free_cpu
                    baseline = (Path(report['groups']['full']['workspace'])
                                if mode == 'all' else None)
                    launch = (run_mutation_group, snapshot, run_dir, workers, cpu, baseline)
                else:
                    workers = 1
                    memory = GROUP_MEMORY_GIB[group] * GIB
                    if memory > free_memory and active:
                        continue
                    # Divide free CPUs among work that actually fits, not jobs
                    # waiting for memory. A lone runnable group gets all CPUs.
                    remaining_memory = free_memory
                    ready = 0
                    for candidate in pending:
                        cost = (MUTANT_MEMORY_BYTES if candidate == 'mutants'
                                else GROUP_MEMORY_GIB[candidate] * GIB)
                        if cost <= remaining_memory:
                            count = (min(10, remaining_memory // cost)
                                     if candidate == 'mutants' else 1)
                            ready += count
                            remaining_memory -= count * cost
                    concurrency = max(1, min(free_slots, free_cpu, ready))
                    cpu = max(1, free_cpu // concurrency)
                    launch = (run_group, group, snapshot, run_dir, cpu)
                lease = reservations.try_acquire(group, Demand(cpu, memory, workers))
                if lease is None:
                    continue
                try:
                    future = pool.submit(*launch)
                except BaseException:
                    reservations.release(group)
                    raise
                allocation = {'oversized_singleton': lease['oversized_singleton'], 'cpu_budget': cpu, 'memory_estimate_bytes': memory,
                              'workers': workers}
                report.setdefault('allocations', {})[group] = allocation
                active[future] = (group, cpu, memory, workers)
                pending.remove(group)
                save()
            if not active:
                if pending:
                    raise RuntimeError(f'Insufficient resources for pending groups: {pending}')
                break
            completed, _ = wait(active, return_when=FIRST_COMPLETED)
            for future in completed:
                group, _, _, _ = active.pop(future)
                reservations.release(group)
                try:
                    result = future.result()
                except CancelledError:
                    result = {'state': 'cancelled'}
                except Exception as error:
                    result = {'state': 'failed', 'error': str(error)}
                report['groups'][group] = result
                save()
                if result['state'] != 'passed':
                    failed = True
                    reservations.cancel()
                    pending.clear()
                    cancel_running()
                    for other in active:
                        other.cancel()
                elif group == 'full' and mode == 'all' and not failed:
                    pending.append('mutants')
    if failed:
        raise RuntimeError('Check group failed; see per-group logs')


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=['quick', 'full', 'mutants', 'web', 'all'])
    parser.add_argument('--jobs', type=int)
    args = parser.parse_args()
    capacity = resources()
    jobs = args.jobs if args.jobs is not None else capacity['default_jobs']
    if jobs < 1:
        parser.error('--jobs must be positive')
    jobs = min(jobs, capacity['cpus'])
    base = ROOT / 'tmp/check-runs'
    base.mkdir(parents=True, exist_ok=True)
    # Setup mutates the main dependency directories; helpers must not race it.
    with (base / 'runner.lock').open('a') as lock, cancellation_scope():
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            parser.error('Another check helper is running in this checkout')
        run_dir = Path(tempfile.mkdtemp(prefix=dt.datetime.now(dt.timezone.utc).strftime('%Y%m%dT%H%M%SZ-'), dir=base))
        say('checks', f'Run directory: {run_dir}')
        say('checks', f'{capacity["cpus"]} available CPUs; '
            f'{capacity["available_memory_bytes"] / 1024**3:.1f} GiB available memory; worker ceiling={jobs}; '
            f'{capacity["memory_budget_bytes"] / GIB:.1f} GiB scheduling budget')
        report = {'mode': args.mode, 'resources': capacity, 'jobs': jobs, 'state': 'running', 'groups': {}}
        status = run_dir / 'status.json'
        def save():
            temporary = status.with_suffix('.json.tmp')
            temporary.write_text(json.dumps(report, indent=2) + '\n')
            temporary.replace(status)
        save()
        try:
            proof_tools = args.mode in ('all', 'full', 'mutants')
            setup = [[sys.executable, 'scripts/onboard.py', '--profile',
                      'proofs' if proof_tools else 'runtime', '--provision'],
                     [sys.executable, 'scripts/local_run.py', 'mix', 'deps.get'],
                     [sys.executable, 'scripts/verify_pins.py']]
            if args.mode in ('all', 'web'):
                setup.append([sys.executable, 'scripts/local_run.py', '--cwd', 'apps/review_web',
                              'mix', 'deps.get', '--check-locked'])
            for argv in setup:
                code = command(argv, ROOT, 'setup', run_dir / 'logs/setup.log', 1,
                               cpu_budget=capacity['cpus'])
                if code:
                    raise RuntimeError(f'Setup failed (exit {code})')
            snapshot = copy_project(ROOT, run_dir / 'snapshot')
            say('checks', f'Source snapshot ready: {snapshot}')
            schedule_groups(args.mode, snapshot, run_dir, capacity, jobs, report, save)
            report['state'] = 'passed'
            say('checks', f'All requested checks passed. Reports and workspaces: {run_dir}')
            return 0
        except KeyboardInterrupt:
            report.update(state='cancelled', error='Interrupted; no completed acceptance claimed')
            say('checks', 'Cancelled; child processes stopped')
            return 130
        except (RuntimeError, OSError, ValueError, subprocess.SubprocessError) as error:
            report.update(state='failed', error=str(error))
            say('checks', str(error))
            return 1
        finally:
            save()


if __name__ == '__main__':
    raise SystemExit(main())
