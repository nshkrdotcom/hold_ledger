#!/usr/bin/env python3
"""Bounded subprocess supervisor for one operator-staged local replay.

STDIN EOF/cancel or SIGTERM kills the entire local subprocess group. The
process separation avoids mixing BEAM modules, NOT hostile-code sandboxing.
No shell, command from the browser, network fetch or dependency installation.
"""
import argparse
import json
import os
from pathlib import Path
import select
import signal
import subprocess
import sys
import time

MAX_TIMEOUT = 14_400


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--snapshot-root", type=Path, required=True)
    ap.add_argument("--request", type=Path, required=True)
    ap.add_argument("--result", type=Path, required=True)
    ap.add_argument("--timeout", type=int, default=120)
    ap.add_argument("--kind", choices=("pointwise", "formal"), default="pointwise")
    args = ap.parse_args()
    if not 1 <= args.timeout <= MAX_TIMEOUT:
        return 3
    root = args.snapshot_root.resolve(strict=True)
    manifest = root / ".part3-snapshot.json"
    if not manifest.is_file():
        return 3
    request = json.loads(args.request.read_text())
    meta = json.loads(manifest.read_text())
    if request.get("snapshot_id") != meta.get("snapshot_id") or root.name != meta.get("snapshot_id"):
        return 3
    if not (root / "scripts/local_run.py").is_file():
        return 3
    args.result.parent.mkdir(parents=True, exist_ok=True)
    work = root / "tmp/part3_build"
    work.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env.update({"MIX_ENV": "test", "MIX_BUILD_PATH": str(work / "_build"),
                "MIX_DEPS_PATH": str(work / "deps"),
                "HOLD_LEDGER_REVIEW_ROOT": str(root), "PORT": "0"})
    # Dependencies must already have been provisioned explicitly in this
    # isolated snapshot. A web request must never download/resolve packages.
    if args.kind == "pointwise":
        command = ["uv", "run", "--offline", "--locked", "python", "scripts/local_run.py",
                   "--cwd", "apps/review_web", "mix", "run", "scripts/part3_execution.exs",
                   "--", str(args.request), str(args.result)]
    else:
        # Direct use of the existing full, uncached, six-checker gate.
        command = ["uv", "run", "--offline", "--locked", "python", "scripts/run_laws.py",
                   "--supported-only", "--stage", "full", "--report", str(args.result)]
    log = args.result.with_suffix(".log")
    proc = None
    def terminate(*_, code=130):
        if proc is not None and proc.poll() is None:
            try:
                os.killpg(proc.pid, signal.SIGTERM)
                proc.wait(timeout=3)
            except (ProcessLookupError, subprocess.TimeoutExpired):
                try: os.killpg(proc.pid, signal.SIGKILL)
                except ProcessLookupError: pass
        raise SystemExit(code)
    signal.signal(signal.SIGTERM, terminate)
    signal.signal(signal.SIGINT, terminate)
    start = time.monotonic()
    with log.open("wb") as output:
        try:
            proc = subprocess.Popen(command, cwd=root, env=env, stdin=subprocess.DEVNULL,
                                    stdout=output, stderr=subprocess.STDOUT, start_new_session=True)
            while proc.poll() is None:
                if time.monotonic() - start >= args.timeout:
                    terminate(code=124)
                readable, _, _ = select.select([sys.stdin], [], [], 0.2)
                if readable and not sys.stdin.buffer.read1(1):
                    terminate()
            status = proc.wait()
            if log.stat().st_size > 100_000:
                # Limit evidence retained; no arbitrary unbounded stdout.
                with log.open("rb+") as truncated:
                    truncated.truncate(100_000)
            return 0 if status == 0 and args.result.is_file() else 2
        except OSError as e:
            output.write(str(e).encode()[:500])
            return 2


if __name__ == "__main__":
    sys.exit(main())
