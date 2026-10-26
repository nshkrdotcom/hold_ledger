#!/usr/bin/env python3
"""Always-running gate: missing or skipped required formal work fails closed."""
import argparse
import os
import subprocess
from pathlib import Path

PREFIXES = ('lib/', 'test/laws/', 'test/support/', 'scripts/', 'tooling_tests/', 'verification/', '.github/', 'mutants/')
FILES = {'AGENTS.md', 'mix.exs', 'mix.lock', 'uv.lock', 'pyproject.toml',
         'lean-toolchain', '.tool-versions', '.python-version', 'verification/laws.json'}


def requires_formal(paths):
    return any(path in FILES or path.startswith(PREFIXES) for path in paths)


def gate_passes(detection, required, formal):
    return detection == 'success' and (required == 'false' or
                                       (required == 'true' and formal == 'success'))


def detect(base, head):
    if not base or set(base) == {'0'}:
        return True
    result = subprocess.run(['git', 'diff', '--name-only', base, head],
                            capture_output=True, text=True, check=False)
    return result.returncode != 0 or requires_formal(result.stdout.splitlines())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=['detect', 'gate'])
    args = parser.parse_args()
    if args.mode == 'gate':
        return 0 if gate_passes(os.environ.get('DETECTION_RESULT'),
                                os.environ.get('FORMAL_REQUIRED'),
                                os.environ.get('FORMAL_RESULT')) else 1
    required = os.environ.get('FORCE_FORMAL') == 'true' or detect(
        os.environ.get('DIFF_BASE', ''), os.environ.get('DIFF_HEAD', 'HEAD'))
    with Path(os.environ['GITHUB_OUTPUT']).open('a', encoding='utf8') as output:
        output.write(f"required={str(required).lower()}\n")
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
