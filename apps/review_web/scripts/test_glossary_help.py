"""Validate the glossary data consumed by contextual help and glossary cards.

These checks protect content shape, public terminology, short definitions and
links. They do not establish the truth of a claim or check a formal proof.
"""

import json
from pathlib import Path
import re
import unittest
from urllib.parse import urlparse


APP = Path(__file__).resolve().parents[1]
ROOT = APP.parents[1]
GLOSSARY = APP / "priv/education_glossary.json"
NEW_CONCEPTS = {
    "binding", "clause", "helper", "basis", "source-generation", "coupled-model"
}
LOOKUP_HOSTS = {
    "github.com", "lean-lang.org", "hexdocs.pm", "elixir.hexdocs.pm",
    "phoenix-live-view.hexdocs.pm", "docs.stripe.com"
}


class GlossaryHelpTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.terms = json.loads(GLOSSARY.read_text(encoding="utf-8"))["terms"]
        cls.by_id = {term["id"]: term for term in cls.terms}

    def test_inspection_concepts_have_entries(self):
        self.assertTrue(NEW_CONCEPTS <= self.by_id.keys())
        self.assertIn("candidate", self.by_id["hypothetical"]["aliases"])
        self.assertIn("fencing", self.by_id["terminal-fence"]["aliases"])

    def test_contextual_fields_are_complete(self):
        for term in self.terms:
            with self.subTest(term=term["id"]):
                for field in ("short", "detail", "why_it_matters", "limit", "example"):
                    self.assertIsInstance(term.get(field), str, field)
                    self.assertTrue(term[field].strip(), field)
                self.assertIn(term.get("level"), {"beginner", "practitioner", "expert"})
                self.assertLessEqual(len(term["short"].split()), 20)
                path = ROOT / term["source_path"]
                self.assertTrue(path.resolve().is_relative_to(ROOT), str(path))
                self.assertTrue(path.is_file(), str(path))

    def test_lookup_links_are_named_primary_sources(self):
        for term in self.terms:
            with self.subTest(term=term["id"]):
                links = term.get("lookup")
                self.assertIsInstance(links, list)
                self.assertGreaterEqual(len(links), 1)
                self.assertLessEqual(len(links), 2)
                for link in links:
                    self.assertIsInstance(link.get("label"), str)
                    self.assertTrue(link["label"].strip())
                    parsed = urlparse(link.get("url", ""))
                    self.assertEqual(parsed.scheme, "https")
                    self.assertIn(parsed.netloc, LOOKUP_HOSTS)
                    self.assertFalse(parsed.username or parsed.password)
                    if parsed.netloc == "github.com" and parsed.path.startswith(
                        "/nshkrdotcom/hold_ledger/blob/main/"
                    ):
                        relative = parsed.path.removeprefix(
                            "/nshkrdotcom/hold_ledger/blob/main/"
                        )
                        self.assertTrue((ROOT / relative).is_file(), relative)

    def test_aliases_are_unambiguous_and_preserve_canonical_ids(self):
        seen = {term["id"].casefold(): term["id"] for term in self.terms}
        self.assertEqual(len(seen), len(self.terms))
        for term in self.terms:
            self.assertRegex(term["id"], r"^[a-z][a-z0-9-]*$")
            aliases = term.get("aliases", [])
            self.assertIsInstance(aliases, list)
            for alias in aliases:
                self.assertIsInstance(alias, str)
                self.assertTrue(alias.strip())
                key = re.sub(r"\s+", " ", alias.strip().casefold())
                if key in seen:
                    self.assertEqual(
                        seen[key], term["id"], f"Ambiguous glossary alias: {alias}"
                    )
                seen[key] = term["id"]


if __name__ == "__main__":
    unittest.main()
