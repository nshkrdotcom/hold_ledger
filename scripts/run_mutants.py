#!/usr/bin/env python3
"""Isolated mutation examples with ordinary assertions and targeted Lynx checks.

Never changes the active ledger, Spec, or any formal law. Native mode first
checks each witness against the correct reducer, then patches a disposable
copy. Formal mutant claims require that the *original* targeted law already
passed the uncached Lynx run AND every independent export checker.
"""
from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import datetime as dt
import os
import hashlib
import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from check_runtime import cancellation_scope, copy_project, resources, worker_environment, worker_count, MUTANT_MEMORY_BYTES
from run_laws import (CHECKERS, REQUIRED_AXIOMS, acceptance_sources, changed_sources,
                      inspect_manifest, run as run_command)
from obligations import required_inventory

ROOT = Path(__file__).resolve().parents[1]
LEDGER = Path("lib/hold_ledger/ledger.ex")
SPEC = Path("lib/hold_ledger/spec.ex")
MUTANTS = (
    ("M1", "01_terminal_replay", "po_a4_duplicate"),
    ("M2", "02_timeout_release", "po_b1_timeout"),
    ("M3", "03_retry_identity", "po_b3"),
    ("M4", "04_exact_fit", "po_a2"),
    ("M5", "05_always_reject", "po_a2"),
    ("M6", "06_ack_result", "po_b4"),
    ("M7", "07_void_effect", "po_b3"),
    ("M8", "08_decline_accounting", "po_b1_processor_result"),
    ("M9", "09_restart_unknown", "po_b7"),
    ("M10", "10_premature_void_release", "po_exposure_retain"),
)



def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def cmd(argv: list[str], cwd: Path, *, timeout: int, log: Path) -> dict:
    result = run_command(argv, cwd=cwd, env=worker_environment(int(os.environ.get("HOLD_LEDGER_JOBS", "1")), cwd), log=log, timeout=timeout)
    # Preserve the mutation runner's existing report schema.
    result.pop("cwd")
    return result


def patch_correctly_applies(project: Path, mutant: str, relative_dir: str,
                            original: bytes) -> str:
    patch = ROOT / "mutants" / relative_dir / "mutant.patch"
    if patch.read_text().count("--- a/lib/hold_ledger/ledger.ex") != 1 or \
       patch.read_text().count("+++ b/lib/hold_ledger/ledger.ex") != 1 or \
       len(re.findall(r"(?m)^\+\+\+ ", patch.read_text())) != 1:
        raise RuntimeError(f"{mutant}: patch must target only ledger.ex")
    target = project / LEDGER
    if target.read_bytes() != original:
        raise RuntimeError(f"{mutant}: unexpected input source hash")
    for option in (("apply", "--check"), ("apply",)):
        run = subprocess.run(["git", *option, str(patch)], cwd=project, capture_output=True,
                             text=True, check=False)
        if run.returncode:
            raise RuntimeError(f"{mutant}: git {' '.join(option)} failed: {run.stderr}")
    mutated = target.read_bytes()
    if mutated == original:
        raise RuntimeError(f"{mutant}: patch did not change the ledger")
    return hashlib.sha256(mutated).hexdigest()


def scratch_project(destination: Path) -> Path:
    return copy_project(ROOT, destination / "hold_ledger")


def evidence_of_assertion_failure(output: str, mutant_id: str) -> bool:
    if f"{mutant_id}:" not in output:
        return False
    if "1 failure" not in output and "Failed: 1 test" not in output:
        return False
    if "** (CompileError)" in output or "** (SyntaxError)" in output or "Compilation error" in output:
        return False
    return any(word in output for word in (
        "Assertion with", "AssertionError", "left:", "match (==)",
        "Expected truthy", "Expected false or nil"))


def run_mix(project: Path, path: str | None, *, logsuffix: str, mutant: str, timeout: int) -> dict:
    args = [sys.executable, str(project / "scripts/local_run.py"), "mix", "test"]
    if path:
        args.append(path)
    args += ["--exclude", "laws", "--seed", "12345"]
    result = cmd(args, cwd=project, timeout=timeout,
                 log=ROOT / "tmp/verification/mutant-logs" / f"{mutant}-{logsuffix}.log")
    return result


