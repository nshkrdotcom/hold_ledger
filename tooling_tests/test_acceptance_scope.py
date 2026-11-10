"""Formal acceptance must not acquire external UI snapshot prerequisites."""
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class AcceptanceScopeTests(unittest.TestCase):
    def test_browser_suite_has_no_external_snapshot_or_silent_replay_skip(self):
        browser = ROOT / 'apps/review_web/test/browser'
        sources = '\n'.join(p.read_text() for p in browser.glob('*.cjs'))
        self.assertNotIn('PART3_TEST_BASELINE_ID', sources)
        self.assertNotIn('PART3_TEST_PROPOSAL_ID', sources)
        comparison = (browser / 'comparison.spec.cjs').read_text()
        self.assertIn('source selection uses registered identities', comparison)
        self.assertNotIn('test.skip', comparison)

    def test_formal_and_release_helpers_do_not_require_browser_snapshots(self):
        for name in ('check_suite.py', 'run_laws.py', 'run_mutants.py', 'run_differential.py'):
            source = (ROOT / 'scripts' / name).read_text()
            self.assertNotIn('PART3_TEST_', source)
        for path in (ROOT / '.github/workflows').glob('*.yml'):
            self.assertNotIn('PART3_TEST_', path.read_text())
