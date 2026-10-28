"""Operator-run actual BEAM crash/timeout/cancellation experiments.

Requires staged, pinned, explicitly trusted crash and hang snapshots containing
CONTROLLED_PART3_ENTERED markers; no fake uv or provider is used. These are
planted faults in disposable source, never authoritative payment policy.
"""
import argparse
import ctypes
import hashlib
import json
import os
from pathlib import Path
import select
import subprocess
import time


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("ids", type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[3]
    ids = json.loads(args.ids.read_text())
    witness = json.loads((root / "apps/review_web/priv/scenarios/P04.json").read_text())
    work = root / "tmp/part3_completion/lifecycle"
    work.mkdir(parents=True, exist_ok=True)
    libc = ctypes.CDLL(None, use_errno=True)
    outcomes = []
    for mode, name, expected in [("crash", "crash", 2), ("timeout", "hang", 124), ("cancel", "hang", 130)]:
        result = work / f"{mode}.result.json"
        result.unlink(missing_ok=True)
        log = result.with_suffix(".log")
        log.unlink(missing_ok=True)
        request = work / f"{mode}.json"
        request.write_text(json.dumps({"schema_version": 1, "request_id": f"controlled-{mode}-attempt",
            "snapshot_id": ids[name], "context_digest": digest({"mode": mode}),
            "input_digest": digest(witness), "witness": witness}))
        fd = libc.inotify_init1(os.O_NONBLOCK | os.O_CLOEXEC)
        if fd < 0 or libc.inotify_add_watch(fd, os.fsencode(work), 0x00000002 | 0x00000008 | 0x00000100) < 0:
            raise OSError("inotify unavailable")
        command = ["python3", str(root / "apps/review_web/scripts/part3_worker.py"), "--snapshot-root",
            str(root / "tmp/review_studio/snapshots" / ids[name]), "--request", str(request),
            "--result", str(result), "--timeout", "5" if mode == "timeout" else "20"]
        start = time.monotonic()
        proc = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        try:
            marker = "CONTROLLED_PART3_ENTERED_" + name.upper()
            if mode == "cancel":
                deadline = time.monotonic() + 15
                while marker not in (log.read_text() if log.exists() else ""):
                    remaining = deadline - time.monotonic()
                    if remaining <= 0 or not select.select([fd], [], [], remaining)[0]:
                        raise AssertionError("actual BEAM never reached the controlled cancellation boundary")
                    os.read(fd, 65536)
                # EOF is the real cancellation interface used by Port.close.
                proc.stdin.close()
            status = proc.wait(timeout=25)
            assert status == expected, (mode, status, log.read_text())
            assert marker in log.read_text(), (mode, "BEAM execution was not observed", log.read_text())
            assert not result.exists(), (mode, "fault became successful evidence")
            outcomes.append({"mode": mode, "exit": status, "snapshot_id": ids[name],
                "marker": marker, "elapsed_seconds": round(time.monotonic() - start, 3),
                "result_present": result.exists(), "input_digest": digest(witness)})
        finally:
            os.close(fd)
            if proc.poll() is None:
                proc.terminate()
                proc.wait(timeout=5)
            if not proc.stdin.closed:
                proc.stdin.close()
            proc.stdout.close()
    (work / "results.json").write_text(json.dumps(outcomes, indent=2) + "\n")
    print(json.dumps(outcomes, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
