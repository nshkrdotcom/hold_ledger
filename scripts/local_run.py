#!/usr/bin/env python3
"""Run a command with repository-local native tools, without global PATH edits."""
import argparse
import subprocess
import sys
from pathlib import Path
from provision import local_env, ROOT

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--cwd", type=Path, default=ROOT)
parser.add_argument("command", nargs=argparse.REMAINDER)
args = parser.parse_args()
if not args.command:
    parser.error("a command is required")
try:
    result = subprocess.run(args.command, cwd=args.cwd, env=local_env())
except FileNotFoundError as error:
    print(f"Could not run {args.command[0]!r}: {error}. Run onboarding with --provision, or expose the documented existing prerequisite on PATH.", file=sys.stderr)
    raise SystemExit(1)
raise SystemExit(result.returncode)
