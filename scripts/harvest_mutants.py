#!/usr/bin/env python3
"""Observe exact registered mutant inputs in disposable checkouts (Milestone B).

No live-mutant Phoenix process, inferred mutant outputs, simulated counterexamples
or formal proof claims. Before `--execute` every observation is UNEXECUTED.
After execution the original app separately probes harvested outputs against
its own source-law generation (apps/review_web/scripts/assess_mutant_harvest.exs).
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

from run_mutants import ROOT, LEDGER, SPEC, MUTANTS, digest, patch_correctly_applies, scratch_project, cmd, evidence_of_assertion_failure

INPUTS = ROOT / "scripts/mutant_inputs.json"
MARKER = "MUTANT_OBSERVATION_JSON:"


def source_inputs() -> dict:
    inputs = json.loads(INPUTS.read_text())
    assert set(inputs) == {m[0] for m in MUTANTS}
    for mutant, dirname, _ in MUTANTS:
        item = inputs[mutant]
        path = ROOT / item["counterexample_path"]
        if path.resolve() != (ROOT / "mutants" / dirname / "counterexample_test.exs").resolve():
            raise ValueError(f"{mutant}: unregistered counterexample path")
        if digest(path) != item["counterexample_sha256"]:
            raise ValueError(f"{mutant}: registered input provenance stale")
        if set(item) != {"before", "event", "counterexample_path", "counterexample_sha256"}:
            raise ValueError(f"{mutant}: unexpected input keys")
    return inputs


def run_observation(project: Path, mutant: str, label: str, timeout: int) -> dict:
    script = project / "scripts/local_run.py"
    args = [sys.executable, str(script), "mix", "run", "scripts/mutant_observe.exs", "--", mutant]
    target = ROOT / "tmp/verification/mutant-harvest-logs" / f"{mutant}-{label}.log"
    build = cmd([sys.executable, str(script), "mix", "compile", "--force", "--warnings-as-errors"],
                cwd=project, timeout=timeout,
                log=target.with_name(f"{mutant}-{label}-build.log"))
    if build["exit"] != 0 or build["timeout"]:
        return {"status": "unexecuted", "build": build,
                "error": "Scratch compilation failed; reducer was not observed"}
    info = cmd(args, cwd=project, timeout=timeout, log=target)
    info["build"] = build
    output = target.read_text()
    matches = [line[len(MARKER):] for line in output.splitlines() if line.startswith(MARKER)]
    if info["exit"] == 0 and not info["timeout"] and len(matches) == 1:
        try:
            value = json.loads(matches[0])
            if value["input_id"] == mutant and set(value) == {
                    "input_id", "before", "event", "output", "oracle",
                    "input_matches_original_spec", "counterexample_sha256", "ledger_source_sha256", "ledger_beam_md5"} and value["ledger_source_sha256"] == digest(project / LEDGER) and re.fullmatch(r"[0-9a-f]{32}", value["ledger_beam_md5"]):
                info["compiled_identity"] = {k: value[k] for k in ("ledger_source_sha256", "ledger_beam_md5")}
                info["observation"] = value
                info["status"] = "executed"
                return info
        except (ValueError, KeyError, TypeError):
            pass
    info["status"] = "unexecuted"
    info["error"] = "No valid complete reducer observation; see log (compile/timeout/tool failure is not an ordinary counterexample)"
    return info


def harvest_one(spec: tuple, inputs: dict, timeout: int) -> dict:
    mutant, dirname, target_law = spec
    original = (ROOT / LEDGER).read_bytes()
    original_sha = hashlib.sha256(original).hexdigest()
    spec_sha = digest(ROOT / SPEC)
    patch = ROOT / "mutants" / dirname / "mutant.patch"
    record = {
        "mutant_id": mutant, "target_law": target_law,
        "counterexample_path": inputs[mutant]["counterexample_path"],
        "counterexample_sha256": inputs[mutant]["counterexample_sha256"],
        "patch_path": str(patch.relative_to(ROOT)), "patch_sha256": digest(patch),
        "original_ledger_sha256": original_sha, "original_spec_sha256": spec_sha,
        "provenance": "unexecuted", "input": inputs[mutant], "output": None,
        "original_output": None, "tool_outcome": None, "ordinary_test": "NOT RUN",
        "formal": "NOT RUN"
    }
    with tempfile.TemporaryDirectory(prefix=f"harvest-{mutant}-", dir=ROOT / "tmp") as name:
        copy = scratch_project(Path(name))
        if digest(copy / SPEC) != spec_sha or digest(copy / LEDGER) != original_sha:
            raise RuntimeError(f"{mutant}: scratch differs from original source")
        before = run_observation(copy, mutant, "baseline", timeout)
        record["tool_outcome"] = {"baseline": {k: v for k, v in before.items() if k != "observation"}}
        if before["status"] != "executed" or not before["observation"]["input_matches_original_spec"]:
            record["error"] = "Baseline observation or independent Spec comparison failed"
            return record
        record["original_output"] = before["observation"]["output"]
        mutant_sha = patch_correctly_applies(copy, mutant, dirname, original)
        record["mutant_ledger_sha256"] = mutant_sha
        if digest(copy / SPEC) != spec_sha or (ROOT / LEDGER).read_bytes() != original:
            raise RuntimeError(f"{mutant}: normative/live checkout changed")
        after = run_observation(copy, mutant, "patched", timeout)
        record["tool_outcome"]["patched"] = {k: v for k, v in after.items() if k != "observation"}
        if after["status"] != "executed":
            record["error"] = "Patched reducer observation unavailable; no mutant_observed label"
            return record
        observed = after["observation"]
        if observed["before"] != inputs[mutant]["before"] or observed["event"] != inputs[mutant]["event"] or observed["counterexample_sha256"] != record["counterexample_sha256"]:
            raise RuntimeError(f"{mutant}: exact input identity mismatch")
        record["output"] = observed["output"]
        record["provenance"] = "mutant_observed"
        # Independently run the concrete original test under the patched reducer;
        # a compilation failure is never reported as a concrete counterexample.
        test_file = copy / "test/mutations/active_mutant_test.exs"
        test_file.parent.mkdir(parents=True, exist_ok=True)
        test_file.write_bytes((ROOT / inputs[mutant]["counterexample_path"]).read_bytes())
        test_result = cmd([sys.executable, str(copy / "scripts/local_run.py"),
                           "mix", "test", "test/mutations/active_mutant_test.exs",
                           "--exclude", "laws", "--seed", "12345"], cwd=copy,
                          timeout=timeout, log=ROOT / "tmp/verification/mutant-harvest-logs" / f"{mutant}-test.log")
        text = (ROOT / test_result["log"]).read_text()
        concrete_failure = test_result["exit"] == 2 and not test_result["timeout"] and evidence_of_assertion_failure(text, mutant)
        record["ordinary_test"] = dict(test_result,
            classification=("concrete_assertion_failure" if concrete_failure else
                            "passed" if test_result["exit"] == 0 else
                            "unavailable_compile_or_tool_or_nonassertion_failure"))
        if digest(copy / SPEC) != spec_sha or (ROOT / LEDGER).read_bytes() != original:
            raise RuntimeError(f"{mutant}: isolation failure after test")
    return record


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--execute", action="store_true", help="observe all isolated reducer patches")
    p.add_argument("--timeout", type=int, default=240)
    p.add_argument("--report", type=Path, default=Path("tmp/verification/mutant-harvest.json"))
    args = p.parse_args()
    report = (ROOT / args.report).resolve()
    if not report.is_relative_to(ROOT / "tmp"):
        p.error("report must be under checkout tmp/")
    (ROOT / "tmp").mkdir(exist_ok=True)
    report.parent.mkdir(parents=True, exist_ok=True)
    try:
        inputs = source_inputs()
        result = {"mode": "EXECUTED" if args.execute else "STATIC_ONLY",
                  "generated_at_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
                  "original_ledger_sha256": digest(ROOT / LEDGER),
                  "original_spec_sha256": digest(ROOT / SPEC), "inputs_sha256": digest(INPUTS),
                  "mutants": {}, "catcher_mapping": "NOT RUN"}
        for spec in MUTANTS:
            mutant, dirname, law = spec
            if args.execute:
                result["mutants"][mutant] = harvest_one(spec, inputs, args.timeout)
            else:
                patch = ROOT / "mutants" / dirname / "mutant.patch"
                result["mutants"][mutant] = {"mutant_id": mutant, "target_law": law,
                    "provenance": "unexecuted", "input": inputs[mutant], "output": None,
                    "patch_path": str(patch.relative_to(ROOT)), "patch_sha256": digest(patch),
                    "ordinary_test": "NOT RUN", "formal": "NOT RUN"}
        if digest(ROOT / LEDGER) != result["original_ledger_sha256"] or digest(ROOT / SPEC) != result["original_spec_sha256"]:
            raise RuntimeError("Original sources changed during harvest")
        report.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
        observed = sum(v["provenance"] == "mutant_observed" for v in result["mutants"].values())
        print(f"Harvested {observed}/10 isolated outputs; original-source catcher mapping is a separate Phoenix command")
        assertions = all(isinstance(v["ordinary_test"], dict) and
                         v["ordinary_test"]["classification"] == "concrete_assertion_failure"
                         for v in result["mutants"].values())
        return 0 if not args.execute or (observed == 10 and assertions) else 2
    except (OSError, ValueError, RuntimeError, AssertionError, subprocess.SubprocessError) as error:
        report.write_text(json.dumps({"mode": "INCOMPLETE", "error": str(error),
                                      "mutants": {}, "catcher_mapping": "NOT RUN"}, indent=2) + "\n")
        print(f"HARVEST FAILED: {error}", file=sys.stderr)
        return 1

if __name__ == "__main__":
    raise SystemExit(main())
