#!/usr/bin/env python3
"""Fail if source/dependency/runtime versions differ from the repository pins."""
from __future__ import annotations

import json
import platform
import re
import subprocess
import sys
from pathlib import Path

from provision import ROOT, PINS, local_env

LYNX_COMMIT = "3b44de83fb63503e12b84233de70cf0647e7e63e"
ELIXIR = "1.20.4"
OTP = "29.1.2"
UV = "0.12.6"
PYTHON = "3.13.15"


def command(argv: list[str]) -> str:
    result = subprocess.run(argv, cwd=ROOT, env=local_env(), capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError(f"Pinned command failed (exit {result.returncode}): {argv[0:2]}")
    return (result.stdout + result.stderr).strip()


def main() -> int:
    try:
        os_release = platform.freedesktop_os_release()
        if os_release.get("ID") != "ubuntu" or os_release.get("VERSION_ID") != "26.04" or platform.machine() != "x86_64":
            raise RuntimeError("Only Ubuntu 26.04 x86_64 is a claimed supported runner")
        if (ROOT / "lean-toolchain").read_text().strip() != PINS["lean_toolchain"]:
            raise RuntimeError("Lean pin drift")
        lock = (ROOT / "mix.lock").read_text()
        if LYNX_COMMIT not in lock:
            raise RuntimeError("mix.lock Lynx full SHA mismatch")
        outputs = {
            "elixir": command(["elixir", "--version"]),
            "otp": command(["elixir", "-e",
                            "rel = :erlang.system_info(:otp_release) |> to_string(); "
                            "IO.write(File.read!(Path.join([to_string(:code.root_dir()), "
                            "\"releases\", rel, \"OTP_VERSION\"])))"]),
            "uv": command(["uv", "--version"]),
            "python": command(["uv", "run", "--locked", "python", "--version"]),
            "lean": command(["lean", "--version"]),
            "lake": command(["lake", "--version"]),
            "lynx": command(["git", "-C", "deps/lynx", "rev-parse", "HEAD"]),
        }
        if ELIXIR not in outputs["elixir"] or "compiled with Erlang/OTP 29" not in outputs["elixir"]:
            raise RuntimeError("Elixir build version drift")
        if outputs["otp"].strip() != OTP:
            raise RuntimeError("Full OTP_VERSION mismatch")
        if f"uv {UV} " not in outputs["uv"]:
            raise RuntimeError("uv version drift")
        if outputs["python"] != f"Python {PYTHON}":
            raise RuntimeError("Python version drift")
        if not re.search(r"Lean \(version 4\.35\.0", outputs["lean"]):
            raise RuntimeError("Lean version drift")
        if "Lake version 5.0.0" not in outputs["lake"]:
            raise RuntimeError("Lake version drift")
        if outputs["lynx"] != LYNX_COMMIT:
            raise RuntimeError("Resolved Lynx source does not match committed mix.lock")
        print(json.dumps({"status": "PASS", "runtime": outputs, "platform": os_release}, indent=2))
        return 0
    except (RuntimeError, OSError, ValueError) as error:
        print(f"PIN CHECK FAILED: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
