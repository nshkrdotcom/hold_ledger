"""Content coverage for authored help; browser tests exercise its behavior."""

import json
from pathlib import Path
import re
import unittest
from urllib.parse import urlsplit


APP = Path(__file__).resolve().parents[1]
WEB = APP / "lib/hold_ledger_review_web"


class HelpRegistryTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.registry = json.loads((APP / "priv/education_help.json").read_text())
        cls.controls = cls.registry["controls"]
        cls.router = (WEB / "router.ex").read_text()

    def test_control_explanations_are_short_and_identified(self):
        self.assertEqual(self.registry["schema"], 1)
        for key, entry in self.controls.items():
            with self.subTest(control=key):
                self.assertRegex(key, r"^[a-z]+\.[a-z_]+$")
                for field in ("term", "selector", "short", "detail", "link"):
                    self.assertTrue(entry[field].strip(), field)
                self.assertLessEqual(len(entry["short"].split()), 20)
                self.assertNotIn("javascript:", entry["link"])

    def test_screen_actions_have_help_or_an_explicit_reason(self):
        covered = set(
            re.findall(
                r'phx-click="([^"]+)"',
                " ".join(entry["selector"] for entry in self.controls.values()),
            )
        )
        exemptions = self.registry["action_exemptions"]
        missing = []
        for source in WEB.rglob("*.ex"):
            for action in re.findall(r'phx-click="([^"]+)"', source.read_text()):
                if action not in covered and action not in exemptions:
                    missing.append(f"{source.name}: {action}")
        self.assertEqual(missing, [], "Author help or record why the label is sufficient")
        for action, reason in exemptions.items():
            with self.subTest(action=action):
                self.assertGreater(len(reason.split()), 5)

    def test_page_guides_cover_the_learning_routes(self):
        guides = {page["path"]: page for page in self.registry["pages"]}
        self.assertEqual(len(guides), len(self.registry["pages"]))
        routes = re.findall(r'live "([^"]+)", EducationLive', self.router)
        for route in routes:
            if ":" in route:
                route = route.split("/:", 1)[0]
            with self.subTest(route=route):
                self.assertIn(route, guides)
                for field in ("title", "detail", "limit"):
                    self.assertTrue(guides[route][field].strip())

    def test_help_links_point_to_existing_app_routes(self):
        paths = re.findall(r'(?:live|get) "([^"]+)"', self.router)
        patterns = [re.compile("^" + re.sub(r":[^/]+", "[^/]+", path) + "$") for path in paths]
        for key, entry in self.controls.items():
            target = urlsplit(entry["link"])
            with self.subTest(control=key, path=target.path):
                self.assertFalse(target.netloc)
                self.assertTrue(any(pattern.fullmatch(target.path) for pattern in patterns))


if __name__ == "__main__":
    unittest.main()
