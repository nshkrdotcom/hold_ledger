"""Reject false and partial differential acceptance evidence without Lean."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest


SPEC = importlib.util.spec_from_file_location(
    'run_differential', Path(__file__).resolve().parents[1] / 'scripts/run_differential.py')
module = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(module)


class DifferentialReportTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.report = {
            'accepted': True, 'attempted': 245,
            'comparisons': 245, 'mismatches': 0, 'unsupported': 0,
            'kernel_cases': 8, 'evaluator_exit': 0,
        }
        self.path = self.root / 'tmp/differential/report.json'
        self.path.parent.mkdir(parents=True)

    def validate(self):
        self.path.write_text(json.dumps(self.report))
        return module.validate_report(self.path, 100)[0]

    def test_valid_accepted_report(self):
        self.assertTrue(self.validate())

    def test_missing_report_rejected(self):
        self.assertFalse(module.validate_report(self.path, 100)[0])

    def test_partial_counts_rejected(self):
        self.report['comparisons'] -= 1
        self.assertFalse(self.validate())

    def test_unchecked_kernel_or_unsupported_rejected(self):
        self.report['kernel_cases'] = None
        self.assertFalse(self.validate())
        self.report['kernel_cases'] = 8
        self.report['unsupported'] = 1
        self.assertFalse(self.validate())

    def test_false_flag_rejected(self):
        self.report['accepted'] = False
        self.assertFalse(self.validate())


if __name__ == '__main__':
    unittest.main()
