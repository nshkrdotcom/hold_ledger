#!/usr/bin/env python3
"""Bounded deterministic BEAM/compiled Lean/kernel comparisons on pinned tools."""
import argparse
import json
from pathlib import Path
import sys

from run_laws import run as run_command
from check_scheduler import managed_run

ROOT = Path(__file__).resolve().parents[1]


def validate_report(report_path: Path, samples: int) -> tuple[bool, str]:
    """Reject absent, failed or partial compiled/kernel results."""
    try:
        report = json.loads(report_path.read_text(encoding='utf8'))
        if not isinstance(report, dict):
            return False, 'report is not a JSON object'
        fields = ('accepted',)
        if any(report.get(field) is not True for field in fields):
            return False, 'differential result not accepted'
        attempted = report.get('attempted')
        if (type(attempted) is not int or attempted < samples
                or report.get('comparisons') != attempted
                or report.get('mismatches') != 0 or report.get('unsupported') != 0
                or report.get('kernel_cases') != 8 or report.get('evaluator_exit') != 0):
            return False, 'differential counts, evaluator or kernel pilot incomplete'
        return True, 'compiled/kernel differential report accepted'
    except (OSError, ValueError, TypeError) as exc:
        return False, f'cannot inspect differential report: {exc}'


@managed_run
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
    outcome = run_command(command, cwd=ROOT, env=None,
                          log=ROOT / 'tmp/differential/command.log', timeout=args.timeout)
    if outcome['timeout'] or outcome['exit'] != 0:
        print('Differential campaign failed or timed out; no acceptance', file=sys.stderr)
        return 1
    accepted, message = validate_report(report, args.samples)
    print(message, file=sys.stdout if accepted else sys.stderr)
    return 0 if accepted else 1



if __name__ == '__main__':
    raise SystemExit(main())
