"""Incomplete, misregistered and orphan proof obligations cannot hide in a green release."""
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from obligations import check_registration, coverage, orphan_modules


class ObligationTests(unittest.TestCase):
    def test_a_pending_required_group_makes_release_incomplete(self):
        required = [{'slug': 'first'}, {'slug': 'second'}]
        registered = [{'slug': 'first', 'status': 'supported'}, {'slug': 'second', 'status': 'pending'}]
        self.assertEqual(coverage(required, registered, ['first'])['missing'], ['second'])
        self.assertFalse(coverage(required, registered, ['first'])['complete'])
        registered[1]['status'] = 'supported'
        self.assertTrue(coverage(required, registered, ['first', 'second'])['complete'])

    def test_qualified_theorem_identity_cannot_change(self):
        required = [{'slug': 'first', 'theorems': ['Intended.statement']}]
        with self.assertRaisesRegex(RuntimeError, 'identity changed'):
            check_registration(required, [{'slug': 'first', 'theorems': ['Other.statement']}])
        with self.assertRaisesRegex(RuntimeError, 'group identities'):
            check_registration(required, [])

    def test_dependency_helpers_are_reachable_but_orphans_are_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder)
            (path / 'Root.lean').write_text('public import HoldLedgerProof.Helper\n')
            (path / 'Helper.lean').write_text('module\n')
            (path / 'Forgotten.lean').write_text('module\n')
            self.assertEqual(orphan_modules(path, ['HoldLedgerProof.Root']), ['HoldLedgerProof.Forgotten'])
