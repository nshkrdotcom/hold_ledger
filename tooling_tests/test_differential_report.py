"""Reject false, stale and partial differential acceptance evidence without Lean."""
import hashlib
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
        manifest = {}
        for rel in ['lib/hold_ledger/ledger.ex', 'lib/hold_ledger/spec.ex',
                    'scripts/differential.exs', 'scripts/run_differential.py']:
            file = self.root / rel
            file.parent.mkdir(parents=True, exist_ok=True)
            file.write_text('source ' + rel)
            manifest[rel] = hashlib.sha256(file.read_bytes()).hexdigest()
        self.report = {
            'accepted': True, 'source_unchanged': True, 'attempted': 245,
            'comparisons': 245, 'mismatches': 0, 'unsupported': 0,
            'kernel_cases': 8, 'evaluator_exit': 0, 'source_sha256': manifest,
        }
        self.path = self.root / 'tmp/differential/report.json'
        self.path.parent.mkdir(parents=True)

    def validate(self):
        self.path.write_text(json.dumps(self.report))
        return module.validate_report(self.path, self.root, 100)[0]

    def test_valid_accepted_report(self):
        self.assertTrue(self.validate())

    def test_missing_report_rejected(self):
        self.assertFalse(module.validate_report(self.path, self.root, 100)[0])

    def test_partial_counts_rejected(self):
        self.report['comparisons'] -= 1
        self.assertFalse(self.validate())

    def test_unchecked_kernel_or_unsupported_rejected(self):
        self.report['kernel_cases'] = None
        self.assertFalse(self.validate())
        self.report['kernel_cases'] = 8
        self.report['unsupported'] = 1
        self.assertFalse(self.validate())

    def test_source_drift_and_manifest_omissions_rejected(self):
        self.report['source_sha256'].pop('lib/hold_ledger/ledger.ex')
        self.assertFalse(self.validate())
        self.report['source_sha256']['lib/hold_ledger/ledger.ex'] = '0' * 64
        self.assertFalse(self.validate())

    def test_false_flag_rejected(self):
        self.report['source_unchanged'] = False
        self.assertFalse(self.validate())


if __name__ == '__main__':
    unittest.main()
