"""Offline source-level Lynx pin regression; not proof or dependency verification.

This test intentionally does not import Elixir, fetch dependencies, or trust a
previously generated verification report.  The live pin gate separately checks
local BEAM, Lean, the resolved Git checkout and the supported toolchain.
"""

from __future__ import annotations

import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SHA = r"[0-9a-f]{40}"


class LynxSourcePinTest(unittest.TestCase):
    def test_git_spec_lock_and_policy_pin_match(self) -> None:
        mix = (ROOT / "mix.exs").read_text(encoding="utf-8")
        lock = (ROOT / "mix.lock").read_text(encoding="utf-8")
        pins = (ROOT / "scripts/verify_pins.py").read_text(encoding="utf-8")

        specs = re.findall(
            rf'\{{:lynx,\s*git:\s*"https://github\.com/josevalim/lynx\.git",'
            rf'\s*ref:\s*"({SHA})",\s*only:\s*:test\}}',
            mix,
            flags=re.S,
        )
        self.assertEqual(len(specs), 1, "exactly one immutable Lynx git ref expected")
        target = specs[0]
        locks = re.findall(
            rf'"lynx":\s*\{{:git,\s*"https://github\.com/josevalim/lynx\.git",'
            rf'\s*"({SHA})",\s*\[ref:\s*"({SHA})"\]\}}',
            lock,
        )
        self.assertEqual(locks, [(target, target)], "Mix lock SHA/ref must match")
        constants = re.findall(rf'^LYNX_COMMIT = "({SHA})"$', pins, flags=re.M)
        self.assertEqual(constants, [target], "runtime pin checker must match Mix")
        self.assertIn('mix.exs Lynx full SHA mismatch', pins)

    def test_verification_guide_cites_locked_target(self) -> None:
        spec = (ROOT / "mix.exs").read_text(encoding="utf-8")
        target = re.search(rf'ref:\s*"({SHA})"', spec)
        self.assertIsNotNone(target)
        guide = (ROOT / "guides/verification.md").read_text(encoding="utf-8")
        self.assertIn(f'This checkout pins Lynx `{target.group(1)}`', guide)
        self.assertIn(f'/blob/{target.group(1)}/README.md', guide)

    def test_source_only_checks_do_not_claim_a_verified_checkout(self) -> None:
        # Source matching alone is insufficient: verify_pins.py must still
        # execute the resolved checkout check in the real provisioned runtime.
        pins = (ROOT / "scripts/verify_pins.py").read_text(encoding="utf-8")
        self.assertIn('"deps/lynx", "rev-parse", "HEAD"', pins)
        self.assertIn('if outputs["lynx"] != LYNX_COMMIT:', pins)


if __name__ == "__main__":
    unittest.main()
