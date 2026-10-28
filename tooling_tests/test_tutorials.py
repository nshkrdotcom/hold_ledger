import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location(
    'tutorials', Path(__file__).resolve().parents[1] / 'scripts/check_tutorials.py')
tutorials = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(tutorials)


class TutorialChecksTest(unittest.TestCase):
    def test_missing_or_ambiguous_example_fails(self):
        for blocks in ([], ['example one', 'example two']):
            with self.assertRaises(ValueError):
                tutorials.one(blocks, 'example')

    def test_current_tutorial_inventory_is_complete(self):
        examples = tutorials.standalone_lean_examples()
        self.assertEqual(len(examples), 6)
        self.assertTrue(any('theorem reserve_within_limit' in code for code in examples))
        self.assertTrue(any('inductive ToyRun' in code for code in examples))
        tutorials.one(tutorials.blocks('guides/formal_verification_crash_course.md', 'elixir'),
                      'law(over_capacity(')
        for diagnostic in ('omega could not prove the goal', 'unsolved goals'):
            tutorials.one(tutorials.blocks('guides/formal_verification_crash_course.md', 'text'),
                          diagnostic)

    def test_removing_or_duplicating_required_example_fails(self):
        original_blocks = tutorials.blocks
        crash = 'guides/formal_verification_crash_course.md'
        examples = original_blocks(crash, 'lean')
        required = tutorials.one(examples, 'theorem reserve_within_limit')
        for replacement in ([code for code in examples if code != required],
                            examples + [required]):
            def changed_blocks(guide, language):
                return replacement if guide == crash and language == 'lean' else original_blocks(guide, language)
            with patch.object(tutorials, 'blocks', side_effect=changed_blocks):
                with self.assertRaises(ValueError):
                    tutorials.standalone_lean_examples()

    def test_new_unregistered_standalone_example_cannot_be_ignored(self):
        original_blocks = tutorials.blocks
        crash = 'guides/formal_verification_crash_course.md'

        def changed_blocks(guide, language):
            result = original_blocks(guide, language)
            if guide == crash and language == 'lean':
                return result + ['import Lean\nexample : True := by trivial\n']
            return result

        with patch.object(tutorials, 'blocks', side_effect=changed_blocks):
            with self.assertRaisesRegex(ValueError, 'Unregistered standalone Lean example'):
                tutorials.standalone_lean_examples()

    def test_arbitrary_failure_is_not_mutant_evidence(self):
        with self.assertRaises(RuntimeError):
            tutorials.require('CompileError: undefined function', 'law fits/2 expects returned false')

    def test_unexpected_success_or_failure_rejected_and_logged(self):
        with tempfile.TemporaryDirectory() as directory:
            with patch.object(tutorials, 'OUTPUT', Path(directory)):
                for actual, expected in [(0, 2), (1, 2), (2, 0)]:
                    result = subprocess.CompletedProcess([], actual, 'output', 'diagnostic')
                    with patch.object(tutorials.subprocess, 'run', return_value=result):
                        with self.assertRaises(RuntimeError):
                            tutorials.run('check', ['lean', '--stdin'], expected=expected)
                    self.assertEqual((Path(directory) / 'check.log').read_text(), 'outputdiagnostic')

    def test_timeout_cannot_pass_as_expected_failure(self):
        with patch.object(tutorials.subprocess, 'run', side_effect=subprocess.TimeoutExpired('lean', 300)):
            with self.assertRaises(subprocess.TimeoutExpired):
                tutorials.run('check', ['lean', '--stdin'], expected=2)

    def test_proof_attempt_disables_cache_and_has_timeout(self):
        with tempfile.TemporaryDirectory() as directory:
            with patch.object(tutorials, 'OUTPUT', Path(directory)):
                result = subprocess.CompletedProcess([], 0, '', '')
                with patch.object(tutorials.subprocess, 'run', return_value=result) as run:
                    tutorials.run('check', ['lean', '--stdin'], fresh=True)
                self.assertEqual(run.call_args.kwargs['env']['LYNX_CACHE'], '0')
                self.assertEqual(run.call_args.kwargs['timeout'], 300)
