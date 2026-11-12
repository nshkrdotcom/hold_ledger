#!/usr/bin/env python3
"""Run independent generated Lean evaluation batches under the shared budget."""
from concurrent.futures import ThreadPoolExecutor
import json
import os
from pathlib import Path
import subprocess
import sys

from check_resources import GIB, resources
from check_runtime import tracked_process, worker_count
from check_scheduler import command_lease, delegate_parent, execution_scope, lease_command
from provision import local_env

ROOT = Path(__file__).resolve().parents[1]


def main():
    manifest = Path(sys.argv[1]).resolve()
    sources = [Path(path) for path in json.loads(manifest.read_text())]
    if not sources or len(set(sources)) != len(sources):
        raise ValueError('Evaluation sources must be nonempty and unique')
    delegate_parent()
    def evaluate(source):
        log = source.with_suffix('.log')
        with command_lease('differential:' + source.stem, memory=2 * GIB) as lease, log.open('wb') as output:
            argv = ['lake', '--dir', str(ROOT / 'deps/lynx/Lean'), 'env', 'lean', str(source)]
            process = subprocess.Popen(lease_command(argv, lease), cwd=ROOT, env=local_env(),
                stdin=subprocess.DEVNULL, stdout=output, stderr=subprocess.STDOUT, start_new_session=True)
            lease.started(process.pid)
            with tracked_process(process):
                code = process.wait(timeout=600)
        return code, log
    with execution_scope(manifest.parent):
        jobs = worker_count(resources(), len(sources), 2 * GIB)
        with ThreadPoolExecutor(max_workers=jobs) as pool:
            results = list(pool.map(evaluate, sources))
    for code, log in results:
        sys.stdout.write(log.read_text())
    return 0 if all(code == 0 for code, _ in results) else 1


if __name__ == '__main__':
    raise SystemExit(main())
