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

    def test_source_drift_is_reported_instead_of_certifying_final_bytes(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'source.ex'
            path.write_text('original')
            manifest = {str(path): run_laws.sha(path)}
            self.assertEqual(run_laws.changed_sources(manifest), [])
            path.write_text('changed during verification')
            self.assertEqual(run_laws.changed_sources(manifest), [str(path)])
            path.unlink()
            self.assertEqual(run_laws.changed_sources(manifest), [str(path)])

    def test_new_source_files_also_invalidate_acceptance(self):
        with tempfile.TemporaryDirectory() as directory:
            original = Path(directory) / 'original.ex'
            added = Path(directory) / 'added.ex'
            original.write_text('original')
            manifest = {str(original): run_laws.sha(original)}
            added.write_text('new behavior')
            self.assertEqual(run_laws.changed_sources(manifest, [original, added]), [str(added)])
