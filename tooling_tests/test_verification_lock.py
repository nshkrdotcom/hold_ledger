"""Concurrent acceptance runs must not overwrite one another's artifacts."""
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
import run_laws


class VerificationLockTests(unittest.TestCase):
    def test_an_overlapping_run_fails_before_mutating_artifacts(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'acceptance.lock'
            with run_laws.acceptance_lock(path):
                with self.assertRaisesRegex(RuntimeError, 'already running'):
                    with run_laws.acceptance_lock(path):
                        self.fail('overlapping acceptance entered its mutation section')
            with run_laws.acceptance_lock(path):
                self.assertTrue(path.is_file())
