#!/usr/bin/env python3
"""Validate existing Elixir/OTP; optionally provision pinned repository-local proof tools."""
from __future__ import annotations

import argparse
import json
import os
import re
import platform
import subprocess
from pathlib import Path

from doctor import check

OTP_QUERY = ('Root=code:root_dir(), Rel=erlang:system_info(otp_release), '
             'Path=filename:join([Root,"releases",Rel,"OTP_VERSION"]), '
             '{ok,Version}=file:read_file(Path), io:format("~s",[Version]), halt().')


def validate(profile: str, results: dict) -> list[str]:
    errors = []
    patterns = {
        "elixir": r"Elixir 1\.20\.4 \(compiled with Erlang/OTP 29\)",
        "mix": r"Mix 1\.20\.4 \(compiled with Erlang/OTP 29\)",
        "otp": r"\A29\.1\.2\s*\Z",
        "git": r"git version ",
    }
    if profile == "proofs":
        patterns.update({"elan": r"elan ", "lean": r"Lean \(version 4\.35\.0(?:[ ,)])",
                         "lake": r"Lean version 4\.35\.0(?:[ ,)])",
                         "bwrap": r"bubblewrap "})
    help_text = {
        "elixir": "Please expose your existing Elixir 1.20.4 (built with OTP 29) on PATH; if using asdf, activate that environment. We will not replace it.",
        "mix": "Please expose Mix 1.20.4 from the same Elixir installation on PATH.",
        "otp": "Please select the existing OTP 29.1.2 installation; its releases/29/OTP_VERSION must be readable.",
        "git": "Please make an existing Git installation available on PATH; no apt or sudo installation is performed.",
        "elan": "Run: uv run --locked python scripts/onboard.py --provision (installs Elan locally).",
        "lean": "Run: uv run --locked python scripts/onboard.py --provision (installs pinned Lean locally).",
        "lake": "Run: uv run --locked python scripts/onboard.py --provision (Lake is included with Lean).",
        "bwrap": "Please expose an existing bubblewrap installation for independent sandboxed checks; we will not change system packages or security policy.",
    }
    for name, pattern in patterns.items():
        result = results[name]
        if result["status"] != "ok" or not re.search(pattern, result.get("output") or ""):
            errors.append(f"{name}: missing, failed, or incompatible. {help_text[name]}")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profile", choices=("runtime", "proofs"), default="proofs")
    parser.add_argument("--provision", action="store_true", help="install pinned local proof tools after runtime validation")
    parser.add_argument("--json", type=Path, default=Path("tmp/onboard.json"))
    args = parser.parse_args()
    os.chdir(Path(__file__).resolve().parents[1])
    try:
        release = platform.freedesktop_os_release()
    except OSError:
        release = {}
    if release.get("ID") != "ubuntu" or release.get("VERSION_ID") != "26.04" or platform.machine() != "x86_64":
        print("This onboarding is built for Ubuntu 26.04 on x86_64 only; other environments are not designed or tested. Please use the supported environment.")
        return 1
    print("Hold Ledger onboarding — Ubuntu 26.04 x86_64. Existing Elixir/OTP will be checked; no system packages or global configuration will be changed.", flush=True)
    from provision import local_env, provision
    os.environ.update(local_env())
    if args.provision:
        runtime = {"elixir": check(["elixir", "--version"]),
                   "mix": check(["mix", "--version"]),
                   "otp": check(["erl", "-noshell", "-eval", OTP_QUERY]),
                   "git": check(["git", "--version"])}
        errors = validate("runtime", runtime)
        if errors:
            print(json.dumps({"status": "BLOCKED", "checks": runtime, "errors": errors}, indent=2))
            return 1
        print("Runtime prerequisites passed. Preparing pinned local Elan/Lean/Lake in ignored .local/ (downloads can take a few minutes).", flush=True)
        try:
            provision()
        except (RuntimeError, OSError, ValueError, subprocess.SubprocessError) as error:
            print(f"Local provisioning failed: {error}. Correct the reported issue and rerun this command; no system installer is used.")
            return 1
    commands = {"elixir": ["elixir", "--version"], "mix": ["mix", "--version"],
                "otp": ["erl", "-noshell", "-eval", OTP_QUERY], "git": ["git", "--version"]}
    if args.profile == "proofs":
        commands.update({name: [name, "--version"] for name in ("elan", "lean", "lake", "bwrap")})
    results = {}
    if args.profile == "proofs":
        # Listing installed toolchains is read-only. Do not invoke Elan shims
        # for Lean/Lake until the pinned toolchain exists: shims can download.
        installed = check(["elan", "toolchain", "list"])
        pinned = "leanprover/lean4:v4.35.0"
        ready = installed["status"] == "ok" and any(
            line.split()[0] == pinned for line in (installed["output"] or "").splitlines() if line.split()
        )
        if Path("lean-toolchain").read_text().strip() != pinned:
            ready = False
        results["installed_toolchains"] = installed
    else:
        ready = False
    for name, command in commands.items():
        if name in ("lean", "lake") and not ready:
            results[name] = {"tool": name, "command": command, "status": "blocked",
                             "output": "Not invoked: pinned Elan toolchain not confirmed installed; run onboard.py --provision to install locally."}
        else:
            if name in ("lean", "lake"):
                command = ["elan", "run", "leanprover/lean4:v4.35.0", *command]
            results[name] = check(command)
    errors = validate(args.profile, results)
    report = {"profile": args.profile, "checks": results, "errors": errors,
              "status": "BLOCKED" if errors else "PASS", "provision_requested": args.provision}
    args.json.parent.mkdir(parents=True, exist_ok=True)
    args.json.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))
    if not errors:
        print("Ready. Next: uv run --locked python scripts/local_run.py mix deps.get", flush=True)
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
