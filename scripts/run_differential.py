#!/usr/bin/env python3
"""Bounded deterministic BEAM/compiled Lean/kernel comparisons on pinned tools."""
import argparse
import hashlib
import json
import re
import os
from pathlib import Path
import signal
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
SHA256 = re.compile(r"[0-9a-f]{64}\Z")


def validate_report(report_path: Path, root: Path, samples: int) -> tuple[bool, str]:
    """Reject absent, stale, failed or partial compiled/kernel evidence."""
    try:
        report = json.loads(report_path.read_text(encoding='utf8'))
        if not isinstance(report, dict):
            return False, 'report is not a JSON object'
        fields = ('accepted', 'source_unchanged')
        if any(report.get(field) is not True for field in fields):
            return False, 'differential result not accepted on unchanged source'
        attempted = report.get('attempted')
        if (type(attempted) is not int or attempted < samples
                or report.get('comparisons') != attempted
                or report.get('mismatches') != 0 or report.get('unsupported') != 0
                or report.get('kernel_cases') != 8 or report.get('evaluator_exit') != 0):
            return False, 'differential counts, evaluator or kernel pilot incomplete'
        manifest = report.get('source_sha256')
        if not isinstance(manifest, dict) or not manifest:
            return False, 'source digest manifest missing'
        for rel, digest in manifest.items():
            if not isinstance(rel, str) or not isinstance(digest, str) or not SHA256.fullmatch(digest):
                return False, 'invalid source manifest entry'
            path = (root / rel).resolve()
            if not path.is_relative_to(root.resolve()) or not path.is_file():
                return False, f'unsafe or missing source file: {rel}'
            if hashlib.sha256(path.read_bytes()).hexdigest() != digest:
                return False, f'differential source drift: {rel}'
        if not {'lib/hold_ledger/ledger.ex', 'lib/hold_ledger/spec.ex',
                'scripts/differential.exs', 'scripts/run_differential.py'} <= set(manifest):
            return False, 'critical differential sources omitted from manifest'
        return True, 'source-bound compiled/kernel differential report accepted'
    except (OSError, ValueError, TypeError) as exc:
        return False, f'cannot inspect differential report: {exc}'


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
        code = child.wait(timeout=args.timeout)
        if code:
            print(f'Differential runner exited {code}; no acceptance', file=sys.stderr)
            return code
        accepted, message = validate_report(report, ROOT, args.samples)
        print(message, file=sys.stdout if accepted else sys.stderr)
        return 0 if accepted else 1
    except subprocess.TimeoutExpired:
        os.killpg(child.pid, signal.SIGKILL)
        child.wait()
        print('Differential campaign timed out; no acceptance', file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
