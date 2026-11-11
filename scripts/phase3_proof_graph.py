#!/usr/bin/env python3
"""Reproducible 0300-02 shared-proof consumer graph (source audit, NOT proof evidence).

Fails closed for missing native roots, import cycles, orphan modules or a changed
L1 postlude migration. This supplements, never replaces, run_laws.py inspection.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LIB = ROOT / "test/support/lean"
FILE = ROOT / "verification/research/phase3_proof_graph.json"
IMPORT = re.compile(r"^public import (\S+)", re.M)


def analyze() -> dict:
    mapping = json.loads((LIB / "library.json").read_text(encoding="utf-8"))
    entries = json.loads((ROOT / "verification/laws.json").read_text(encoding="utf-8"))["laws"]
    native = [item for item in entries if item.get("kind") == "lean"]
    law_groups = [item for item in entries if item.get("kind") != "lean"]
    if len(mapping) != 35 or len(law_groups) != 35 or len(native) != 14:
        raise ValueError("Expected 35 DSL and 14 native groups; audit halted")
    if {i["slug"] for i in law_groups} != set(mapping):
        raise ValueError("DSL group / library.json identities differ")
    anchors = [x for item in native for x in item["theorems"]]
    if len(anchors) != 21 or len(set(anchors)) != 21:
        raise ValueError("Native qualified theorem-anchor identity drift")

    sources = {p.stem: p for p in sorted(LIB.glob("*.lean"))}
    if len(sources) != 39:
        raise ValueError("The original 39 shared Lean modules must be retained")
    dependents: dict[str, list[str]] = defaultdict(list)
    graph: dict[str, list[str]] = {}
    for name, path in sources.items():
        deps = [x.split(".")[-1] for x in IMPORT.findall(path.read_text(encoding="utf-8"))
                if x.startswith("HoldLedgerProof.")]
        missing = set(deps) - sources.keys()
        if missing:
            raise ValueError(f"{name}: missing dependencies: {sorted(missing)}")
        graph[name] = deps
        for dep in deps:
            dependents[dep].append(name)

    visited: set[str] = set()
    active: set[str] = set()
    def visit(name: str) -> None:
        if name in active:
            raise ValueError(f"Cycle in shared Lean imports at {name}")
        if name not in visited:
            active.add(name)
            for child in graph[name]:
                visit(child)
            active.remove(name)
            visited.add(name)

    roots = set(mapping.values()) | {item["module"].rsplit(".", 1)[-1] for item in native}
    if roots - sources.keys():
        raise ValueError(f"Unknown native/DSL roots: {sorted(roots - sources.keys())}")
    for root in sorted(roots):
        visit(root)
    if visited != sources.keys():
        raise ValueError(f"Orphan sources: {sorted(sources.keys() - visited)}")

    old_l1 = "Elixir.HoldLedger.ProofContracts.«l1_find/2»"
    new_l1 = "HoldLedgerProof.Postludes.L1Find.l1_contract"
    consumers = [str(p.relative_to(ROOT)) for p in sorted([
        *LIB.glob("*.lean"), *(ROOT / "test/laws").glob("*_test.exs")
    ]) if old_l1 in p.read_text(encoding="utf-8")]
    migrated_consumers = [str(p.relative_to(ROOT)) for p in sorted(
        (ROOT / "test/laws").glob("*_test.exs")) if new_l1 in p.read_text(encoding="utf-8")]
    if consumers != [] or migrated_consumers != ["test/laws/l1_find_test.exs"]:
        raise ValueError("L1 local postlude migration is missing or still has old consumers")
    if "theorem «l1_find/2»" in sources["Lookup"].read_text(encoding="utf-8"):
        raise ValueError("Old L1 shared theorem remains after migration")
    if not all(t in (ROOT / "test/laws/l1_find_test.exs").read_text(encoding="utf-8")
               for t in ("theorem l1_contract", "postlude ~LEAN")):
        raise ValueError("Migrated group-local L1 theorem missing")
    # A genuinely non-anchored theorem is moved; Lookup remains in use by A4.
    if len([k for k in mapping if mapping[k] == "Lookup"]) != 3:
        raise ValueError("Lookup library mapping changed during migration")

    modules = [{
        "module": f"HoldLedgerProof.{name}",
        "path": str(sources[name].relative_to(ROOT)),
        "sha256": hashlib.sha256(sources[name].read_bytes()).hexdigest(),
        "imports": [f"HoldLedgerProof.{x}" for x in graph[name]],
        "used_by_modules": [f"HoldLedgerProof.{x}" for x in sorted(dependents[name])],
        "dsl_groups": sorted(k for k, v in mapping.items() if v == name),
        "native_groups": sorted(item["slug"] for item in native
                                if item["module"] == f"HoldLedgerProof.{name}"),
    } for name in sorted(sources)]
    return {
        "scope": "source-only graph; not a kernel proof or independent checker result",
        "counts": {"dsl_groups": len(law_groups), "native_groups": len(native),
                   "total_groups": len(entries), "native_anchors": len(anchors),
                   "shared_lean_modules": len(sources)},
        "native_anchors": anchors,
        "migration": {
            "from": "Elixir.HoldLedger.ProofContracts.«l1_find/2» in Lookup.lean",
            "to": new_l1 + " in test/laws/l1_find_test.exs",
            "remaining_old_name_consumers": consumers,
            "new_name_consumers": migrated_consumers,
            "retained_files": ["test/support/lean/Lookup.lean"],
            "deletions": [],
        },
        "modules": modules,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write", action="store_true", help="write checked-in graph snapshot")
    parser.add_argument("--check", action="store_true", help="fail if snapshot is stale")
    args = parser.parse_args()
    current = json.dumps(analyze(), indent=2, ensure_ascii=False) + "\n"
    if args.write:
        FILE.parent.mkdir(parents=True, exist_ok=True)
        FILE.write_text(current, encoding="utf-8")
    if args.check and (not FILE.exists() or FILE.read_text(encoding="utf-8") != current):
        raise ValueError("Phase 3 proof graph snapshot is stale; rerun --write and review")
    print("Phase 3 graph: 39 modules, 35 DSL + 14 native groups, 21 native anchors; "
          "one L1 theorem moved, zero file deletions. Source check only.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
