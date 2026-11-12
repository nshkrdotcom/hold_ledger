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

    def test_preflight_error_replaces_stale_success_report(self):
        import json
        with tempfile.TemporaryDirectory(dir=run_laws.ROOT / "tmp") as folder:
            report = Path(folder) / "result.json"
            report.write_text(json.dumps({"complete": True, "release_complete": True}))
            with mock.patch.object(sys, 'argv', ['run_laws.py', '--report', str(report)]), \
                    mock.patch.object(run_laws, 'inspect_manifest', side_effect=RuntimeError('broken inventory')):
                self.assertEqual(run_laws.main(), 1)
            result = json.loads(report.read_text())
            self.assertEqual(result['state'], 'INCOMPLETE')
            self.assertFalse(result['complete'])
            self.assertFalse(result['release_complete'])
            self.assertFalse(result['checker_claim'])
            self.assertEqual(result['error'], 'broken inventory')

    def test_supported_selection_requires_all_cataloged_groups(self):
        laws = run_laws.inspect_manifest()
        if any(law.get('status') == 'pending' for law in laws):
            with self.assertRaisesRegex(RuntimeError, 'INCOMPLETE'):
                run_laws.supported_laws(laws)
        else:
            self.assertEqual(len(run_laws.supported_laws(laws)), len(laws))
        for index in range(len(laws)):
            changed = [dict(law) for law in laws]
            changed[index]["status"] = "unproved"
            with self.assertRaises(RuntimeError):
                run_laws.supported_laws(changed)
        with self.assertRaises(RuntimeError):
            run_laws.supported_laws(laws[:-1])

    def test_same_id_groups_cannot_disappear_from_manifest(self):
        import json
        catalog = json.loads(run_laws.MANIFEST.read_text())
        catalog['laws'] = [law for law in catalog['laws'] if law['slug'] != 'po_a4_duplicate']
        with tempfile.TemporaryDirectory(dir=run_laws.ROOT / 'tmp') as folder:
            manifest = Path(folder) / 'laws.json'
            manifest.write_text(json.dumps(catalog))
            with mock.patch.object(run_laws, 'MANIFEST', manifest):
                with self.assertRaisesRegex(RuntimeError, 'group identities'):
                    run_laws.inspect_manifest()

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
            report["reports"].append({"module": module + ".laws", "status": "ok",
                                      "cached": False, "diagnostics": [],
                                      "theorems": [{"name": theorem}]})
        self.assertTrue(run_laws.valid_batch_report(report, laws))
        report["reports"][0]["cached"] = True
        self.assertFalse(run_laws.valid_batch_report(report, laws))
        report["reports"][0]["cached"] = False
        report["reports"][0]["status"] = "skipped"
        self.assertFalse(run_laws.valid_batch_report(report, laws))
        report["reports"][0]["status"] = "ok"
        report["reports"][0]["theorems"] = []
        self.assertFalse(run_laws.valid_batch_report(report, laws))

    def test_cold_batch_rejects_missing_cache_and_diagnostic_provenance(self):
        law = run_laws.inspect_manifest()[0]
        theorem = f"{law['law']}/{law['arity']}"
        module = 'Elixir.HoldLedger.Laws.Provenance'
        good = {'laws': {law['slug']: {'passed': True, 'module': module, 'laws': [theorem]}},
                'reports': [{'module': module + '.laws', 'status': 'ok',
                             'cached': False, 'diagnostics': [],
                             'theorems': [{'name': theorem}]}]}
        self.assertTrue(run_laws.valid_batch_report(good, [law]))
        for key, value in [('cached', None), ('cached', 'false'),
                           ('diagnostics', None), ('diagnostics', [{}]),
                           ('diagnostics', [{'severity': 'error'}]),
                           ('diagnostics', [{'severity': 'warning'}])]:
            bad = {'laws': good['laws'], 'reports': [dict(good['reports'][0], **{key: value})]}
            self.assertFalse(run_laws.valid_batch_report(bad, [law]), (key, value))
        duplicate = {'laws': good['laws'], 'reports': good['reports'] * 2}
        self.assertFalse(run_laws.valid_batch_report(duplicate, [law]))

    def test_batch_warnings_cannot_count_as_clean_acceptance(self):
        law = run_laws.inspect_manifest()[0]
        module = "Elixir.Example." + law["slug"]
        theorem = f"{law['law']}/{law['arity']}"
        report = {"laws": {law["slug"]: {"passed": True, "module": module, "laws": [theorem]}},
                  "reports": [{"module": module + ".laws", "status": "ok", "cached": False,
                               "theorems": [{"name": theorem}], "diagnostics": []}]}
        self.assertTrue(run_laws.valid_batch_report(report, [law]))
        report["reports"][0]["diagnostics"] = [{"severity": "warning", "message": "unused hypothesis"}]
        self.assertFalse(run_laws.valid_batch_report(report, [law]))

    def test_success_requires_an_actual_law_test(self):
        self.assertFalse(run_laws.valid_law_result("Result: 0 passed\n"))
        self.assertFalse(run_laws.valid_law_result("Result: 1 passed\n"))
        self.assertFalse(run_laws.valid_law_result(
            "Checked Elixir.HoldLedger.Ledger in 1ms (ok)\nResult: 1 passed\n"))
        self.assertTrue(run_laws.valid_law_result(
            "Checked Elixir.HoldLedger.Laws.Example.laws in 1ms (ok)\nResult: 1 passed\n"))

    def test_all_six_acknowledgments_and_allowed_axioms_are_required(self):
        from check_kernels_concurrent import accepted
        results = {name: {'accepted': True} for name in run_laws.CHECKERS}
        axioms = ['propext', 'Quot.sound', 'Classical.choice']
        self.assertTrue(accepted(results, axioms, run_laws.CHECKERS, run_laws.REQUIRED_AXIOMS))
        for checker in run_laws.CHECKERS:
            partial = {name: record for name, record in results.items() if name != checker}
            self.assertFalse(accepted(partial, axioms, run_laws.CHECKERS, run_laws.REQUIRED_AXIOMS))
            rejected = {name: {'accepted': name != checker} for name in run_laws.CHECKERS}
            self.assertFalse(accepted(rejected, axioms, run_laws.CHECKERS, run_laws.REQUIRED_AXIOMS))
        self.assertFalse(accepted(results, ['untrusted'], run_laws.CHECKERS, run_laws.REQUIRED_AXIOMS))
        self.assertFalse(accepted(results, [], run_laws.CHECKERS, run_laws.REQUIRED_AXIOMS))

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
        self.assertFalse(result["accepted_proof_claim"])
        self.assertFalse(result["checker_claim"])
        self.assertFalse(result["laws"][law["slug"]]["correct_export"])

    def test_native_group_requires_its_checked_module_and_exact_obligation_list(self):
        law = next(law for law in run_laws.inspect_manifest() if law.get('kind') == 'lean')
        report = {'laws': {law['slug']: {'passed': True, 'kind': 'lean',
                   'module': law['module'], 'laws': law['theorems'], 'qualified_names_checked': law['theorems']}},
                  'reports': [{'module': law['module'], 'status': 'ok', 'cached': False, 'diagnostics': []},
                              {'module': 'HoldLedgerProof.RequiredObligations', 'status': 'ok', 'cached': False, 'diagnostics': []}]}
        self.assertTrue(run_laws.valid_batch_report(report, [law]))
        report['reports'] = []
        self.assertFalse(run_laws.valid_batch_report(report, [law]))
        report['reports'] = [{'module': law['module'], 'status': 'skipped', 'cached': False, 'diagnostics': []}]
        self.assertFalse(run_laws.valid_batch_report(report, [law]))
        report['reports'] = [{'module': law['module'], 'status': 'ok', 'cached': False}]
        report['laws'][law['slug']]['laws'] = []
        self.assertFalse(run_laws.valid_batch_report(report, [law]))

    def test_native_names_require_checked_lean_anchors(self):
        law = next(item for item in run_laws.inspect_manifest() if item.get('kind') == 'lean')
        record = {'passed': True, 'kind': 'lean', 'module': law['module'],
                  'laws': law['theorems'], 'qualified_names_checked': law['theorems']}
        report = {'laws': {law['slug']: record}, 'reports': [
            {'module': law['module'], 'status': 'ok', 'cached': False, 'diagnostics': []}]}
        self.assertFalse(run_laws.valid_batch_report(report, [law]))
        report['reports'].append({'module': 'HoldLedgerProof.RequiredObligations', 'status': 'ok', 'cached': False, 'diagnostics': []})
        self.assertTrue(run_laws.valid_batch_report(report, [law]))
        record['qualified_names_checked'] = ['Wrong.namespace']
        self.assertFalse(run_laws.valid_batch_report(report, [law]))
