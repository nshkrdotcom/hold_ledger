#!/usr/bin/env python3
"""Uncached Lynx laws with per-group exported independent checks.

Use --inspect-only without BEAM. Executing requires the pinned local
Elixir/Mix and Lean/Lake. No failed/absent law or export can count as passing.
Logs and raw exports live under ignored tmp/verification/. Preserve a compact JSON
measurement with --report for each execution baseline. Cache-enabled runs are timing only.
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
import re
import subprocess
import signal
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "verification/laws.json"
LOCAL_RUN = ROOT / "scripts/local_run.py"
CHECKERS = (
    "Lean paranoid", "lean4lean", "nanoda", "con-leche", "con-ron", "Lean default"
)
REQUIRED_AXIOMS = frozenset(("propext", "Quot.sound", "Classical.choice"))
FORBIDDEN = re.compile(r"\b(?:sorry|admit|axiom|unsafe|native_decide)\b")
LAW_SUCCESS = re.compile(r"(?m)^Result: 1 passed\s*$")



def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def git_revision() -> str | None:
    proc = subprocess.run(["git", "rev-parse", "HEAD"], cwd=ROOT,
                          capture_output=True, text=True, check=False)
    return proc.stdout.strip() if proc.returncode == 0 else None


def inspect_shared_sources(directory: Path | None = None) -> list[Path]:
    directory = directory or ROOT / "test/support/lean"
    sources = sorted(directory.rglob("*.lean"))
    for source in sources:
        if FORBIDDEN.search(source.read_text(encoding="utf8")):
            raise RuntimeError(f"Forbidden proof escape in {source}")
    return sources


def inspect_manifest() -> list[dict]:
    inspect_shared_sources()
    catalog = json.loads(MANIFEST.read_text(encoding="utf8"))
    if catalog["revision"] != "authorization-holds-v1":
        raise RuntimeError("Unexpected ledger contract revision")
    laws = catalog["laws"]
    if len(laws) != 29 or len({entry["slug"] for entry in laws}) != len(laws):
        raise RuntimeError("Expected exactly 29 unique law groups for the ledger contract")
    wanted = {"L1", "L2", "L3", "L4", "L5", "L6", "PO-I", "PO-A1", "PO-A2",
              "PO-A3", "PO-A4", "PO-S", "PO-C1", "PO-C2", "PO-B2", "PO-B3",
              "PO-B4", "PO-B5/declined", "PO-B5/voided", "PO-B6", "PO-B7", "PO-C3"}
    wanted |= {f"PO-B1/{event}" for event in
               ("dispatch", "timeout", "restart", "retry", "processor_result", "void")}
    if {item["id"] for item in laws} != wanted:
        raise RuntimeError("Formal obligation coverage differs from the verification guide")
    for entry in laws:
        file = ROOT / entry["file"]
        witness = ROOT / entry["witness"]
        if not file.is_file() or not witness.is_file() or not file.resolve().is_relative_to(ROOT):
            raise RuntimeError(f"Missing law/witness source: {entry['slug']}")
        text = file.read_text(encoding="utf8")
        if FORBIDDEN.search(text):
            raise RuntimeError(f"Forbidden proof escape in {entry['file']}")
        if text.count("laws ") != 1 or text.count("    law(") != 1 or text.count('proof: ~LEAN"""') != 1:
            raise RuntimeError(f"Expected a single authored Lynx law: {entry['file']}")
        for term in (f'laws "{entry["slug"]}"', f'law({entry["law"]}(', "requires:", "expects:",
                     "HoldLedger.{Ledger, Spec}"):
            if term not in text:
                raise RuntimeError(f"{entry['slug']} missing {term}")
        if entry["priority"] not in ("L", "P0", "P1"):
            raise RuntimeError(f"Wrong priority for {entry['slug']}")
    return laws


def run(argv: list[str], *, cwd: Path, env: dict[str, str] | None,
        log: Path, timeout: int) -> dict:
    log.parent.mkdir(parents=True, exist_ok=True)
    started = time.monotonic()
    process = subprocess.Popen(argv, cwd=cwd, text=True,
                               stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                               start_new_session=True, env=env)
    try:
        output, _ = process.communicate(timeout=timeout)
        code, timed_out = process.returncode, False
    except subprocess.TimeoutExpired:
        # The wrapper launches BEAM/Lake/Lean children which retain stdout.
        # Terminate the whole isolated command group so timeout actually ends.
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        output, _ = process.communicate()
        code, timed_out = None, True
    elapsed = round(time.monotonic() - started, 3)
    log.write_text(output, encoding="utf8")
    return {"command": argv, "cwd": str(cwd), "exit": code, "timeout": timed_out,
            "wall_seconds": elapsed, "log": str(log.relative_to(ROOT))}


