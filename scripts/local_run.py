#!/usr/bin/env python3
"""Run a command with repository-local native tools, without global PATH edits."""
import argparse
import os
import subprocess
import sys
from pathlib import Path
from provision import local_env, ROOT
from prepare_lynx import prepare

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--cwd", type=Path, default=ROOT)
parser.add_argument("command", nargs=argparse.REMAINDER)
args = parser.parse_args()
if not args.command:
    parser.error("a command is required")
prepare()
# Git dependencies are not path dependencies: rebuild the changed command host
# before entering a test command, rather than relying on Mix to notice the patch.
mode = os.environ.get("MIX_ENV", "dev")
if "MIX_ENV=test" in args.command or "test" in args.command or "precommit" in args.command:
    mode = "test"
if args.cwd.resolve() == ROOT and mode == "test" and "mix" in args.command:
    source = ROOT / "deps/lynx/lib/lynx/commands.ex"
    beam = ROOT / "_build/test/lib/lynx/ebin/Elixir.Lynx.Commands.beam"
    action = args.command[args.command.index("mix") + 1:]
    if action and action[0] not in ("deps.get", "deps.compile") and source.exists():
        if not beam.exists() or source.stat().st_mtime_ns > beam.stat().st_mtime_ns:
            environment = dict(local_env(), MIX_ENV="test")
            compiled = subprocess.run(["mix", "deps.compile", "lynx", "--force"], cwd=ROOT, env=environment)
            if compiled.returncode:
                raise SystemExit(compiled.returncode)
try:
    result = subprocess.run(args.command, cwd=args.cwd, env=local_env())
except FileNotFoundError as error:
    print(f"Could not run {args.command[0]!r}: {error}. Run onboarding with --provision, or expose the documented existing prerequisite on PATH.", file=sys.stderr)
    raise SystemExit(1)
if result.returncode == 0 and args.command[:2] == ["mix", "deps.get"]:
    prepare()
raise SystemExit(result.returncode)
