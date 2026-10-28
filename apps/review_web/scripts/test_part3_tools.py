"""Stdlib tests of actual snapshot staging and OS-runner boundaries.

Controlled fake uv is *only* a subprocess lifecycle fixture, not an Elixir
execution, semantic result, source-derived evaluator or model observation.
"""
import contextlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent

def module(file, name):
    spec = importlib.util.spec_from_file_location(name, ROOT / file)
    obj = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(obj)
    return obj

stage = module("stage_part3_snapshot.py", "part3_stage")

class SnapshotTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="part3-stage-test-")
        self.addCleanup(self.temp.cleanup)
        self.repo = Path(self.temp.name) / "checkout"
        self.repo.mkdir()
        (self.repo / "apps/review_web").mkdir(parents=True)
        (self.repo / "mix.exs").write_text("# fixture\n")
        (self.repo / "apps/review_web/mix.exs").write_text("# fixture\n")
        (self.repo / ".gitignore").write_text("tmp/\n")
        self.git("init", "-q")
        self.git("config", "user.email", "synthetic@example.invalid")
        self.git("config", "user.name", "Synthetic")
        self.git("add", ".")
        self.git("commit", "-qm", "Synthetic fixture")
        self.out = self.repo / "tmp/review_studio/snapshots"

    def git(self, *args):
        return subprocess.run(["git", *args], cwd=self.repo, check=True,
                              text=True, capture_output=True).stdout

    def test_content_manifest_dirty_identity_and_ignored_files(self):
        a = stage.capture(self.repo, self.out)
        self.assertEqual(stage.validate(self.out / a), a)
        manifest = json.loads((self.out / a / ".part3-snapshot.json").read_text())
        self.assertFalse(manifest["dirty"])
        self.assertNotIn("tmp/ignored", manifest["manifest"])
        (self.repo / "mix.exs").write_text("# controlled source change\n")
        b = stage.capture(self.repo, self.out)
        self.assertNotEqual(a, b)
        self.assertTrue(json.loads((self.out / b / ".part3-snapshot.json").read_text())["dirty"])
        self.assertEqual(stage.capture(self.repo, self.out), b)
        (self.out / b / "mix.exs").write_text("tamper\n")
        with self.assertRaises(ValueError):
            stage.validate(self.out / b)

    def test_dirty_deletion_is_content_addressed_and_not_recreated(self):
        removed = self.repo / "obsolete.ex"
        removed.write_text("# original source\n")
        self.git("add", ".")
        self.git("commit", "-qm", "Source to delete")
        old = stage.capture(self.repo, self.out)
        removed.unlink()
        new = stage.capture(self.repo, self.out)
        self.assertNotEqual(old, new)
        self.assertEqual(stage.validate(self.out / new), new)
        self.assertFalse((self.out / new / "obsolete.ex").exists())
        self.assertTrue((self.out / old / "obsolete.ex").exists())

    def test_unmanifested_file_cannot_be_added_to_snapshot(self):
        identity = stage.capture(self.repo, self.out)
        snapshot = self.out / identity
        (snapshot / "unmanifested.ex").write_text("# unaudited executable\n")
        with self.assertRaisesRegex(ValueError, "unmanifested"):
            stage.validate(snapshot)
        (snapshot / "unmanifested.ex").unlink()
        self.assertEqual(stage.validate(snapshot), identity)

    def test_symlink_file_refused_not_copied(self):
        (self.repo / "untrusted-link").symlink_to("mix.exs")
        with self.assertRaisesRegex(ValueError, "unsafe file"):
            stage.capture(self.repo, self.out)

    def test_outside_tmp_destination_refused(self):
        with self.assertRaisesRegex(ValueError, "ignored tmp"):
            stage.capture(self.repo, self.repo / "owned-output")

class ProcessRunnerTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="part3-worker-test-")
        self.addCleanup(self.temp.cleanup)
        base = Path(self.temp.name)
        self.bin = base / "bin"
        self.bin.mkdir()
        self.root = base / "pending"
        (self.root / "scripts").mkdir(parents=True)
        wrapper = "# fake wrapper; not executed by these tests\n"
        (self.root / "scripts/local_run.py").write_text(wrapper)
        identity = {"schema_version": 1, "commit": "0" * 40, "dirty": True,
                    "manifest": {"scripts/local_run.py": stage.sha(wrapper.encode())}}
        self.id = stage.sha(stage.canonical(identity))
        target = base / self.id
        self.root.rename(target)
        self.root = target
        (self.root / ".part3-snapshot.json").write_text(json.dumps({**identity, "snapshot_id": self.id}))
        self.request = base / "request.json"
        self.request.write_text(json.dumps({"snapshot_id": self.id}))
        self.out = base / "result.json"
        self.env = {**os.environ, "PATH": str(self.bin) + os.pathsep + os.environ.get("PATH", "")}

    def fake_uv(self, body):
        script = self.bin / "uv"
        script.write_text("#!/usr/bin/env python3\nimport sys,time,pathlib\n" + body + "\n")
        script.chmod(0o755)

    def command(self, timeout=3):
        return [sys.executable, str(ROOT / "part3_worker.py"),
                "--kind", "pointwise", "--snapshot-root", str(self.root),
                "--request", str(self.request), "--result", str(self.out),
                "--timeout", str(timeout)]

    def test_subprocess_success_is_only_fake_lifecycle_not_elixir(self):
        self.fake_uv('pathlib.Path(sys.argv[-1]).write_text("synthetic result")')
        proc = subprocess.Popen(self.command(), stdin=subprocess.PIPE, env=self.env)
        try:
            self.assertEqual(proc.wait(timeout=5), 0)
            self.assertEqual(self.out.read_text(), "synthetic result")
        finally:
            proc.stdin.close()

    def test_crash_cannot_appear_as_success(self):
        self.fake_uv('sys.exit(9)')
        proc = subprocess.Popen(self.command(), stdin=subprocess.PIPE, env=self.env)
        try:
            self.assertEqual(proc.wait(timeout=5), 2)
            self.assertFalse(self.out.exists())
        finally:
            proc.stdin.close()

    def test_timeout_is_not_success(self):
        self.fake_uv('time.sleep(30)')
        proc = subprocess.Popen(self.command(timeout=1), stdin=subprocess.PIPE, env=self.env)
        try:
            self.assertEqual(proc.wait(timeout=7), 124)
            self.assertFalse(self.out.exists())
        finally:
            proc.stdin.close()

    def test_unmanifested_source_refused_before_spawn(self):
        (self.root / "unmanifested.py").write_text("raise RuntimeError('must never execute')")
        self.fake_uv('pathlib.Path(sys.argv[-1]).write_text("should never happen")')
        proc = subprocess.Popen(self.command(), stdin=subprocess.PIPE, env=self.env)
        try:
            self.assertEqual(proc.wait(timeout=5), 3)
            self.assertFalse(self.out.exists())
        finally:
            proc.stdin.close()

    def test_mismatched_snapshot_refused_before_spawn(self):
        self.request.write_text(json.dumps({"snapshot_id": "b" * 64}))
        self.fake_uv('pathlib.Path(sys.argv[-1]).write_text("should never happen")')
        proc = subprocess.Popen(self.command(), stdin=subprocess.PIPE, env=self.env)
        try:
            self.assertEqual(proc.wait(timeout=5), 3)
            self.assertFalse(self.out.exists())
        finally:
            proc.stdin.close()

if __name__ == '__main__':
    unittest.main()
