#!/usr/bin/env python3
"""Run Phase 3 research-only Lean counterexample fixture with pinned local Lake.

#guard_msgs requires both negative control diagnostics, while the accepted
schedule must close by cbv. A missing compiler, timeout, or nonzero exit fails.
This is NOT a production law or one of the 49 registered obligations.
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

from provision import ROOT, local_env

FIXTURE = ROOT / "verification/research/0300_counterexample_pilot.lean"


def main() -> int:
    if not FIXTURE.is_file():
        print("research fixture missing", file=sys.stderr)
        return 1
    command = ["lake", "--dir", "deps/lynx/Lean", "env", "lean", str(FIXTURE)]
    try:
        check = subprocess.run(command, cwd=ROOT, env=local_env(),
                               capture_output=True, text=True, timeout=300)
    except (OSError, subprocess.TimeoutExpired) as error:
        print(f"Phase 3 research unresolved: {error}", file=sys.stderr)
        return 1
    if check.stdout:
        print(check.stdout)
    if check.stderr:
        print(check.stderr, file=sys.stderr)
    if check.returncode:
        print("Phase 3 research fixture FAILED; no counterexample result accepted",
              file=sys.stderr)
        return 1
    print("Phase 3 research Lean fixture compiled; negative cases guarded, "
          "positive bounded goal kernel-checked. NOT a runtime law.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