def exported_checker_record(path: Path, *, label: str, timeout: int) -> dict:
    path = path.resolve()
    if not path.is_file() or path.stat().st_size == 0:
        raise RuntimeError(f"Missing/empty independent export: {path}")
    argv = [sys.executable, str(LOCAL_RUN), "lake", "--dir", "deps/lynx/Lean",
            "check", "--paranoid", "--from-export", str(path.resolve())]
    log = ROOT / "tmp/verification/logs" / f"{label}-paranoid.log"
    outcome = run(argv, cwd=ROOT, env=None, log=log, timeout=timeout)
    output = log.read_text(encoding="utf8")
    observed = {name: f"{name} kernel accepts the solution" in output
                for name in CHECKERS}
    axioms_line = re.search(r"^Uses axioms:\s*(.*)$", output, re.MULTILINE)
    reported_axioms = ([part.strip() for part in axioms_line.group(1).split(",")]
                       if axioms_line else None)
    only_nanoda_stack = (not observed["nanoda"] and all(v for k,v in observed.items() if k != "nanoda")
                         and "stack overflow" in output)
    if only_nanoda_stack and reported_axioms is None:
        audit_log = ROOT / "tmp/verification/logs" / f"{label}-axioms.log"
        audit = run([sys.executable, str(LOCAL_RUN), "lake", "--dir", "deps/lynx/Lean",
                     "check", "--from-export", str(path)], cwd=ROOT, env=None,
                    log=audit_log, timeout=timeout)
        audit_text = audit_log.read_text(encoding="utf8")
        audit_line = re.search(r"^Uses axioms:\s*(.*)$", audit_text, re.MULTILINE)
        if audit["exit"] == 0 and audit_line:
            reported_axioms = [part.strip() for part in audit_line.group(1).split(",")]
        outcome["axiom_audit"] = audit
    authorized_axioms = (reported_axioms is not None and bool(reported_axioms)
                         and set(reported_axioms) <= REQUIRED_AXIOMS)
    # A stack-overflow crash is a resource failure, not a kernel rejection.
    # Keep the failed bundled run and require the same pinned Nanoda binary
    # to actually accept the same export in an equally sandboxed serial run.
    serial_ok = False
    if (not observed["nanoda"] and all(v for k, v in observed.items() if k != "nanoda")
            and "stack overflow" in output and authorized_axioms):
        serial_log = ROOT / "tmp/verification/logs" / f"{label}-nanoda-serial.log"
        serial = run([sys.executable, str(ROOT / "scripts/check_nanoda_serial.py"), str(path.resolve())],
                     cwd=ROOT, env=None, log=serial_log, timeout=timeout)
        serial_text = serial_log.read_text(encoding="utf8")
        serial_ok = serial["exit"] == 0 and bool(re.search(r"Checked \d+ declarations with no (?:typechecker )?errors", serial_text))
        serial["passed"] = serial_ok
        outcome["bundled_checker_acceptance"] = dict(observed)
        outcome["nanoda_serial_retry"] = serial
        observed["nanoda"] = serial_ok
    outcome.update(export_sha256=sha(path), export_bytes=path.stat().st_size,
                   path=str(path.relative_to(ROOT)), checker_acceptance=observed,
                   axiom_list=reported_axioms, allowed_axioms=authorized_axioms,
                   passed=((outcome["exit"] == 0 or serial_ok) and all(observed.values()) and authorized_axioms))
    return outcome


def supported_laws(laws: list[dict]) -> list[dict]:
    """Require the complete catalog; never silently drop a formal obligation."""
    if len(laws) != 29 or any(law.get("status") != "supported" for law in laws):
        raise RuntimeError("All 29 cataloged law groups must remain supported")
    return laws


def valid_law_result(output: str) -> bool:
    """A zero-test or omitted Lynx invocation is never proof success."""
    return (bool(LAW_SUCCESS.search(output))
            and "Checked Elixir.HoldLedger." in output
            and ".laws in " in output)


def valid_batch_report(report: dict, laws: list[dict]) -> bool:
    if not laws:
        return False
    records = report.get("laws", {})
    reports = report.get("reports", [])
    if set(records) != {law["slug"] for law in laws} or not reports:
        return False
    if any(item.get("status") != "ok" or item.get("cached") is True for item in reports):
        return False
    for law in laws:
        record = records[law["slug"]]
        expected = f"{law['law']}/{law['arity']}"
        matching = [item for item in reports if item.get("module") == record.get("module", "") + ".laws"]
        if (record.get("passed") is not True or record.get("laws") != [expected]
                or len(matching) != 1
                or [item.get("name") for item in matching[0].get("theorems", [])] != [expected]):
            return False
    return True


