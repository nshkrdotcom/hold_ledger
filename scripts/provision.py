"""Pinned, repository-local native tool provisioning. Invoked by onboard.py."""
from __future__ import annotations

import hashlib
import json
import os
import platform
import subprocess
import tarfile
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LOCAL = ROOT / ".local"
PINS = json.loads((ROOT / "scripts/toolchains.json").read_text())


def local_env() -> dict[str, str]:
    env = os.environ.copy()
    env["ELAN_HOME"] = str(LOCAL / "elan")
    env["ELAN_TOOLCHAIN"] = PINS["lean_toolchain"]
    env["PATH"] = str(LOCAL / "elan/bin") + os.pathsep + env.get("PATH", "")
    # Do not write build caches into the user's home.
    env["XDG_CACHE_HOME"] = str(LOCAL / "cache")
    return env


def digest(path: Path) -> str:
    with path.open("rb") as f:
        return hashlib.file_digest(f, "sha256").hexdigest()


def download(pin: dict) -> Path:
    dest = LOCAL / "downloads" / pin["url"].rsplit("/", 1)[-1]
    dest.parent.mkdir(parents=True, exist_ok=True)
    if dest.exists() and digest(dest) == pin["sha256"]:
        print(f"Verified cached {dest.name}", flush=True)
        return dest
    part = dest.with_suffix(dest.suffix + ".partial")
    print(f"Downloading {pin['url']}", flush=True)
    with urllib.request.urlopen(pin["url"], timeout=60) as src, part.open("wb") as out:
        while chunk := src.read(1024 * 1024):
            out.write(chunk)
    if digest(part) != pin["sha256"]:
        raise RuntimeError(f"Checksum mismatch: {part}; refusing extraction")
    part.replace(dest)
    return dest


def provision() -> None:
    if (platform.system(), platform.machine()) != ("Linux", "x86_64"):
        raise RuntimeError("Pinned native artifacts currently support Linux x86_64 only")
    if (ROOT / "lean-toolchain").read_text().strip() != PINS["lean_toolchain"]:
        raise RuntimeError("lean-toolchain disagrees with provisioning pins")
    LOCAL.mkdir(exist_ok=True)
    subprocess.run(["git", "check-ignore", "--quiet", ".local/"], cwd=ROOT, check=True)
    env = local_env()
    elan = LOCAL / "elan/bin/elan"
    if not elan.exists():
        archive = download(PINS["elan"])
        unpack = LOCAL / "elan-init"
        unpack.mkdir(exist_ok=True)
        with tarfile.open(archive, "r:gz") as tar:
            tar.extractall(unpack, filter="data")
        subprocess.run([str(unpack / "elan-init"), "-y", "--no-modify-path",
                        "--default-toolchain", "none"], env=env, check=True)
    elan_version = subprocess.check_output([str(elan), "--version"], env=env, text=True)
    if not elan_version.startswith("elan " + PINS["elan"]["version"] + " "):
        raise RuntimeError("Existing local Elan differs from pinned 4.2.4; inspect .local/elan before retrying")
    lean_dir = LOCAL / PINS["lean"]["directory"]
    marker = lean_dir / ".hold-ledger-provisioned"
    if not marker.exists():
        if lean_dir.exists():
            raise RuntimeError(f"Incomplete extraction at {lean_dir}; inspect and remove only that local directory before retry")
        import zstandard
        archive = download(PINS["lean"])
        print("Extracting verified Lean release locally", flush=True)
        with archive.open("rb") as f, zstandard.ZstdDecompressor().stream_reader(f) as stream:
            with tarfile.open(fileobj=stream, mode="r|") as tar:
                tar.extractall(LOCAL, filter="data")
        marker.write_text(PINS["lean"]["sha256"] + "\n")
    if marker.read_text().strip() != PINS["lean"]["sha256"]:
        raise RuntimeError("Installed Lean marker does not match pinned archive")
    installed = subprocess.check_output([str(elan), "toolchain", "list"], env=env, text=True)
    if PINS["lean_toolchain"] not in [line.split()[0] for line in installed.splitlines() if line.split()]:
        subprocess.run([str(elan), "toolchain", "link", PINS["lean_toolchain"], str(lean_dir)], env=env, check=True)
    else:
        selected = subprocess.check_output([str(elan), "which", "lean"], cwd=ROOT, env=env, text=True).strip()
        if Path(selected).resolve() != (lean_dir / "bin/lean").resolve():
            raise RuntimeError("Pinned Elan toolchain points outside its expected local installation; inspect .local/elan")
        print("Reusing the verified local toolchain link", flush=True)
    for tool in ("elan", "lean", "lake"):
        subprocess.run([str(LOCAL / "elan/bin" / tool), "--version"], cwd=ROOT, env=env, check=True)
    print("Local toolchains ready; use scripts/local_run.py for commands.", flush=True)
