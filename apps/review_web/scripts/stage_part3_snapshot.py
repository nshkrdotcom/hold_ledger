#!/usr/bin/env python3
"""Operator-only capture of a complete, immutable local source tree for Part 3.

Run in a trusted terminal, not from Phoenix. Git is used only to enumerate
tracked/untracked non-ignored files and record a commit hint; file bytes (not a
branch label or Git history) define the snapshot. No network operations.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

MAX_FILES = 1500
MAX_FILE = 3_000_000
MAX_TOTAL = 24_000_000


def canonical(obj):
    return json.dumps(obj, sort_keys=True, ensure_ascii=False, separators=(",", ":")).encode()


def sha(data):
    return hashlib.sha256(data).hexdigest()


def git(root, *args):
    p = subprocess.run(["git", "-C", str(root), *args], capture_output=True, check=True)
    return p.stdout


def capture(root, destination):
    root = root.resolve(strict=True)
    destination = destination.resolve()
    if not (root / "mix.exs").is_file() or not (root / "apps/review_web/mix.exs").is_file():
        raise ValueError("not a root Hold Ledger source tree")
    if destination.is_relative_to(root) and not str(destination.relative_to(root)).startswith("tmp/"):
        raise ValueError("snapshots must be under ignored tmp/ when inside source")
    paths = git(root, "ls-files", "-z", "--cached", "--others", "--exclude-standard").split(b"\0")
    # Tracked deletions are legitimate dirty proposals, not unreadable files to copy.
    # A file disappearing after this inventory is still rejected during capture.
    deleted = set(git(root, "ls-files", "--deleted", "-z").split(b"\0"))
    paths = sorted({os.fsdecode(p) for p in paths if p and p not in deleted})
    if not paths or len(paths) > MAX_FILES:
        raise ValueError("empty or excessive Git source inventory")
    entries = {}
    total = 0
    for rel in paths:
        p = Path(rel)
        if p.is_absolute() or ".." in p.parts or not p.parts or p.parts[0] == ".git" or str(p).startswith("tmp/"):
            raise ValueError(f"unsafe or ignored path: {rel}")
        full = root / p
        if full.is_symlink() or not full.is_file() or not full.resolve().is_relative_to(root):
            raise ValueError(f"nonregular or unsafe file: {rel}")
        data = full.read_bytes()
        total += len(data)
        if len(data) > MAX_FILE or total > MAX_TOTAL:
            raise ValueError("snapshot exceeds resource bounds")
        entries[rel] = sha(data)
    commit = git(root, "rev-parse", "--verify", "HEAD").decode().strip()
    if len(commit) != 40 or any(c not in "0123456789abcdef" for c in commit):
        raise ValueError("invalid commit identity")
    dirty = bool(git(root, "status", "--porcelain", "--untracked-files=all").strip())
    identity = {"schema_version": 1, "commit": commit, "dirty": dirty, "manifest": entries}
    digest = sha(canonical(identity))
    destination.mkdir(parents=True, exist_ok=True)
    final = destination / digest
    if final.exists():
        if validate(final) != digest:
            raise ValueError("existing snapshot name has mismatched bytes")
        return digest
    work = Path(tempfile.mkdtemp(prefix=".part3-", dir=destination))
    try:
        for rel, expected in entries.items():
            output = work / rel
            output.parent.mkdir(parents=True, exist_ok=True)
            data = (root / rel).read_bytes()
            if sha(data) != expected:
                raise ValueError(f"source changed during capture: {rel}")
            output.write_bytes(data)
        (work / ".part3-snapshot.json").write_bytes(canonical({**identity, "snapshot_id": digest}) + b"\n")
        if validate(work) != digest:
            raise ValueError("snapshot validation failed")
        work.rename(final)
    finally:
        if work.exists():
            shutil.rmtree(work)
    return digest


def validate(folder):
    obj = json.loads((folder / ".part3-snapshot.json").read_text())
    if sorted(obj) != sorted(("schema_version", "commit", "dirty", "manifest", "snapshot_id")):
        raise ValueError("invalid manifest schema")
    files = obj["manifest"]
    if obj["schema_version"] != 1 or not isinstance(files, dict) or len(files) > MAX_FILES:
        raise ValueError("invalid manifest")
    identity = {k: obj[k] for k in ("schema_version", "commit", "dirty", "manifest")}
    digest = sha(canonical(identity))
    if digest != obj["snapshot_id"]:
        raise ValueError("invalid snapshot identity")
    excluded = {'tmp', '_build', 'deps', 'node_modules', '.venv', '.local'}
    actual = set()
    for child in folder.rglob('*'):
        rel = child.relative_to(folder)
        if any(part in excluded for part in rel.parts):
            continue
        if child.is_symlink():
            raise ValueError(f'unmanifested symlink: {rel}')
        if child.is_file():
            actual.add(rel.as_posix())
    if actual != set(files) | {'.part3-snapshot.json'}:
        raise ValueError('unmanifested, added or missing source path')
    for rel, expected in files.items():
        p = Path(rel)
        if p.is_absolute() or ".." in p.parts or not p.parts or p.parts[0] == ".git":
            raise ValueError("unsafe path")
        source = folder / p
        if source.is_symlink() or not source.is_file() or not source.resolve().is_relative_to(folder.resolve()):
            raise ValueError("unsafe file")
        if sha(source.read_bytes()) != expected:
            raise ValueError("source drift")
    return digest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True, help="trusted local Git tree")
    parser.add_argument("--destination", type=Path, required=True, help="ignored tmp/review_studio/snapshots directory")
    args = parser.parse_args()
    try:
        print(capture(args.source, args.destination))
    except (OSError, ValueError, subprocess.CalledProcessError) as exc:
        print(f"snapshot refused: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