def formal_run(project: Path, law_slug: str, *, label: str, timeout: int) -> tuple[dict, dict | None]:
    report = project / "tmp/verification/mutant-formal.json"
    args = [sys.executable, str(project / "scripts/run_laws.py"), "--slug", law_slug,
            "--timeout", str(timeout), "--checker-timeout", str(timeout),
            "--report", "tmp/verification/mutant-formal.json"]
    executed = cmd(args, cwd=project, timeout=2 * timeout + 60,
                   log=ROOT / "tmp/verification/mutant-logs" / f"{label}-lynx.log")
    payload = json.loads(report.read_text()) if report.is_file() else None
    law = payload["laws"].get(law_slug) if payload else None
    if law and project != ROOT:
        # The isolated project is deleted on return. Retain the actual Lean
        # diagnostics, rather than only the outer runner's one-line verdict.
        source_log = project / law["log"]
        if source_log.is_file():
            retained = ROOT / "tmp/verification/mutant-logs" / f"{label}-proof-detail.log"
            retained.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source_log, retained)
            law["log"] = str(retained.relative_to(ROOT))
            law["log_sha256"] = digest(retained)
    return executed, law


def accepted_baseline(path: Path, mutants: list[tuple]) -> dict:
    """Reuse a complete fresh acceptance artifact, never an unverified success label."""
    path = path.resolve()
    report = json.loads(path.read_text(encoding="utf8"))
    manifest = report.get("source_sha256", {})
    expected = {str(source.relative_to(ROOT)) for source in acceptance_sources()}
    obligations = required_inventory(ROOT / "verification/obligations.json")
    required = {item["slug"] for item in obligations}
    records = report.get("laws", {})
    coverage = report.get("obligation_coverage", {})
    if (report.get("mode") != "EXECUTED" or report.get("stage") != "full"
            or report.get("cache") != "LYNX_CACHE=0" or report.get("batch") is not True
            or report.get("complete") is not True or report.get("correct_export") is not True
            or report.get("release_complete") is not True or report.get("checker_claim") is not True
            or report.get("accepted_proof_claim") is not True
            or report.get("source_changes_during_run") != []
            or not isinstance(manifest, dict) or set(manifest) != expected
            or changed_sources(manifest, acceptance_sources())
            or not isinstance(records, dict) or set(records) != required
            or any(item.get("passed") is not True or item.get("native_passed") is not True
                   for item in records.values())
            or coverage.get("complete") is not True or coverage.get("missing") != []
            or set(coverage.get("accepted", [])) != required
            or set(coverage.get("required", [])) != required):
        raise RuntimeError("Formal baseline must accept the complete unchanged source")
    exports = report.get("exports", [])
    if not isinstance(exports, list) or len(exports) != 1:
        raise RuntimeError("Formal baseline must have exactly one checked suite export")
    for export in exports:
        if export.get("path") != "tmp/verification/exports/full-suite/suite.ndjson":
            raise RuntimeError("Formal baseline export is not the full-suite artifact")
        artifact = (ROOT / export["path"]).resolve()
        if (not artifact.is_relative_to(ROOT / "tmp") or not artifact.is_file()
                or export.get("passed") is not True or export.get("allowed_axioms") is not True
                or not export.get("axiom_list")
                or set(export.get("axiom_list", [])) - REQUIRED_AXIOMS
                or set(export.get("checker_acceptance", {})) != set(CHECKERS)
                or not all(value is True for value in export["checker_acceptance"].values())
                or artifact.stat().st_size != export.get("export_bytes")
                or digest(artifact) != export.get("export_sha256")):
            raise RuntimeError("Formal baseline export identity/checkers do not match")
    slugs = list(dict.fromkeys(item[2] for item in mutants))
    if any(report.get("laws", {}).get(slug, {}).get("passed") is not True for slug in slugs):
        raise RuntimeError("Formal baseline omits a targeted mutation law")
    return {"reused_report": str(path), "report_sha256": digest(path),
            "source_sha256": manifest,
            "laws": {slug: {"passed": True} for slug in slugs}}


def baseline_laws(mutants: list[tuple], timeout: int) -> dict:
    slugs = list(dict.fromkeys(x[2] for x in mutants))
    args = [sys.executable, str(ROOT / "scripts/run_laws.py")]
    for slug in slugs:
        args += ["--slug", slug]
    args += ["--timeout", str(timeout), "--checker-timeout", str(timeout),
             "--report", "tmp/verification/mutant-formal-baseline.json"]
    report = ROOT / "tmp/verification/mutant-formal-baseline.json"
    # Never consume a stale successful report from a previous source revision.
    report.unlink(missing_ok=True)
    executed = cmd(args, cwd=ROOT, timeout=(2 * timeout + 60) * len(slugs),
                   log=ROOT / "tmp/verification/mutant-logs" / "baseline-lynx.log")
    checked = json.loads(report.read_text())["laws"] if report.is_file() else {}
    return {"execution": executed, "laws": {s: {"passed": checked.get(s, {}).get("passed", False),
                                              "exit": checked.get(s, {}).get("exit")}
                                          for s in slugs}}