def batch_execution(laws: list[dict], timeout: int, checker_timeout: int, stage: str) -> dict:
    import shutil
    directory = ROOT / "tmp/verification/batch"
    directory.mkdir(parents=True, exist_ok=True)
    selection = directory / "selection.json"
    native_report = directory / "native.json"
    native_report.unlink(missing_ok=True)
    selection.write_text(json.dumps(laws, indent=2) + "\n")
    export_root = ROOT / "tmp/verification/exports/full-suite"
    if export_root.exists():
        shutil.rmtree(export_root)
    export_root.mkdir(parents=True)
    export = export_root / "suite.ndjson"
    env = dict(os.environ, MIX_ENV="test", LYNX_CACHE="0")
    env.pop("LYNX_EXPORT", None)
    env.pop("HOLD_LEDGER_PROOF_CACHE", None)
    command = [sys.executable, str(LOCAL_RUN), "mix", "run", "scripts/verify_laws.exs",
               str(selection), str(native_report), str(export) if stage == "full" else "none"]
    outcome = run(command, cwd=ROOT, env=env, log=ROOT / "tmp/verification/logs/full-suite-lynx.log",
                  timeout=timeout)
    native = json.loads(native_report.read_text()) if native_report.is_file() else {}
    verified = outcome["exit"] == 0 and valid_batch_report(native, laws)
    exports = sorted(export_root.rglob("*.ndjson"))
    correct_export = exports == [export] and export.stat().st_size > 0 if exports else False
    checks = ([exported_checker_record(export, label="full-suite", timeout=checker_timeout)]
              if stage == "full" and correct_export else [])
    accepted = verified and (stage == "proofs" or (correct_export and all(check["passed"] for check in checks)))
    sources = [ROOT / p for p in ("lib/hold_ledger/ledger.ex", "lib/hold_ledger/spec.ex", "mix.lock",
               "lean-toolchain", "verification/laws.json", "test/support/proof_case.ex", "scripts/verify_laws.exs",
               "scripts/run_laws.py", "test/support/lean/library.json")]
    sources += inspect_shared_sources() + [ROOT / law["file"] for law in laws]
    result = {"mode": "EXECUTED", "date_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
              "commit": git_revision(), "stage": stage, "cache": "LYNX_CACHE=0", "batch": True,
              "source_sha256": {str(path.relative_to(ROOT)): sha(path) for path in sources},
              "execution": outcome, "native_report": str(native_report.relative_to(ROOT)), "exports": checks,
              "correct_export": correct_export, "complete": accepted, "laws": {},
              "checker_claim": stage == "full" and accepted, "accepted_proof_claim": verified}
    for law in laws:
        result["laws"][law["slug"]] = {"id": law["id"], "source": law["file"], "source_sha256": sha(ROOT / law["file"]),
            "passed": accepted, "native_passed": verified, "exports": checks}
        print(f"{law['slug']}: {'PASS' if accepted else 'UNVERIFIED/FAIL'} (shared cold batch, stage={stage})", flush=True)
    return result


