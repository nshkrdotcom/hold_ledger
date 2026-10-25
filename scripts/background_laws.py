#!/usr/bin/env python3
"""Launch a detached full formal run against a snapshot of the committed source."""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import traceback

ROOT = Path(__file__).resolve().parents[1]


def utc() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat()


def save_status(directory: Path, status: dict) -> None:
    temporary = directory / "status.json.tmp"
    temporary.write_text(json.dumps(status, indent=2, sort_keys=True) + "\n")
    temporary.replace(directory / "status.json")


def worker(directory: Path) -> int:
    status = json.loads((directory / "status.json").read_text())
    status.update(state="running", pid=os.getpid(), started_utc=utc())
    save_status(directory, status)
    child = None

    def cancel(_signum, _frame):
        if child is not None and child.poll() is None:
            os.killpg(child.pid, signal.SIGTERM)
        raise InterruptedError("Background formal run cancelled")

    signal.signal(signal.SIGTERM, cancel)
    try:
        source = directory / "source"
        subprocess.run(["git", "clone", "--shared", "--no-checkout", "--quiet", str(ROOT), str(source)], check=True)
        subprocess.run(["git", "checkout", "--quiet", "--detach", status["commit"]], cwd=source, check=True)
        for name in (".local", ".venv", "deps"):
            if (ROOT / name).exists():
                (source / name).symlink_to(ROOT / name, target_is_directory=True)
        command = ["uv", "run", "--locked", "python", "scripts/run_laws.py", "--supported-only",
                   "--stage", "full", "--timeout", "7200", "--checker-timeout", "1800",
                   "--report", "tmp/verification/complete.json"]
        status.update(source=str(source), command=command)
        save_status(directory, status)
        child = subprocess.Popen(command, cwd=source, stdin=subprocess.DEVNULL, start_new_session=True)
        status["runner_pid"] = child.pid
        save_status(directory, status)
        code = child.wait()
        report_path = source / "tmp/verification/complete.json"
        report = json.loads(report_path.read_text()) if report_path.is_file() else {}
        accepted = code == 0 and report.get("complete") is True and report.get("checker_claim") is True
        status.update(state="passed" if accepted else "failed", exit_code=code,
                      accepted_laws=sum(item.get("passed") is True for item in report.get("laws", {}).values()))
    except InterruptedError as exc:
        status.update(state="cancelled", error=str(exc))
    except Exception:
        status.update(state="failed", error=traceback.format_exc())
    finally:
        source = directory / "source/tmp/verification"
        try:
            for name in ("logs", "exports", "batch"):
                if (source / name).exists():
                    shutil.copytree(source / name, directory / name, dirs_exist_ok=True)
            if (source / "complete.json").exists():
                shutil.copy2(source / "complete.json", directory / "report.json")
        except OSError:
            status["artifact_copy_error"] = traceback.format_exc()
        status["finished_utc"] = utc()
        save_status(directory, status)
    return 0 if status["state"] == "passed" else 2


def start() -> Path:
    if subprocess.check_output(["git", "status", "--porcelain"], cwd=ROOT, text=True).strip():
        raise RuntimeError("Commit the source before starting a reproducible background run")
    commit = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    stamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    directory = ROOT / "tmp/verification" / ("background-" + stamp)
    directory.mkdir(parents=True)
    save_status(directory, {"state": "starting", "commit": commit, "created_utc": utc()})
    with (directory / "output.log").open("ab", buffering=0) as output:
        process = subprocess.Popen([sys.executable, "-u", str(Path(__file__).resolve()), "--worker", str(directory)],
                                   cwd=ROOT, stdin=subprocess.DEVNULL, stdout=output, stderr=subprocess.STDOUT,
                                   start_new_session=True, close_fds=True)
    (directory / "launcher.json").write_text(json.dumps({"pid": process.pid, "directory": str(directory)}, indent=2) + "\n")
    return directory


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--worker", type=Path, help=argparse.SUPPRESS)
    args = parser.parse_args()
    if args.worker:
        return worker(args.worker.resolve())
    print(start())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
