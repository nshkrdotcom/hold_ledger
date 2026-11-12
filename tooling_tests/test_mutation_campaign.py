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


    def test_reuse_requires_complete_laws_and_checker_results(self):
        original_root = run_mutants.ROOT
        with tempfile.TemporaryDirectory() as folder:
            folder = Path(folder)
            (folder / 'verification').mkdir()
            (folder / 'verification/obligations.json').write_bytes(
                (original_root / 'verification/obligations.json').read_bytes())
            required = {item['slug'] for item in
                        json.loads((folder / 'verification/obligations.json').read_text())['obligations']}
            export = folder / 'tmp/verification/exports/full-suite/suite.ndjson'
            export.parent.mkdir(parents=True)
            export.write_text('synthetic export')
            report = folder / 'accepted.json'
            payload = {'mode': 'EXECUTED', 'stage': 'full', 'cache': 'LYNX_CACHE=0',
                       'batch': True, 'complete': True, 'correct_export': True,
                       'release_complete': True, 'checker_claim': True, 'accepted_proof_claim': True,
                       'obligation_coverage': {'complete': True, 'missing': [],
                                               'required': sorted(required), 'accepted': sorted(required)},
                       'laws': {slug: {'passed': True, 'native_passed': True} for slug in required},
                       'exports': [{'path': str(export.relative_to(folder)), 'passed': True,
                                    'allowed_axioms': True, 'axiom_list': ['propext'],
                                    'checker_acceptance': {name: True for name in run_mutants.CHECKERS}}]}
            report.write_text(json.dumps(payload))
            selected = next(iter(required))
            with mock.patch.object(run_mutants, 'ROOT', folder):
                result = run_mutants.accepted_baseline(report, [('M', 'directory', selected)])
                self.assertTrue(result['laws'][selected]['passed'])
                payload['release_complete'] = False
                report.write_text(json.dumps(payload))
                with self.assertRaisesRegex(RuntimeError, 'complete required laws'):
                    run_mutants.accepted_baseline(report, [('M', 'directory', selected)])
                payload['release_complete'] = True
                del payload['laws'][selected]
                report.write_text(json.dumps(payload))
                with self.assertRaisesRegex(RuntimeError, 'complete required laws'):
                    run_mutants.accepted_baseline(report, [('M', 'directory', selected)])
                payload['laws'][selected] = {'passed': True, 'native_passed': True}
                payload['cache'] = 'LYNX_CACHE=warm'
                report.write_text(json.dumps(payload))
                with self.assertRaisesRegex(RuntimeError, 'complete required laws'):
                    run_mutants.accepted_baseline(report, [('M', 'directory', selected)])


class CampaignSelectionTests(unittest.TestCase):
    def test_formal_budget_uses_manifest_survivor_order(self):
        from mutation_campaign import select_formal
        records = [
            {'id': 'first', 'classification': 'executable_counterexample'},
            {'id': 'second', 'classification': 'ordinary_survivor'},
            {'id': 'third', 'classification': 'ordinary_timeout'},
            {'id': 'fourth', 'classification': 'ordinary_survivor'},
        ]
        self.assertEqual(select_formal(records, 1), ['second'])
        self.assertEqual(select_formal(records, 2), ['second', 'fourth'])
        self.assertEqual(select_formal(records, 0), [])
