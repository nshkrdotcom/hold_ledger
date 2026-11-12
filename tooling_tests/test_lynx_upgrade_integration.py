"""Offline checks and live-checkout patch validation for the pinned Lynx migration.

A source-only pass is not equivalent to Lean compilation or kernel acceptance.
When deps/lynx exists, test the patch against pristine Git blobs at its exact pin.
"""

from __future__ import annotations

import hashlib
from pathlib import Path
import runpy
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "scripts"
if str(SCRIPTS) not in sys.path:
    sys.path.insert(0, str(SCRIPTS))


class LynxUpgradeIntegrationTest(unittest.TestCase):
    def test_runner_patch_retains_coordinator_and_axiom_guard(self) -> None:
        source = (ROOT / "verification/patches/lynx-parallel-runner.patch").read_text()
        for fragment in (
            'diff --git a/Lean/Lynx/Runner.lean b/Lean/Lynx/Runner.lean',
            'diff --git a/lib/lynx/commands.ex b/lib/lynx/commands.ex',
            '+    (inventory : Array Json) (inputArtifacts : NameMap ImportArtifacts)',
            '+      "check_source", "inventory", "artifact_inputs", "artifact_output"]',
            '+              if file.theorems.isEmpty then',
            's!"unexpected axiom in {name}: {axiomName}"',
            '+    | "plan" => planFiles j cache emit',
            '+    | "export" => exportArtifacts j cache',
            '+  @protocol_version "2.0"',
            '+    executable = System.find_executable("python3")',
        ):
            with self.subTest(fragment=fragment):
                self.assertIn(fragment, source)
        self.assertNotIn('SYNTHETIC UNKNOWABLE', source)

    def test_patch_applies_to_exact_pinned_git_blobs_when_present(self) -> None:
        dependency = ROOT / "deps/lynx"
        if not (dependency / ".git").exists():
            self.skipTest("deps/lynx not present; requires a provisioned checkout")
        from verify_pins import LYNX_COMMIT
        sha = subprocess.check_output(
            ["git", "-C", str(dependency), "rev-parse", "HEAD"], text=True,
        ).strip()
        self.assertEqual(sha, LYNX_COMMIT, "Lynx checkout is not pinned to expected commit")
        with tempfile.TemporaryDirectory() as tmp:
            target = Path(tmp)
            for name in ("Lean/Lynx/Runner.lean", "lib/lynx/commands.ex"):
                data = subprocess.check_output(
                    ["git", "-C", str(dependency), "show", f"HEAD:{name}"]
                )
                file = target / name
                file.parent.mkdir(parents=True, exist_ok=True)
                file.write_bytes(data)
            patch_file = ROOT / "verification/patches/lynx-parallel-runner.patch"
            subprocess.run(["git", "apply", "--check", str(patch_file)], cwd=target, check=True)
            subprocess.run(["git", "apply", str(patch_file)], cwd=target, check=True)
            runner = (target / "Lean/Lynx/Runner.lean").read_text()
            self.assertIn('private def elabOptions (async : Bool)', runner)
            self.assertIn('for snapshot in tree.getAll do', runner)
            self.assertIn('if file.theorems.isEmpty then', runner)
            self.assertIn('artifactOutput.getD', runner)
            self.assertIn('private def exportArtifacts', runner)
            self.assertIn('private def planFiles', runner)
            commands = (target / "lib/lynx/commands.ex").read_text()
            self.assertIn('scripts/verify_modules.py', commands)
            self.assertIn('@protocol_version "2.0"', commands)


class LocalRunUpgradeTest(unittest.TestCase):
    def run_local(self, arguments: list[str], fake_root: Path):
        events: list[str] = []

        def perform(command, **kwargs):
            events.append("run:" + " ".join(command))
            return type("Result", (), {"returncode": 0})()

        def prepare():
            events.append("prepare")

        with (patch("sys.argv", [str(SCRIPTS / "local_run.py"), *arguments]),
              patch("provision.ROOT", fake_root),
              patch("provision.local_env", return_value={}),
              patch("prepare_lynx.prepare", side_effect=prepare),
              patch("subprocess.run", side_effect=perform),
              patch.dict("os.environ", {"MIX_ENV": "test"})):
            with self.assertRaises(SystemExit) as exc:
                runpy.run_path(str(SCRIPTS / "local_run.py"), run_name="__main__")
            self.assertEqual(exc.exception.code, 0)
        return events

    def test_mix_deps_get_runs_before_patching(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            self.assertEqual(self.run_local(["mix", "deps.get"], Path(tmp)),
                             ["run:mix deps.get", "prepare"])

    def test_other_mix_commands_prepare_before_running(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            self.assertEqual(self.run_local(["mix", "test"], Path(tmp)),
                             ["prepare", "run:mix test"])

    def test_stale_command_host_is_recompiled_even_if_timestamp_is_newer(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source = root / "deps/lynx/lib/lynx/commands.ex"
            beam = root / "_build/test/lib/lynx/ebin/Elixir.Lynx.Commands.beam"
            source.parent.mkdir(parents=True)
            beam.parent.mkdir(parents=True)
            source.write_text("new patched source")
            beam.write_bytes(b"stale, from older source")
            events = self.run_local(["mix", "test"], root)
            self.assertEqual(events, ["prepare", "run:mix deps.compile lynx --force", "run:mix test"])
            stamp = beam.parent / ".hold_ledger_lynx_commands_sha256"
            self.assertEqual(stamp.read_text().strip(), hashlib.sha256(source.read_bytes()).hexdigest())
            events = self.run_local(["mix", "test"], root)
            self.assertEqual(events, ["prepare", "run:mix test"])


if __name__ == "__main__":
    unittest.main()
