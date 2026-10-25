#!/usr/bin/env python3
"""Observe local tool versions; this does not install or verify proofs."""
from __future__ import annotations
import argparse
import json
import os
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path


def check(argv: list[str]) -> dict:
    path = shutil.which(argv[0])
    if path is None:
        return {"tool": argv[0], "command": argv, "status": "missing", "output": None}
    if argv[0] in ("lean", "lake") and shutil.which("elan"):
        argv = ["elan", "run", "leanprover/lean4:v4.35.0", *argv]
    try:
        result = subprocess.run(argv, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=20, check=False)
        output = result.stdout + ("\n" + result.stderr if result.stderr else "")
        return {"tool": argv[0], "path": path, "command": argv,
                "status": "ok" if result.returncode == 0 else f"exit_{result.returncode}",
                "output": output.strip()[:8000]}
    except (OSError, subprocess.TimeoutExpired) as err:
        return {"tool": argv[0], "path": path, "command": argv, "status": "error", "output": str(err)}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--json", type=Path, help="optionally save report (use ignored tmp/ path)")
    args = parser.parse_args()
    from provision import local_env
    os.environ.update(local_env())
    commands = [
        ["uv", "--version"], ["elixir", "--version"], ["mix", "--version"],
        ["erl", "-noshell", "-eval", 'io:format("~s~n", [erlang:system_info(otp_release)]), halt().'],
        ["elan", "--version"], ["lean", "--version"], ["lake", "--version"],
        ["bwrap", "--version"], ["git", "--version"],
    ]
    report = {
        "observed_at_utc": datetime.now(timezone.utc).isoformat(),
        "python": sys.version.split()[0],
        "checks": [check(command) for command in commands],
        "warning": "OTP major version is not the required patch-level release; no proof is run by this script."
    }
    if args.json:
        args.json.parent.mkdir(parents=True, exist_ok=True)
        args.json.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
