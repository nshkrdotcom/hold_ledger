"""Semantic counterexamples and tool failures must stay separate."""
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from mutation_campaign import classify_ordinary
import run_mutants
from unittest import mock
import tempfile
import json


class MutationClassificationTests(unittest.TestCase):
    def test_curated_witness_recognizes_boolean_assertions_without_accepting_tool_errors(self):
        for message in ('Expected truthy, got false', 'Expected false or nil, got true'):
            output = f'M10: unconfirmed void\n{message}\nFailed: 1 test\n'
            self.assertTrue(run_mutants.evidence_of_assertion_failure(output, 'M10'))
            self.assertFalse(run_mutants.evidence_of_assertion_failure(output, 'M9'))
            self.assertFalse(run_mutants.evidence_of_assertion_failure(
                output + '** (CompileError)', 'M10'))
        self.assertFalse(run_mutants.evidence_of_assertion_failure(
            'M10: unconfirmed void\n** (RuntimeError) missing tool\nFailed: 1 test', 'M10'))

    def test_assertion_and_contract_exception_are_concrete(self):
        result = {'exit': 2, 'timeout': False}
        self.assertEqual(classify_ordinary(result, 'Assertion with == failed'), 'executable_counterexample')
        self.assertEqual(classify_ordinary(result, 'code: Ledger.init(0, 0)\n** (FunctionClauseError)'),
                         'executable_exception_counterexample')
        self.assertEqual(classify_ordinary(result, 'code: processor_result(state, 1, :declined)\n** (CaseClauseError)'),
                         'executable_exception_counterexample')

    def test_compile_timeout_and_tool_failures_are_not_semantic_kills(self):
        self.assertEqual(classify_ordinary({'exit': 1, 'timeout': False}, '** (CompileError)'),
                         'invalid_or_uncompilable')
        self.assertEqual(classify_ordinary({'exit': None, 'timeout': True}, 'AssertionError'),
                         'ordinary_timeout')
        self.assertEqual(classify_ordinary({'exit': 1, 'timeout': False}, 'missing binary'),
                         'ordinary_tool_failure')

    def test_equivalent_edit_control_does_not_become_a_kill(self):
        self.assertEqual(classify_ordinary({'exit': 0, 'timeout': False}, 'Result: 1 passed'),
                         'ordinary_survivor')
        self.assertEqual(classify_ordinary({'exit': 1, 'timeout': False}, 'Lean tactic failed'),
                         'ordinary_tool_failure')


class MutationBaselineTests(unittest.TestCase):
    def test_preflight_error_replaces_stale_mutation_report(self):
        with tempfile.TemporaryDirectory(dir=run_mutants.ROOT / 'tmp') as folder:
            report = Path(folder) / 'mutants.json'
            report.write_text(json.dumps({'all_concrete_detected': True}))
            with mock.patch.object(sys, 'argv', ['run_mutants.py', '--report', str(report)]), \
                    mock.patch.object(run_mutants, 'inspect_manifest', side_effect=RuntimeError('invalid catalog')):
                self.assertEqual(run_mutants.main(), 1)
            result = json.loads(report.read_text())
            self.assertEqual(result['mode'], 'INCOMPLETE')
            self.assertFalse(result['all_concrete_detected'])


    def test_reuse_requires_current_sources_complete_checks_and_exact_export(self):
        with tempfile.TemporaryDirectory(dir=run_mutants.ROOT / 'tmp') as folder:
            folder = Path(folder)
            source = folder / 'source.ex'
            source.write_text('synthetic source')
            export = folder / 'proof.ndjson'
            export.write_text('synthetic export')
            report = folder / 'accepted.json'
            payload = {'release_complete': True, 'checker_claim': True, 'accepted_proof_claim': True,
                       'source_changes_during_run': [],
                       'source_sha256': {str(source.relative_to(run_mutants.ROOT)): run_mutants.digest(source)},
                       'laws': {'law': {'passed': True}},
                       'exports': [{'path': str(export.relative_to(run_mutants.ROOT)), 'passed': True,
                                    'allowed_axioms': True, 'axiom_list': ['propext'],
                                    'checker_acceptance': {name: True for name in run_mutants.CHECKERS},
                                    'export_bytes': export.stat().st_size, 'export_sha256': run_mutants.digest(export)}]}
            report.write_text(json.dumps(payload))
            with mock.patch.object(run_mutants, 'acceptance_sources', return_value=[source]):
                result = run_mutants.accepted_baseline(report, [('M', 'directory', 'law')])
                self.assertTrue(result['laws']['law']['passed'])
                source.write_text('changed')
                with self.assertRaisesRegex(RuntimeError, 'unchanged source'):
                    run_mutants.accepted_baseline(report, [('M', 'directory', 'law')])
                source.write_text('synthetic source')
                export.write_text('tampered export')
                with self.assertRaisesRegex(RuntimeError, 'export identity'):
                    run_mutants.accepted_baseline(report, [('M', 'directory', 'law')])
                export.write_text('synthetic export')
                payload['release_complete'] = False
                report.write_text(json.dumps(payload))
                with self.assertRaisesRegex(RuntimeError, 'complete unchanged source'):
                    run_mutants.accepted_baseline(report, [('M', 'directory', 'law')])