def one_mutant(spec: tuple, original: bytes, spec_digest: str,
               baseline: dict, timeout: int, full_suite_timeout: int) -> dict:
    mutant, relative_dir, law_slug = spec
    with tempfile.TemporaryDirectory(prefix=f"mutant-{mutant}-", dir=ROOT / "tmp") as dirname:
        project = scratch_project(Path(dirname))
        if digest(project / SPEC) != spec_digest:
            raise RuntimeError(f"{mutant}: independent Spec changed during copy")
        witness_source = ROOT / "mutants" / relative_dir / "counterexample_test.exs"
        test_file = project / "test/mutations/active_mutant_test.exs"
        test_file.parent.mkdir(parents=True, exist_ok=True)
        test_file.write_bytes(witness_source.read_bytes())
        protected_law = project / f"test/laws/{law_slug}_test.exs"
        protected_sha = digest(protected_law)
        before = run_mix(project, "test/mutations/active_mutant_test.exs",
                         logsuffix="witness-baseline", mutant=mutant, timeout=timeout)
        if before["exit"] != 0:
            raise RuntimeError(f"{mutant}: unmutated concrete witness did not pass; see {before['log']}")
        changed_sha = patch_correctly_applies(project, mutant, relative_dir, original)
        if digest(project / SPEC) != spec_digest:
            raise RuntimeError(f"{mutant}: mutation touched the normative Spec")
        after = run_mix(project, "test/mutations/active_mutant_test.exs",
                        logsuffix="witness-mutant", mutant=mutant, timeout=timeout)
        output = (ROOT / after["log"]).read_text()
        contradicted = after["exit"] == 2 and evidence_of_assertion_failure(output, mutant)
        if not contradicted:
            raise RuntimeError(f"{mutant}: missing real assertion failure (not mere compile failure): {after['log']}")
        normal = run_mix(project, None, logsuffix="ordinary-suite", mutant=mutant,
                         timeout=full_suite_timeout)
        normal_text = (ROOT / normal["log"]).read_text()
        normal["detected"] = (
            normal["exit"] == 2 and
            (" failure" in normal_text or "Failed: " in normal_text) and
            "** (CompileError)" not in normal_text
        )
        if not normal["detected"]:
            raise RuntimeError(f"{mutant}: ordinary full-suite failure not confirmed: {normal['log']}")
        formal, formal_result = formal_run(project, law_slug, label=mutant, timeout=timeout)
        baseline_ok = baseline["laws"].get(law_slug, {}).get("passed", False)
        formal_text = (ROOT / formal["log"]).read_text()
        if formal_result and (ROOT / formal_result["log"]).is_file():
            formal_text += "\n" + (ROOT / formal_result["log"]).read_text()
        if not baseline_ok:
            attribution = "UNAVAILABLE_BASELINE_LAW_NOT_INDEPENDENTLY_VERIFIED"
        elif formal_result and formal_result.get("passed"):
            attribution = "MUTANT_FORMAL_ESCAPED"
        elif ("proof for law" in formal_text or "Failed to check" in formal_text) and \
             "Checked Elixir.HoldLedger" in formal_text:
            attribution = "FORMAL_PROOF_REJECTED_NOT_A_CONCRETE_COUNTEREXAMPLE"
        else:
            attribution = "UNAVAILABLE_ELABORATION_TRANSLATION_TIMEOUT_OR_TOOL_ERROR"
        if (project / SPEC).read_bytes() != (ROOT / SPEC).read_bytes():
            raise RuntimeError(f"{mutant}: Spec changed during isolated formal execution")
        if digest(protected_law) != protected_sha or protected_law.read_bytes() != \
           (ROOT / f"test/laws/{law_slug}_test.exs").read_bytes():
            raise RuntimeError(f"{mutant}: original law changed in mutant source copy")
        if (ROOT / LEDGER).read_bytes() != original:
            raise RuntimeError(f"{mutant}: live ledger changed during mutation")
        return {"patch": f"mutants/{relative_dir}/mutant.patch", "patch_sha256":
                digest(ROOT / "mutants" / relative_dir / "mutant.patch"),
                "mutant_sha256": changed_sha, "id": mutant, "law_slug": law_slug,
                "baseline_concrete": before, "mutant_concrete":
                    dict(after, assertion_counterexample=contradicted),
                "mutant_ordinary_suite": normal, "formal_baseline_passed": baseline_ok,
                "mutant_law_run": formal, "mutant_law_evidence": formal_result,
                "formal_attribution": attribution}


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--jobs", type=int, help="worker ceiling (default: all usable CPUs, bounded by memory and mutant count)")
    p.add_argument("--baseline-report", type=Path, help="reuse matching complete cold checker acceptance")
    p.add_argument("--execute", action="store_true", help="run full native isolated mutations")
    p.add_argument("--timeout", type=int, default=1800, help="native per-check seconds")
    p.add_argument("--suite-timeout", type=int, default=2400)
    p.add_argument("--report", type=Path, help="persist results JSON inside checkout")
    args = p.parse_args()
    dest = None
    try:
        if args.jobs is not None and args.jobs < 1:
            raise RuntimeError("--jobs must be positive")
        capacity = resources()
        args.jobs = worker_count(capacity, len(MUTANTS), MUTANT_MEMORY_BYTES, args.jobs)
        os.environ["HOLD_LEDGER_JOBS"] = str(args.jobs)
        if args.report:
            candidate = args.report.resolve()
            if not candidate.is_relative_to(ROOT / "tmp"):
                raise RuntimeError("Report must remain inside checkout tmp directory")
            candidate.parent.mkdir(parents=True, exist_ok=True)
            candidate.unlink(missing_ok=True)
            dest = candidate
        inspect_manifest()
        original = (ROOT / LEDGER).read_bytes()
        spec_hash = digest(ROOT / SPEC)
        report = {"mode": "EXECUTED" if args.execute else "STATIC_ONLY",
                  "date_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
                  "jobs": args.jobs, "resources": capacity,
                  "ledger_sha256": hashlib.sha256(original).hexdigest(),
                  "spec_sha256": spec_hash, "mutants": {}}
        (ROOT / "tmp").mkdir(exist_ok=True)
        for mutant, dirname, law_slug in MUTANTS:
            with tempfile.TemporaryDirectory(prefix="mutant-patch-static-", dir=ROOT / "tmp") as folder:
                project = Path(folder)
                target = project / LEDGER
                target.parent.mkdir(parents=True)
                target.write_bytes(original)
                mutant_sha = patch_correctly_applies(project, mutant, dirname, original)
            report["mutants"][mutant] = {"patch": f"mutants/{dirname}/mutant.patch",
                                          "law_slug": law_slug, "patch_sha256":
                                          digest(ROOT / "mutants" / dirname / "mutant.patch"),
                                          "mutant_sha256": mutant_sha,
                                          "ordinary": "NOT RUN", "formal": "NOT RUN"}
        if args.execute:
            if args.timeout <= 0 or args.suite_timeout <= 0:
                raise RuntimeError("Positive timeouts required")
            baselines = (accepted_baseline(args.baseline_report, MUTANTS) if args.baseline_report
                         else baseline_laws(MUTANTS, args.timeout))
            report["formal_baselines"] = baselines
            print(f"Running {len(MUTANTS)} isolated mutants with {args.jobs} workers", flush=True)
            all_detected = True
            with cancellation_scope(), ThreadPoolExecutor(max_workers=args.jobs) as pool:
                futures = {pool.submit(one_mutant, entry, original, spec_hash, baselines,
                                       args.timeout, args.suite_timeout): entry for entry in MUTANTS}
                for future in as_completed(futures):
                    entry = futures[future]
                    try:
                        result = future.result()
                    except (RuntimeError, OSError, ValueError, subprocess.SubprocessError) as error:
                        result = {"id": entry[0], "state": "INCOMPLETE", "error": str(error)}
                        all_detected = False
                    report["mutants"][entry[0]] = result
                    detected = result.get("mutant_concrete", {}).get("assertion_counterexample", False)
                    all_detected &= detected
                    print(f"{entry[0]} concrete={'DETECTED' if detected else 'INCOMPLETE'}; "
                          f"formal={result.get('formal_attribution', 'UNAVAILABLE')}", flush=True)
                    if dest:
                        dest.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
            report["all_concrete_detected"] = bool(all_detected)
        if (ROOT / LEDGER).read_bytes() != original or digest(ROOT / SPEC) != spec_hash:
            raise RuntimeError("Live normative/reducer sources changed; isolation failure")
        if dest:
            dest.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
        print(f"{len(MUTANTS)} isolated patch anchors verified; run mode={report['mode']}" )
        if not args.execute:
            print("Ordinary execution / formal checker NOT RUN; no mutation claims")
        return 0 if not args.execute or report.get("all_concrete_detected") else 2
    except KeyboardInterrupt:
        if dest:
            dest.write_text(json.dumps({"mode": "INCOMPLETE", "all_concrete_detected": False,
                                        "error": "Cancelled"}) + "\n")
        return 130
    except (RuntimeError, OSError, ValueError, subprocess.SubprocessError) as error:
        if dest:
            dest.write_text(json.dumps({"mode": "INCOMPLETE", "all_concrete_detected": False,
                                        "error": str(error)}) + "\n")
        print(f"MUTATION RUNNER ERROR: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    with cancellation_scope():
        raise SystemExit(main())
