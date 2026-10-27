#!/usr/bin/env python3
"""Controlled unit tests for the hidden offline grader; no model was queried."""
from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from score_discovery import RUBRIC, entries, preview, summarize


class HiddenScoringTests(unittest.TestCase):
    def setUp(self) -> None:
        self.rubric = json.loads(RUBRIC.read_text())

    def test_six_private_source_grounded_items(self) -> None:
        self.assertEqual([item["id"] for item in self.rubric["items"]],
                         [f"R{x}" for x in range(1, 7)])
        self.assertTrue(all(item["source_paths"] and item["signals"]
                            for item in self.rubric["items"]))

    def test_preview_needs_text_and_grounded_model_source_link(self) -> None:
        item = self.rubric["items"][3]
        case = {
            "case": "controlled_only", "source_registry": [
                {"id": "known", "path": "test/laws/po_a2_test.exs"}
            ],
            "discovery": {"output": {"deck": {"card_suggestions": [{
                "question": "For exact-fit eligible capacity, does po_a2 demand positive admitted result rather than validity?",
                "selection_reason": "Could distinguish admission from state validity",
                "source_ids": ["known"],
            }]}}},
        }
        found = preview(item, [case])
        self.assertTrue(found["source_link_matched"])
        self.assertEqual(found["provisional"], "discovered with correct source link")
        case["discovery"]["output"]["deck"]["card_suggestions"][0]["source_ids"] = ["fictional"]
        self.assertEqual(preview(item, [case])["provisional"], "partially discovered")

    def test_nonlive_controlled_fixture_report_is_refused(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "controlled.json"
            path.write_text(json.dumps({"evidence_kind": "controlled_fixture_not_observed",
                                        "cases": []}))
            with self.assertRaisesRegex(ValueError, "actual configured-model"):
                summarize(path, None)

    def test_all_model_discovery_fields_are_scored(self) -> None:
        synthetic = {"discovery": {"output": {"deck": {
            "intent_hypotheses": [{"statement": "A", "source_ids": ["a"]}],
            "readings": [{"summary": "B", "source_ids": ["b"]}],
            "card_suggestions": [{"question": "C", "source_ids": ["c"]}],
            "uncertainties": [{"question": "D", "source_ids": ["d"]}],
        }}}}
        self.assertEqual(len(entries(synthetic)), 4)


if __name__ == "__main__":
    unittest.main()
