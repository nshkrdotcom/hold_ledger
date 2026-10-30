"""Check the educational catalog's coverage and source references without BEAM.

These checks validate navigation data and provenance. They do not judge the
meaning of the prose, evaluate laws, or establish formal proof acceptance.
Run from any directory: python3 apps/review_web/scripts/test_education_content.py
"""

from collections import Counter
import json
from pathlib import Path
import re
import unittest


APP = Path(__file__).resolve().parents[1]
ROOT = APP.parents[1]
PRIV = APP / "priv"
FAMILIES = {
    "Foundations",
    "Admission",
    "Single-step safety",
    "Identity & lifecycle",
    "Histories",
    "Attempts",
    "Processor & exposure",
    "Composite & recovery",
}
COPY_FIELDS = (
    "title",
    "scenario",
    "must_happen",
    "wrong_behavior",
    "why_others_miss",
    "does_not_cover",
)
# These IDs are public glossary anchors and authored tooltip lookup keys.
TERM_IDS = set(
    "hold capacity authorization processor timeout unknown reserved sent "
    "authorized voiding voided declined request-id idempotency event effect "
    "pure-core specification law requires expects invariant witness "
    "counterexample mutation claim theorem lemma lean lynx elixir phoenix "
    "induction axiom omega aesop cases sorry proof-status source-identity "
    "proof-dependency pointwise hypothetical assumption journal replay "
    "composite terminal-fence coverage vacuity effect-intent policy-gap review".split()
)
REFERENCE_ROUTES = {
    "/start", "/system", "/guarantees", "/proofs", "/assurance",
    "/atlas", "/repository", "/lens/po_a2", "/lens/po_exposure_retain",
}


def read_json(path):
    return json.loads(path.read_text(encoding="utf-8"))


class EducationContentTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.catalog = read_json(ROOT / "verification/laws.json")["laws"]
        cls.claim_file = read_json(PRIV / "education_claims.json")
        cls.claims = cls.claim_file["claims"]
        cls.terms = read_json(PRIV / "education_glossary.json")["terms"]

    def source_path(self, value):
        self.assertIsInstance(value, str)
        self.assertTrue(value, "A source reference needs a path")
        path = Path(value)
        self.assertFalse(path.is_absolute(), value)
        self.assertNotIn("..", path.parts, value)
        resolved = (ROOT / path).resolve()
        self.assertTrue(resolved.is_relative_to(ROOT), value)
        self.assertTrue(resolved.is_file(), f"Missing source: {value}")
        return resolved

    def test_catalog_coverage_has_no_missing_or_duplicate_claims(self):
        actual = Counter(claim["slug"] for claim in self.claims)
        expected = Counter(law["slug"] for law in self.catalog)
        self.assertEqual(actual, expected)
        self.assertTrue(all(count == 1 for count in actual.values()))

    def test_each_claim_has_an_authored_reading_and_known_family(self):
        self.assertEqual(self.claim_file.get("schema"), 2)
        self.assertEqual({claim["family"] for claim in self.claims}, FAMILIES)
        for claim in self.claims:
            with self.subTest(claim=claim["slug"]):
                for field in COPY_FIELDS:
                    self.assertIsInstance(claim.get(field), str, field)
                    self.assertTrue(claim[field].strip(), field)
                self.assertEqual(claim["risk"], claim["wrong_behavior"])
        # Copying a family-level warning loses the individual claim's example.
        for field in ("scenario", "wrong_behavior"):
            values = [claim.get(field) for claim in self.claims]
            self.assertEqual(len(values), len(set(values)), field)

    def test_claim_provenance_points_to_the_registered_source(self):
        registered = {law["slug"]: law for law in self.catalog}
        for claim in self.claims:
            with self.subTest(claim=claim["slug"]):
                refs = claim.get("provenance")
                self.assertIsInstance(refs, list)
                self.assertTrue(refs)
                for ref in refs:
                    self.assertIn(
                        ref.get("kind"),
                        {"claim", "policy", "mutant", "exercise", "editorial"},
                    )
                    self.assertTrue(ref.get("reference"))
                    path = self.source_path(ref.get("path"))
                    if ref.get("section") and path.suffix == ".md":
                        headings = re.findall(
                            r"^#{1,6} (.+)$", path.read_text(encoding="utf-8"), re.M
                        )
                        self.assertIn(ref["section"], headings)
                self.assertTrue(
                    any(
                        ref["kind"] == "claim"
                        and ref["reference"] == claim["slug"]
                        and ref["path"] == registered[claim["slug"]]["file"]
                        for ref in refs
                    ),
                    "The explanation must cite this claim's actual registered source",
                )

    def test_named_mutants_match_their_unchanged_target_laws(self):
        source_targets = {}
        for readme in sorted((ROOT / "mutants").glob("*/README.md")):
            mutant = "M" + str(int(readme.parent.name.split("_", 1)[0]))
            targets = set(re.findall(r"`(po_[a-z0-9_]+)`", readme.read_text()))
            self.assertEqual(len(targets), 1, str(readme))
            source_targets[mutant] = (targets.pop(), str(readme.relative_to(ROOT)))

        authored = {}
        for claim in self.claims:
            with self.subTest(claim=claim["slug"]):
                mutants = claim.get("named_mutants")
                self.assertIsInstance(mutants, list)
                self.assertEqual(len(mutants), len(set(mutants)))
                for mutant in mutants:
                    self.assertNotIn(mutant, authored, "A mutant has one target law")
                    refs = [
                        ref for ref in claim["provenance"]
                        if ref["kind"] == "mutant" and ref["reference"] == mutant
                    ]
                    self.assertEqual(len(refs), 1, mutant)
                    authored[mutant] = (claim["slug"], refs[0]["path"])
        self.assertEqual(authored, source_targets)

    def test_exercise_links_have_a_real_guide_reference(self):
        guide = "guides/payment_hold_review_exercises.md"
        available = set(re.findall(r"\((P\d{2})\)", (ROOT / guide).read_text()))
        for claim in self.claims:
            with self.subTest(claim=claim["slug"]):
                examples = claim.get("exercise_ids")
                self.assertIsInstance(examples, list)
                self.assertEqual(len(examples), len(set(examples)))
                self.assertTrue(set(examples) <= available)
                for example in examples:
                    self.assertTrue(
                        any(
                            ref["kind"] == "exercise"
                            and ref["reference"] == example
                            and ref["path"] == guide
                            for ref in claim["provenance"]
                        )
                    )

    def test_glossary_keeps_public_anchors_and_real_source_references(self):
        ids = [term["id"] for term in self.terms]
        self.assertEqual(set(ids), TERM_IDS)
        self.assertEqual(len(ids), len(set(ids)))
        for term in self.terms:
            with self.subTest(term=term["id"]):
                for field in ("term", "short", "detail", "example"):
                    self.assertIsInstance(term.get(field), str, field)
                    self.assertTrue(term[field].strip(), field)
                self.assertIn(term["link"], REFERENCE_ROUTES)
                self.source_path(term.get("source_path"))


if __name__ == "__main__":
    unittest.main(verbosity=2)
