#!/usr/bin/env python3
"""Private, offline evaluator of the configured model's *recorded* proposals.

No calls to Inference. This file and the hidden rubric are NOT read by the
model packet builder. The string checks identify review candidates only;
semantic adjudication and source-citation verification are explicitly human.
"""
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

RUBRIC = Path(__file__).resolve().parents[1] / "priv/benchmark/rubric.json"
LABELS = {
    "discovered with correct source link", "partially discovered", "missed", "hallucinated"
}


def entries(case: dict) -> list[tuple[str, set[str]]]:
    block = case.get("discovery", {})
    output = block.get("output", {}).get("deck", {})
    values: list[tuple[str, set[str]]] = []
    for key, fields in (
        ("intent_hypotheses", ["statement", "why_plausible", "distinguishing_question"]),
        ("readings", ["summary", "not_claimed"]),
        ("card_suggestions", ["question", "selection_reason"]),
        ("uncertainties", ["question", "missing_evidence"]),
    ):
        for item in output.get(key, []):
            values.append((" ".join(str(item.get(f, "")) for f in fields), set(item.get("source_ids", []))))
    return values


def preview(item: dict, cases: list[dict]) -> dict:
    best = (0, False, "", "")
    contradiction = False
    for case in cases:
        registry = {x["id"]: x["path"] for x in case.get("source_registry", [])}
        for phrase, ids in entries(case):
            signals = sum(bool(re.search(pattern, phrase, flags=re.I)) for pattern in item["signals"])
            sourced = any(registry.get(sid) in item["source_paths"] for sid in ids)
            contradiction = contradiction or any(
                re.search(pattern, phrase, flags=re.I) for pattern in item.get("contradiction", [])
            )
            if (signals, sourced) > best[:2]:
                best = (signals, sourced, case["case"], phrase[:400])
    score, sourced, where, text = best
    if contradiction:
        label = "hallucinated"
    elif score == len(item["signals"]) and sourced:
        label = "discovered with correct source link"
    elif score:
        label = "partially discovered"
    else:
        label = "missed"
    return {"id": item["id"], "provisional": label, "signals": score,
            "source_link_matched": sourced, "case": where, "text_excerpt": text}


def summarize(path: Path, adjudication: Path | None) -> dict:
    run = json.loads(path.read_text())
    if run.get("evidence_kind") != "configured_model_live_evaluation":
        raise ValueError("Only actual configured-model benchmark reports are accepted")
    rubric = json.loads(RUBRIC.read_text())
    cases = run["cases"]
    previews = [preview(item, cases) for item in rubric["items"]]
    candidate_overrides = {}
    if adjudication:
        labels = json.loads(adjudication.read_text())
        if set(labels) != {item["id"] for item in rubric["items"]}:
            raise ValueError("Every item needs an explicit adjudicated label")
        for key, entry in labels.items():
            if set(entry) != {"label", "rationale", "source_evidence"} or entry["label"] not in LABELS:
                raise ValueError(f"Malformed adjudication for {key}")
            if not entry["rationale"].strip() or not entry["source_evidence"].strip():
                raise ValueError(f"Missing evidence/rationale for {key}")
        candidate_overrides = labels

    corrected_errors = 0
    redundant = 0
    total_latency = 0
    validated_novel = 0
    false_status_candidates = []
    for case in cases:
        discovery = case.get("discovery", {})
        output = discovery.get("output", {})
        if discovery.get("status") == "configured_model_response_validated":
            redundant += output.get("deduplicated_count", 0)
            total_latency += output.get("provenance", {}).get("latency_ms", 0)
            for reading in output.get("reading_checks", []):
                corrected_errors += sum(p["verification"] == "prediction_conflicts"
                                        for p in reading.get("predictions", []))
            deck = output.get("deck", {})
            for text, _ids in entries(case):
                if re.search(r"(lean|formal|verified|proved).{0,60}(guarantees|certifies|proved|sign.off)", text, re.I):
                    false_status_candidates.append({"case": case["case"], "text": text[:350]})
        challenge = case.get("challenge", {})
        if challenge.get("status") == "configured_model_response_validated" and challenge.get("novel_witness"):
            validated_novel += 1
        total_latency += challenge.get("output", {}).get("provenance", {}).get("latency_ms", 0)

    chosen = [candidate_overrides.get(x["id"], {}).get("label", x["provisional"]) for x in previews]
    correct = chosen.count("discovered with correct source link")
    all_success = all(case.get("discovery", {}).get("status") == "configured_model_response_validated"
                      for case in cases)
    gate = "NOT_RUN_OR_FAILED" if not all_success else (
        "NEEDS_HUMAN_ADJUDICATION" if not candidate_overrides else (
            "CANDIDATE_BAR_MET_REQUIRES_QC" if correct >= 4 and validated_novel >= 1
            and not false_status_candidates else "QUALITY_BAR_NOT_MET"))
    return {
        "scoring_kind": "offline_hidden_rubric_assessment",
        "source_report": str(path),
        "semantic_scoring_is_human_reviewed": bool(candidate_overrides),
        "model": run.get("model"), "provider": run.get("provider"),
        "items": [{**x, **({"human_adjudication": candidate_overrides[x["id"]]}
                             if x["id"] in candidate_overrides else {})} for x in previews],
        "correct_links": correct,
        "partial": chosen.count("partially discovered"),
        "missed": chosen.count("missed"),
        "hallucinated": chosen.count("hallucinated"),
        "correctable_prediction_conflicts": corrected_errors,
        "redundant_suggestions": redundant,
        "validated_novel_challenges": validated_novel,
        "total_latency_ms": total_latency,
        "unchallenged_false_proof_status_candidates": false_status_candidates,
        "quality_assessment": gate,
        "note": "Lexical previews are not semantic proof. Inspect original model proposals, source links and contradictions; record explicit rubric adjudication and run the AI available/unavailable UI QC before Gate C."
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("report", type=Path)
    parser.add_argument("--adjudication", type=Path, help="complete human R1-R6 labels/rationale/source evidence JSON")
    parser.add_argument("--out", type=Path, help="save machine-readable scoring summary")
    args = parser.parse_args()
    result = summarize(args.report, args.adjudication)
    text = json.dumps(result, indent=2, sort_keys=True) + "\n"
    if args.out:
        args.out.write_text(text)
    print(text, end="")


if __name__ == "__main__":
    main()
