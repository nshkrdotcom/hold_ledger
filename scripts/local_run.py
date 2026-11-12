#!/usr/bin/env python3
"""Run a command with repository-local native tools, without global PATH edits."""
import argparse
import hashlib
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
# Mix must resolve a new git checkout *before* its version-specific patch is
# applied. Attempting to apply the new patch to yesterday's checkout prevents
# `mix deps.get` from running at all.
deps_get = args.command[:2] == ["mix", "deps.get"]
if not deps_get:
    prepare()
# Git dependencies are not path dependencies: rebuild the changed command host
# before entering a test command, rather than relying on Mix to notice the patch.
mode = os.environ.get("MIX_ENV", "dev")
if "MIX_ENV=test" in args.command or "test" in args.command or "precommit" in args.command:
    mode = "test"
if args.cwd.resolve() == ROOT and mode == "test" and "mix" in args.command:
    source = ROOT / "deps/lynx/lib/lynx/commands.ex"
    build = Path(os.environ.get("MIX_BUILD_PATH", str(ROOT / "_build/test")))
    if not build.is_absolute():
        build = ROOT / build
    beam = build / "lib/lynx/ebin/Elixir.Lynx.Commands.beam"
    action = args.command[args.command.index("mix") + 1:]
    if action and action[0] not in ("deps.get", "deps.compile") and source.exists():
        # Mix may retain an unpatched/stale BEAM despite changed Git dependency
        # files. A content fingerprint also catches timestamp-preserving restores.
        fingerprint = hashlib.sha256(source.read_bytes()).hexdigest()
        stamp = beam.parent / ".hold_ledger_lynx_commands_sha256"
        installed = stamp.read_text().strip() if stamp.exists() else None
        if (not beam.exists() or source.stat().st_mtime_ns > beam.stat().st_mtime_ns
                or installed != fingerprint):
            environment = dict(local_env(), MIX_ENV="test")
            compiled = subprocess.run(["mix", "deps.compile", "lynx", "--force"], cwd=ROOT, env=environment)
            if compiled.returncode:
                raise SystemExit(compiled.returncode)
            stamp.parent.mkdir(parents=True, exist_ok=True)
            stamp.write_text(fingerprint + "\n")
try:
    result = subprocess.run(args.command, cwd=args.cwd, env=local_env())
except FileNotFoundError as error:
    print(f"Could not run {args.command[0]!r}: {error}. Run onboarding with --provision, or expose the documented existing prerequisite on PATH.", file=sys.stderr)
    raise SystemExit(1)
if result.returncode == 0 and deps_get:
    prepare()
raise SystemExit(result.returncode)
