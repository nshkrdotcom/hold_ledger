#!/usr/bin/env python3
"""Run one command with durable output and terminal status, independent of the chat."""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

from check_runtime import stop_tree


def save(path: Path, value: dict) -> None:
    pending = path.with_suffix('.tmp')
    pending.write_text(json.dumps(value, indent=2) + '\n')
    pending.replace(path)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory', required=True, type=Path)
    parser.add_argument('command', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    argv = args.command[1:] if args.command[:1] == ['--'] else args.command
    if not argv:
        parser.error('a command is required after --')
    directory = args.directory.resolve()
    directory.mkdir(parents=True, exist_ok=False)
    status = {'state': 'starting', 'command': argv, 'cwd': os.getcwd(),
              'pid': os.getpid(), 'started_utc': dt.datetime.now(dt.timezone.utc).isoformat()}
    status_path = directory / 'status.json'
    save(status_path, status)
    print(f'Job log: {directory / "output.log"}', flush=True)
    started = time.monotonic()
    child = None

    def cancel(signum, _frame):
        raise InterruptedError(f'Cancelled by signal {signum}')

    for sig in (signal.SIGINT, signal.SIGTERM):
        signal.signal(sig, cancel)
    code = 1
    with (directory / 'output.log').open('ab', buffering=0) as output:
        try:
            output.write((json.dumps(status) + '\n').encode())
            child = subprocess.Popen(argv, stdin=subprocess.DEVNULL, stdout=output,
                                     stderr=subprocess.STDOUT, start_new_session=True)
            status.update(state='running', child_pid=child.pid)
            save(status_path, status)
            code = child.wait()
            status.update(state='passed' if code == 0 else 'failed', exit_code=code)
        except InterruptedError as error:
            code = 130
            status.update(state='cancelled', exit_code=code, error=str(error))
        except Exception as error:
            status.update(state='failed', exit_code=code, error=str(error))
        finally:
            if child is not None:
                stop_tree(child.pid)
                child.wait()
            status.update(finished_utc=dt.datetime.now(dt.timezone.utc).isoformat(),
                          elapsed_seconds=time.monotonic() - started)
            output.write(('\nJOB RESULT ' + json.dumps(status) + '\n').encode())
            save(status_path, status)
    return code


if __name__ == '__main__':
    sys.exit(main())
