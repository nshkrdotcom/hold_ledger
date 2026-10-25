"""Proof-result guards: omitted verification must never count as acceptance."""
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import run_laws


class LawRunnerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        (run_laws.ROOT / "tmp").mkdir(exist_ok=True)

    def test_supported_selection_requires_all_29_groups(self):
        laws = run_laws.inspect_manifest()
        self.assertEqual(len(run_laws.supported_laws(laws)), 29)
        for index in range(len(laws)):
            changed = [dict(law) for law in laws]
            changed[index]["status"] = "unproved"
            with self.assertRaises(RuntimeError):
                run_laws.supported_laws(changed)
        with self.assertRaises(RuntimeError):
            run_laws.supported_laws(laws[:-1])

    def test_shared_proof_sources_are_scanned_for_escapes(self):
        with tempfile.TemporaryDirectory(dir=run_laws.ROOT / "tmp") as folder:
            source = Path(folder) / "Example.lean"
            source.write_text("theorem unchecked : False := by sorry\n")
            with self.assertRaisesRegex(RuntimeError, "Forbidden proof escape"):
                run_laws.inspect_shared_sources(Path(folder))
            source.write_text("theorem checked : True := by trivial\n")
            self.assertEqual(run_laws.inspect_shared_sources(Path(folder)), [source])

    def test_batch_acceptance_requires_every_requested_theorem(self):
        laws = run_laws.inspect_manifest()[:2]
        report = {"laws": {}, "reports": []}
        self.assertFalse(run_laws.valid_batch_report(report, laws))
        for law in laws:
            module = "Elixir.Example." + law["slug"]
            theorem = f"{law['law']}/{law['arity']}"
            report["laws"][law["slug"]] = {"passed": True, "module": module, "laws": [theorem]}
            report["reports"].append({"module": module + ".laws", "status": "ok", "theorems": [{"name": theorem}]})
        self.assertTrue(run_laws.valid_batch_report(report, laws))
        report["reports"][0]["cached"] = True
        self.assertFalse(run_laws.valid_batch_report(report, laws))
        report["reports"][0]["cached"] = False
        report["reports"][0]["status"] = "skipped"
        self.assertFalse(run_laws.valid_batch_report(report, laws))
        report["reports"][0]["status"] = "ok"
        report["reports"][0]["theorems"] = []
        self.assertFalse(run_laws.valid_batch_report(report, laws))

    def test_success_requires_an_actual_law_test(self):
        self.assertFalse(run_laws.valid_law_result("Result: 0 passed\n"))
        self.assertFalse(run_laws.valid_law_result("Result: 1 passed\n"))
        self.assertFalse(run_laws.valid_law_result(
            "Checked Elixir.HoldLedger.Ledger in 1ms (ok)\nResult: 1 passed\n"))
        self.assertTrue(run_laws.valid_law_result(
            "Checked Elixir.HoldLedger.Laws.Example.laws in 1ms (ok)\nResult: 1 passed\n"))

    def test_all_six_acknowledgments_and_allowed_axioms_are_required(self):
        with tempfile.TemporaryDirectory(dir=run_laws.ROOT / "tmp") as folder:
            export = Path(folder) / "proof.ndjson"
            export.write_text("{}\n")
            complete = "\n".join(f"{name} kernel accepts the solution"
                                 for name in run_laws.CHECKERS)
            output = complete + "\nUses axioms: propext, Quot.sound, Classical.choice\n"

            def fake_run(argv, *, cwd, env, log, timeout):
                self.assertIn("--paranoid", argv)
                log.parent.mkdir(parents=True, exist_ok=True)
                log.write_text(output)
                return {"exit": 0, "timeout": False, "log": str(log.relative_to(run_laws.ROOT))}

            with mock.patch.object(run_laws, "run", fake_run):
                self.assertTrue(run_laws.exported_checker_record(export, label="unit", timeout=1)["passed"])
                for checker in run_laws.CHECKERS:
                    output = complete.replace(f"{checker} kernel accepts the solution", "")
                    output += "\nUses axioms: propext\n"
                    self.assertFalse(run_laws.exported_checker_record(export, label="unit", timeout=1)["passed"])
                output = complete + "\nUses axioms: untrusted\n"
                self.assertFalse(run_laws.exported_checker_record(export, label="unit", timeout=1)["passed"])
                output = "command exited successfully without checking anything\n"
                self.assertFalse(run_laws.exported_checker_record(export, label="unit", timeout=1)["passed"])

    def test_empty_exports_fail_even_with_a_successful_law_command(self):
        law = dict(run_laws.inspect_manifest()[0], slug="unit-empty-export")

        def fake_run(argv, *, cwd, env, log, timeout):
            self.assertEqual(env["LYNX_CACHE"], "0")
            log.parent.mkdir(parents=True, exist_ok=True)
            log.write_text("Checked Elixir.HoldLedger.Laws.Example.laws in 1ms (ok)\nResult: 1 passed\n")
            return {"exit": 0, "timeout": False, "log": str(log.relative_to(run_laws.ROOT))}

        with mock.patch.object(run_laws, "run", fake_run):
            result = run_laws.execution([law], 1, 1, stage="full")
        self.assertFalse(result["complete"])
        self.assertFalse(result["laws"][law["slug"]]["correct_export"])
