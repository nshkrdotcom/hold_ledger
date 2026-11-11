"""Source-only guards for 0300-01..05; never substitute for Lynx checks."""
from __future__ import annotations

import importlib
import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
graph = importlib.import_module("phase3_proof_graph")
freeze = importlib.import_module("phase3_preservation")
research = importlib.import_module("check_phase3_research")


class Phase3PreparationTest(unittest.TestCase):
    def test_proof_graph_covers_original_groups_modules_and_native_anchors(self):
        report = graph.analyze()
        self.assertEqual(report["counts"], {
            "dsl_groups": 35, "native_groups": 14,
            "total_groups": 49, "native_anchors": 21, "shared_lean_modules": 39,
        })
        self.assertEqual(len(report["modules"]), 39)
        self.assertEqual(report["migration"]["deletions"], [])
        self.assertEqual(json.loads(graph.FILE.read_text()), report)

    def test_graph_rejects_old_lemma_reintroduction(self):
        with tempfile.TemporaryDirectory() as directory:
            tmp = Path(directory)
            (tmp / "test/support").mkdir(parents=True)
            (tmp / "verification").mkdir()
            shutil.copytree(ROOT / "test/support/lean", tmp / "test/support/lean")
            shutil.copytree(ROOT / "test/laws", tmp / "test/laws")
            shutil.copy2(ROOT / "verification/laws.json", tmp / "verification/laws.json")
            lookup = tmp / "test/support/lean/Lookup.lean"
            lookup.write_text(lookup.read_text() + "\ntheorem «l1_find/2» : True := by trivial\n")
            with patch.object(graph, "ROOT", tmp), patch.object(
                graph, "LIB", tmp / "test/support/lean"
            ):
                with self.assertRaisesRegex(ValueError, "old consumers|Old L1"):
                    graph.analyze()

    def test_phase_2_contract_freeze_passes_and_fails_on_drift(self):
        freeze.check()
        baseline = json.loads(freeze.BASELINE.read_text())
        self.assertEqual(len(baseline["dsl_contracts"]), 35)
        changed = freeze.current()
        changed["dsl_contracts"]["test/laws/l1_find_test.exs"] = "changed"
        with patch.object(freeze, "current", return_value=changed):
            with self.assertRaisesRegex(ValueError, "dsl_contracts changed"):
                freeze.check()

    def test_research_runner_fails_closed_and_does_not_fake_acceptance(self):
        with patch.object(research.subprocess, "run", side_effect=FileNotFoundError("lake")):
            self.assertEqual(research.main(), 1)
        with patch.object(research.subprocess, "run", return_value=subprocess.CompletedProcess(
            ["lake"], 2, "", "compilation failed"
        )):
            self.assertEqual(research.main(), 1)


if __name__ == "__main__":
    unittest.main()
