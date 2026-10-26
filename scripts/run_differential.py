#!/usr/bin/env python3
"""Bounded deterministic BEAM/compiled Lean/kernel comparisons on pinned tools."""
import argparse
import os
from pathlib import Path
import signal
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--samples', type=int, default=100)
    parser.add_argument('--timeout', type=int, default=300)
    args = parser.parse_args()
    if not 1 <= args.samples <= 10_000 or args.timeout <= 0:
        parser.error('samples must be 1..10000 and timeout must be positive')
    report = ROOT / 'tmp/differential/report.json'
    report.unlink(missing_ok=True)
    command = [sys.executable, str(ROOT / 'scripts/local_run.py'), 'env',
               'MIX_ENV=test', 'mix', 'run', 'scripts/differential.exs', str(args.samples)]
    child = subprocess.Popen(command, cwd=ROOT, start_new_session=True)
    try:
        return child.wait(timeout=args.timeout)
    except subprocess.TimeoutExpired:
        os.killpg(child.pid, signal.SIGKILL)
        child.wait()
        print('Differential campaign timed out; no acceptance', file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
