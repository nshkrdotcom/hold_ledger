#!/usr/bin/env python3
"""Isolated mutation examples with ordinary assertions and targeted Lynx checks.

Never changes the active ledger, Spec, or any formal law. Native mode first
checks each witness against the correct reducer, then patches a disposable
copy. Formal mutant claims require that the *original* targeted law already
passed the uncached Lynx run AND every independent export checker.
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
import re
import shutil
import subprocess
import signal
import sys
import tempfile
import time
from pathlib import Path

from run_laws import inspect_manifest

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
)
OMIT = (".git", ".local", ".venv", "_build", "deps", "tmp", "__pycache__",
        ".pytest_cache", "doc", "hold_ledger-*.tar")


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def cmd(argv: list[str], cwd: Path, *, timeout: int, log: Path) -> dict:
    log.parent.mkdir(parents=True, exist_ok=True)
    started = time.monotonic()
    process = subprocess.Popen(argv, cwd=cwd, text=True,
                               stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                               start_new_session=True)
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
    log.write_text(output, encoding="utf8")
    return {"command": argv, "exit": code, "timeout": timed_out,
            "wall_seconds": round(time.monotonic() - started, 3),
            "log": str(log.relative_to(ROOT))}


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
    project = destination / "hold_ledger"
    shutil.copytree(ROOT, project, ignore=shutil.ignore_patterns(*OMIT))
    for name in ("deps", ".local"):
        # The Elixir and Lean binaries/dependencies remain at their known pinned
        # native checkout; builds, generated files and export output stay in
        # this disposable copy. Do not write into source dependencies.
        original = ROOT / name
        if original.is_dir():
            (project / name).symlink_to(original, target_is_directory=True)
    return project


def evidence_of_assertion_failure(output: str, mutant_id: str) -> bool:
    if f"{mutant_id}:" not in output:
        return False
    if "1 failure" not in output and "Failed: 1 test" not in output:
        return False
    if "** (CompileError)" in output or "** (SyntaxError)" in output or "Compilation error" in output:
        return False
    return any(word in output for word in ("Assertion with", "AssertionError", "left:", "match (==)"))


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
    p.add_argument("--execute", action="store_true", help="run full native isolated mutations")
    p.add_argument("--timeout", type=int, default=1800, help="native per-check seconds")
    p.add_argument("--suite-timeout", type=int, default=2400)
    p.add_argument("--report", type=Path, help="persist results JSON inside checkout")
    args = p.parse_args()
    try:
        inspect_manifest()
        original = (ROOT / LEDGER).read_bytes()
        spec_hash = digest(ROOT / SPEC)
        report = {"mode": "EXECUTED" if args.execute else "STATIC_ONLY",
                  "date_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
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
            baselines = baseline_laws(MUTANTS, args.timeout)
            report["formal_baselines"] = baselines
            all_detected = True
            for entry in MUTANTS:
                result = one_mutant(entry, original, spec_hash, baselines,
                                    args.timeout, args.suite_timeout)
                report["mutants"][entry[0]] = result
                all_detected &= result["mutant_concrete"]["assertion_counterexample"]
                print(f"{entry[0]} concrete={'DETECTED' if result['mutant_concrete']['assertion_counterexample'] else 'NOT DETECTED'}; "
                      f"formal={result['formal_attribution']}", flush=True)
            report["all_six_concrete_detected"] = bool(all_detected)
        if (ROOT / LEDGER).read_bytes() != original or digest(ROOT / SPEC) != spec_hash:
            raise RuntimeError("Live normative/reducer sources changed; isolation failure")
        if args.report:
            dest = args.report.resolve()
            if not dest.is_relative_to(ROOT):
                raise RuntimeError("Report must remain inside source checkout")
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
        print(f"Six isolated patch anchors verified; run mode={report['mode']}" )
        if not args.execute:
            print("Ordinary execution / formal checker NOT RUN; no mutation claims")
        return 0 if not args.execute or report.get("all_six_concrete_detected") else 2
    except (RuntimeError, OSError, ValueError, subprocess.SubprocessError) as error:
        print(f"MUTATION RUNNER ERROR: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
