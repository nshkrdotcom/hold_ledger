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