def execution(laws: list[dict], timeout: int, checker_timeout: int,
              *, stage: str = "full", cache_mode: str = "cold") -> dict:
    if len(laws) > 1 and cache_mode == "cold":
        return batch_execution(laws, timeout, checker_timeout, stage)
    measurements = {"mode": "EXECUTED", "date_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
                    "commit": git_revision(), "source_sha256":
                        {str(path): sha(ROOT / path) for path in
                         ("lib/hold_ledger/ledger.ex", "lib/hold_ledger/spec.ex",
                          "mix.lock", "lean-toolchain", "verification/laws.json",
                          "test/support/proof_case.ex", "scripts/verify_laws.exs", "test/support/lean/library.json",
                          *[str(p.relative_to(ROOT)) for p in inspect_shared_sources()])},
                    "cache": "LYNX_CACHE=0" if cache_mode == "cold" else "warm, Lynx cache enabled",
                    "stage": stage, "export_mode": ("LYNX_EXPORT=tmp/verification/exports/<group>"
                                                   if stage == "full" else "no exports"),
                    "sandbox": "paranoid checker default; no sandbox bypass", "laws": {}}
    for law in laws:
        label = law["slug"]
        export_root = ROOT / "tmp/verification/exports" / label
        if export_root.exists():
            # This is a per-law scratch export path; remove only that directory,
            # preventing old exports from satisfying today's independent check.
            import shutil
            if not export_root.resolve().is_relative_to(ROOT / "tmp/verification/exports"):
                raise RuntimeError("Unsafe export path")
            shutil.rmtree(export_root)
        export_root.mkdir(parents=True)
        env = os.environ.copy()
        if cache_mode == "cold":
            env["LYNX_CACHE"] = "0"
        else:
            env.pop("LYNX_CACHE", None)
        env.pop("LYNX_EXPORT", None)
        env.pop("HOLD_LEDGER_PROOF_CACHE", None)
        if stage == "full":
            env["LYNX_EXPORT"] = f"tmp/verification/exports/{label}"
        env["LYNX_DEBUG"] = "lean"
        argv = [sys.executable, str(LOCAL_RUN), "mix", "test", law["file"],
                "--only", "laws", "--seed", "12345"]
        elixir_outcome = run(argv, cwd=ROOT, env=env,
                             log=ROOT / f"tmp/verification/logs/{label}-lynx.log", timeout=timeout)
        output = (ROOT / elixir_outcome["log"]).read_text(encoding="utf8")
        validated_law = elixir_outcome["exit"] == 0 and valid_law_result(output)
        exports = sorted(export_root.rglob("*.ndjson")) if stage == "full" else []
        checks = ([exported_checker_record(export, label=f"{label}-{i}", timeout=checker_timeout)
                   for i, export in enumerate(exports, 1)] if stage == "full" else [])
        expected_basename = f"laws-{label}.ndjson"
        right_export = (len(exports) == 1 and exports[0].name == expected_basename
                        and exports[0].stat().st_size > 0)
        if stage != "full":
            # No exported checker claim is made by the proof-only/warm stage.
            right_export = False
        elixir_outcome.update(id=law["id"], priority=law["priority"], source=law["file"],
                              source_sha256=sha(ROOT / law["file"]),
                              exports=checks, correct_export=right_export,
                              one_law_test=validated_law,
                              passed=(validated_law and (stage == "proofs" or
                                      (right_export and all(check["passed"] for check in checks)))))
        measurements["laws"][label] = elixir_outcome
        print(f"{label}: {'PASS' if elixir_outcome['passed'] else 'UNVERIFIED/FAIL'} "
              f"(Lynx exit={elixir_outcome['exit']}, test={validated_law}, exports={len(exports)}, "
              f"paranoid={all(x['passed'] for x in checks) if checks else False})", flush=True)
    measurements["complete"] = (bool(laws) and
                                all(x["passed"] for x in measurements["laws"].values()))
    measurements["checker_claim"] = stage == "full" and cache_mode == "cold"
    measurements["accepted_proof_claim"] = cache_mode == "cold"
    return measurements


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--inspect-only", action="store_true", help="static validation, no native success claim")
    parser.add_argument("--slug", action="append", help="restrict to one or more exact law slugs")
    parser.add_argument("--priority", choices=("L", "P0", "P1"), help="restrict laws by stage")
    parser.add_argument("--supported-only", action="store_true", help="require and select all 29 supported groups")
    parser.add_argument("--stage", choices=("full", "proofs"), default="full",
                        help="full=uncached proof+export+six checkers; proofs=no export/checker claim")
    parser.add_argument("--cache-mode", choices=("cold",), default="cold",
                        help="acceptance always uses cold verification")
    parser.add_argument("--timeout", type=int, default=1800, help="seconds for the selected proof request (one group or a shared batch)")
    parser.add_argument("--checker-timeout", type=int, default=900, help="per-export checker seconds")
    parser.add_argument("--report", type=Path, help="persist complete execution report JSON")
    args = parser.parse_args()
    try:
        laws = inspect_manifest()
        if args.supported_only:
            laws = supported_laws(laws)
            print("Supported proof selection: all 29 cataloged law groups; none excluded.", flush=True)
        if args.slug:
            unknown = set(args.slug) - {law["slug"] for law in laws}
            if unknown:
                raise RuntimeError(f"Unknown law slug(s): {sorted(unknown)}")
            laws = [law for law in laws if law["slug"] in args.slug]
        if args.priority:
            laws = [law for law in laws if law["priority"] == args.priority]
        if not laws:
            raise RuntimeError("Empty law selection is not a proof")
        if args.inspect_only:
            print(f"Catalog valid: {len(laws)} law groups checked statically; "
                  "BEAM, Lynx, Lean and exports NOT RUN")
            return 0
        if args.cache_mode == "warm":
            raise RuntimeError("Shared-theory verification requires cold checks; warm cache runs are not supported")
        if args.timeout <= 0 or args.checker_timeout <= 0:
            raise RuntimeError("Timeouts must be positive")
        result = execution(laws, args.timeout, args.checker_timeout,
                           stage=args.stage, cache_mode=args.cache_mode)
        if args.report:
            output = args.report.resolve()
            if not output.is_relative_to(ROOT):
                raise RuntimeError("Report path must stay within source checkout")
            output.parent.mkdir(parents=True, exist_ok=True)
            output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf8")
        return 0 if all(x["passed"] for x in result["laws"].values()) else 2
    except (RuntimeError, OSError, ValueError) as exc:
        print(f"LAW RUNNER ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
