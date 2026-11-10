"""Focused reading provenance negatives; all sample files are synthetic."""
import copy
import datetime as dt
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
import validate_readings


def digest(data):
    return hashlib.sha256(data).hexdigest()


class ReadingIntegrityTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.sources = ['lib/hold_ledger/ledger.ex', 'mix.lock']
        self.index = {'schema_version': 1, 'scope': validate_readings.SCOPE,
                      'generated_at': dt.datetime.now(dt.timezone.utc).isoformat(),
                      'sources': {}, 'claims': {}}
        for name in self.sources:
            self.write(name, name.encode())
            self.index['sources'][name] = digest(name.encode())
        for slug in validate_readings.CLAIMS:
            artifact = f'tmp/verification/claim-reading/{"a" * 64}/{slug}/sample.lean'
            self.write(artifact, b'theorem synthetic : True := by trivial\n')
            self.index['claims'][slug] = {'status': 'elaborated', 'full_acceptance': False,
                'reports': [{'module': 'Synthetic', 'status': 'ok', 'cached': False}],
                'artifacts': [{'path': artifact, 'sha256': digest((self.root / artifact).read_bytes()),
                               'bytes': (self.root / artifact).stat().st_size}]}
        self.save()
        self.lookup = patch.object(validate_readings, 'source_paths', return_value=set(self.sources))
        self.lookup.start()
        self.addCleanup(self.lookup.stop)

    def write(self, name, data):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)

    def save(self):
        self.write(validate_readings.INDEX, json.dumps(self.index).encode())

    def test_complete_synthetic_manifest_and_artifacts_are_consistent(self):
        self.assertEqual(validate_readings.validate(self.root), [])

    def test_source_byte_drift_or_omitted_source_is_rejected(self):
        self.write(self.sources[0], b'tampered source')
        self.assertIn('focused source missing/changed', ' '.join(validate_readings.validate(self.root)))
        self.write(self.sources[0], self.sources[0].encode())
        del self.index['sources'][self.sources[0]]
        self.save()
        self.assertIn('incomplete', ' '.join(validate_readings.validate(self.root)))

    def test_missing_stale_or_misrouted_artifacts_are_rejected(self):
        slug = 'po_a2'
        record = self.index['claims'][slug]['artifacts'][0]
        path = self.root / record['path']
        path.write_text('different Lean terms')
        self.assertIn('artifact missing/changed', ' '.join(validate_readings.validate(self.root)))
        path.unlink()
        self.assertIn('artifact missing/changed', ' '.join(validate_readings.validate(self.root)))
        record['path'] = '../escape.lean'
        self.save()
        self.assertIn('invalid/duplicate artifact', ' '.join(validate_readings.validate(self.root)))

    def test_omitted_claim_or_false_full_acceptance_is_rejected(self):
        self.index['claims'].pop('po_b1_void')
        self.save()
        self.assertIn('exactly the three', ' '.join(validate_readings.validate(self.root)))
        self.setUpCaseRestored()
        self.index['claims']['po_a2']['full_acceptance'] = True
        self.save()
        self.assertIn('not a completed', ' '.join(validate_readings.validate(self.root)))

    def setUpCaseRestored(self):
        # Separate mutation while preserving the fixture's original three records.
        self.index['claims']['po_b1_void'] = copy.deepcopy(self.index['claims']['po_a2'])

    def test_cached_or_omitted_report_cannot_be_elaboration_evidence(self):
        self.index['claims']['po_a2']['reports'][0]['cached'] = True
        self.save()
        self.assertIn('possibly cached', ' '.join(validate_readings.validate(self.root)))
        self.index['claims']['po_a2']['reports'][0].pop('cached')
        self.save()
        self.assertIn('possibly cached', ' '.join(validate_readings.validate(self.root)))

    def test_path_traversal_or_symlink_is_not_current(self):
        self.assertIsNone(validate_readings.safe_file(self.root, '../outside'))
        target = self.root / 'untrusted'
        target.symlink_to('/etc/passwd')
        self.assertIsNone(validate_readings.safe_file(self.root, 'untrusted'))


if __name__ == '__main__':
    unittest.main()
