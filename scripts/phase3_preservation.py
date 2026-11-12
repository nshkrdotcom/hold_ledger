#!/usr/bin/env python3
"""Preserve runtime policy and authored law statements from the accepted snapshot.

The historical baseline is immutable. Tooling implementation, build metadata and
execution documentation are deliberately outside the current policy freeze: the
parallelism rework replaces those directly. Runtime/policy and theorem domains
remain protected independently of the new execution implementation.
"""
from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASELINE = ROOT / "verification/research/0300_preservation_baseline.json"


def policy_file(path: str) -> bool:
    return path.startswith(('lib/', 'test/')) or path in {
        'guides/specification.md', 'guides/runtime.md', 'guides/processors.md',
        'verification/laws.json', 'verification/obligations.json',
    }


def digest(body: bytes) -> str:
    return hashlib.sha256(body).hexdigest()


def declaration(body: str) -> str:
    """Preserve the exact requires/expects region; proof bodies may migrate."""
    start = body.index("    law(")
    end = body.index('      proof: ~LEAN"""', start)
    return body[start:end]


def current() -> dict:
    baseline = json.loads(BASELINE.read_text(encoding="utf-8"))
    protected = {}
    for path in sorted(path for path in baseline["protected_files"] if policy_file(path)):
        p = ROOT / path
        if not p.is_file():
            raise ValueError(f"protected file removed: {path}")
        protected[path] = digest(p.read_bytes())
    groups = {}
    for path in sorted(baseline["dsl_contracts"]):
        p = ROOT / path
        if not p.is_file():
            raise ValueError(f"law source removed: {path}")
        groups[path] = digest(declaration(p.read_text(encoding="utf-8")).encode("utf-8"))
    return {"protected_files": protected, "dsl_contracts": groups}


def check() -> None:
    baseline = json.loads(BASELINE.read_text(encoding="utf-8"))
    seen = current()
    baseline['protected_files'] = {path: sha for path, sha in baseline['protected_files'].items()
                                   if policy_file(path)}
    for category in ("protected_files", "dsl_contracts"):
        changed = [path for path, sha in baseline[category].items()
                   if seen[category].get(path) != sha]
        if changed or set(seen[category]) != set(baseline[category]):
            raise ValueError(f"Phase 3 {category} changed from accepted 0200 snapshot: "
                             f"{changed}")
    if len(seen["dsl_contracts"]) != 35:
        raise ValueError("Expected all 35 original DSL requires/expects")

    from run_laws import CHECKERS, inspect_manifest
    if tuple(CHECKERS) != ("Lean paranoid", "lean4lean", "nanoda", "con-leche",
                           "con-ron", "Lean default"):
        raise ValueError("Six checker list changed")
    if len(inspect_manifest()) != 49:
        raise ValueError("49-group required inventory drift")


def main() -> int:
    try:
        check()
    except (OSError, ValueError, KeyError, RuntimeError) as error:
        print(f"PHASE 3 SOURCE FREEZE FAILED: {error}", file=sys.stderr)
        return 1
    print("Phase 3 source freeze: original 35 contract fragments, 49 groups, "
          "six checker names and protected runtime/policy sources unchanged. SOURCE ONLY, "
          "not a proof or release pass.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
