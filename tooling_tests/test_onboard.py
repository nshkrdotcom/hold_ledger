"""Negative checks for fail-closed environment validation (standard library only)."""
import unittest
import contextlib
import io
import hashlib
import tempfile
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import provision
from unittest.mock import patch
import onboard
from onboard import validate


class PreflightTests(unittest.TestCase):
    def setUp(self):
        self.results = {
            name: {"status": "ok", "output": output}
            for name, output in {
                "elixir": "Elixir 1.20.4 (compiled with Erlang/OTP 29)",
                "mix": "Mix 1.20.4 (compiled with Erlang/OTP 29)",
                "otp": "29.1.2", "git": "git version 2.53.0",
                "elan": "elan 4.1.2", "lean": "Lean (version 4.35.0, x86_64)",
                "lake": "Lake version 5.0.0-src (Lean version 4.35.0)",
                "bwrap": "bubblewrap 0.11.1",
            }.items()
        }

    def test_valid(self):
        self.assertEqual(validate("proofs", self.results), [])

    def test_incompatible_runtime_fails_closed(self):
        for name, output in [("elixir", "Elixir 1.20.40 (compiled with Erlang/OTP 29)"),
                             ("elixir", "Elixir 1.20.4 (compiled with Erlang/OTP 28)"),
                             ("otp", "29"), ("otp", "29.1.20")]:
            with self.subTest(name=name, output=output):
                changed = {**self.results, name: {"status": "ok", "output": output}}
                self.assertTrue(validate("runtime", changed))

    def test_missing_or_failed_tool_fails_closed(self):
        for name in self.results:
            for status in ("missing", "exit_1", "error"):
                with self.subTest(name=name, status=status):
                    changed = {**self.results, name: {"status": status, "output": None}}
                    self.assertTrue(validate("proofs", changed))

    def test_wrong_proof_version(self):
        for name in ("lean", "lake"):
            changed = {**self.results, name: {"status": "ok", "output": self.results[name]["output"].replace("4.35.0", "4.35.1")}}
            self.assertTrue(validate("proofs", changed))

    def test_bad_runtime_prevents_installation(self):
        failed = {"status": "missing", "output": None}
        with patch("sys.argv", ["onboard.py", "--provision"]), \
             patch("onboard.platform.freedesktop_os_release", return_value={"ID": "ubuntu", "VERSION_ID": "26.04"}), \
             patch("onboard.platform.machine", return_value="x86_64"), \
             patch("onboard.check", return_value=failed), \
             patch("provision.provision") as install, contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(onboard.main(), 1)
            install.assert_not_called()

    def test_unsupported_environment_prevents_installation(self):
        with patch("sys.argv", ["onboard.py", "--provision"]), \
             patch("onboard.platform.freedesktop_os_release", return_value={"ID": "ubuntu", "VERSION_ID": "24.04"}), \
             patch("provision.provision") as install, contextlib.redirect_stdout(io.StringIO()) as output:
            self.assertEqual(onboard.main(), 1)
            install.assert_not_called()
            self.assertIn("Ubuntu 26.04", output.getvalue())

    def test_bad_download_hash_never_becomes_install_input(self):
        with tempfile.TemporaryDirectory() as directory, \
             patch("provision.LOCAL", Path(directory)), \
             patch("provision.urllib.request.urlopen", return_value=io.BytesIO(b"unexpected bytes")), \
             contextlib.redirect_stdout(io.StringIO()):
            pin = {"url": "https://example.invalid/tool.tar.gz", "sha256": "0" * 64}
            with self.assertRaisesRegex(RuntimeError, "Checksum mismatch"):
                provision.download(pin)
            self.assertFalse((Path(directory) / "downloads/tool.tar.gz").exists())

    def test_verified_cache_needs_no_network(self):
        with tempfile.TemporaryDirectory() as directory, \
             patch("provision.LOCAL", Path(directory)), \
             patch("provision.urllib.request.urlopen") as network, \
             contextlib.redirect_stdout(io.StringIO()):
            cached = Path(directory) / "downloads/tool.tar.gz"
            cached.parent.mkdir()
            cached.write_bytes(b"verified archive")
            pin = {"url": "https://example.invalid/tool.tar.gz",
                   "sha256": hashlib.sha256(cached.read_bytes()).hexdigest()}
            self.assertEqual(provision.download(pin), cached)
            network.assert_not_called()


if __name__ == "__main__":
    unittest.main()
