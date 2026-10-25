"""Durable status and rejection of incomplete background verification results."""
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import background_laws


class BackgroundLawTests(unittest.TestCase):
    def test_status_updates_are_atomic_and_replace_prior_state(self):
        with tempfile.TemporaryDirectory() as folder:
            directory = Path(folder)
            background_laws.save_status(directory, {"state": "running"})
            background_laws.save_status(directory, {"state": "failed", "exit_code": 2})
            self.assertEqual(json.loads((directory / "status.json").read_text()),
                             {"state": "failed", "exit_code": 2})
            self.assertFalse((directory / "status.json.tmp").exists())

    def test_dirty_source_cannot_launch_a_background_acceptance_run(self):
        with mock.patch.object(background_laws.subprocess, "check_output", return_value=" M lib/example.ex\n"), \
             mock.patch.object(background_laws.subprocess, "Popen") as launch:
            with self.assertRaisesRegex(RuntimeError, "Commit the source"):
                background_laws.start()
            launch.assert_not_called()
