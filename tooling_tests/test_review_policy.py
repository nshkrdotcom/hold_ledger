import importlib.util
import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('review_policy', ROOT / 'scripts/review_policy.py')
review = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(review)


class ReviewPolicyTest(unittest.TestCase):
    def test_codeowners_matches_shared_policy(self):
        self.assertEqual((ROOT / '.github/CODEOWNERS').read_text(), review.codeowners(review.policy()))

    def test_sensitive_paths_have_owners_and_require_formal(self):
        data = review.policy()
        paths = ['verification/baseline.json', 'scripts/obligations.py',
                 'scripts/verify_laws.exs', 'scripts/verify_pins.py',
                 'scripts/toolchains.json', 'lean-toolchain', 'mix.lock', 'uv.lock',
                 'tooling_tests/test_formal_gate.py', '.github/CODEOWNERS',
                 'test/support/lean/Lookup.lean', 'mutants/02_timeout_release/mutant.patch']
        for path in paths:
            with self.subTest(path=path):
                self.assertTrue(any(path == p.lstrip('/') or
                                    (p.endswith('/') and path.startswith(p.lstrip('/')))
                                    for p in data['tier1_paths']))
                self.assertTrue(path in data['formal_files'] or
                                any(path.startswith(p) for p in data['formal_prefixes']))
