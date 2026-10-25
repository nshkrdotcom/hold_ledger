"""Actual ExUnit tag metadata enforces feature-dependent regression activation."""
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class FeatureGuardTest(unittest.TestCase):
    def guard(self, present, source):
        with tempfile.TemporaryDirectory() as folder:
            feature = Path(folder) / 'feature.ex'
            test = Path(folder) / 'regression.exs'
            if present:
                feature.write_text('feature')
            test.write_text(source)
            return subprocess.run(
                ['uv', 'run', '--locked', 'python', 'scripts/local_run.py',
                 'mix', 'run', '--no-start', 'scripts/check_feature_tests.exs',
                 str(feature), str(test), 'forged_completion'],
                cwd=ROOT, capture_output=True, text=True, check=False).returncode

    def test_feature_guard_matrix(self):
        enabled = '''defmodule FeatureFixture do
  use ExUnit.Case
  test "forged_completion" do
    assert true
  end
end
'''
        self.assertEqual(self.guard(False, ''), 0)
        self.assertEqual(self.guard(True, enabled), 0)
        self.assertNotEqual(self.guard(True, enabled.replace('  test', '  @tag skip: true\n  test')), 0)
        self.assertNotEqual(self.guard(True, enabled.replace('  test', '  @moduletag skip: true\n  test')), 0)
        self.assertNotEqual(self.guard(True, enabled.replace('  test "forged_completion" do\n    assert true\n  end', '  describe "group" do\n    @describetag skip: true\n    test "forged_completion", do: assert(true)\n  end')), 0)
        self.assertNotEqual(self.guard(True, enabled.replace('forged_completion', 'different')), 0)

    def test_current_feature_regression_is_enabled(self):
        result = subprocess.run(
            ['uv', 'run', '--locked', 'python', 'scripts/local_run.py',
             'mix', 'run', '--no-start', 'scripts/check_feature_tests.exs'],
            cwd=ROOT, capture_output=True, text=True, check=False)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
