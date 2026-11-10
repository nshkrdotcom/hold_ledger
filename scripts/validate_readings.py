#!/usr/bin/env python3
"""Fail-closed freshness/byte-integrity check for the three focused readings.

This is NOT formal proof verification. It inspects the producer's real index
and artifacts after the producer has executed in this exact source checkout.
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
INDEX = 'tmp/verification/claim-reading/index.json'
CLAIMS = frozenset(('po_a2', 'po_b1_void', 'po_exposure_retain'))
SCOPE = 'focused_original_lean_elaboration_not_full_acceptance'
HEX64 = re.compile(r'[0-9a-f]{64}\Z')


def source_paths(root: Path) -> set[str]:
    """Mirror the committed Elixir producer's source selection exactly."""
    names = set()
    for folder, glob in (('lib', '*.ex'), ('test/laws', '*.exs'),
                         ('scripts', '*.py'), ('verification', '*.json')):
        base = root / folder
        iterator = base.rglob(glob) if folder == 'lib' else base.glob(glob)
        names.update(str(file.relative_to(root)) for file in iterator if file.is_file())
    for suffix in ('.ex', '.lean', '.json'):
        names.update(str(file.relative_to(root)) for file in
                     (root / 'test/support').rglob('*' + suffix) if file.is_file())
    names.update(('mix.exs', 'mix.lock', 'uv.lock', '.tool-versions', 'lean-toolchain',
                  'apps/review_web/scripts/produce_claim_readings.exs'))
    return names


def safe_file(root: Path, relative: str) -> Path | None:
    if not isinstance(relative, str) or not relative or relative.startswith('/'):
        return None
    parts = Path(relative).parts
    if '..' in parts or '.' in parts:
        return None
    file = root / relative
    if not file.resolve().is_relative_to(root.resolve()) or not file.is_file():
        return None
    return file


def sha(file: Path) -> str:
    return hashlib.sha256(file.read_bytes()).hexdigest()


def validate(root: Path) -> list[str]:
    errors = []
    index_file = safe_file(root, INDEX)
    if index_file is None or index_file.stat().st_size > 2_000_000:
        return ['focused reading index missing, unsafe, or oversized']
    try:
        index = json.loads(index_file.read_text(encoding='utf8'))
    except (ValueError, OSError, UnicodeError) as exc:
        return [f'invalid focused reading JSON: {exc}']
    if not isinstance(index, dict) or index.get('schema_version') != 1 or index.get('scope') != SCOPE:
        return ['focused reading index schema/scope mismatch']
    try:
        generated = dt.datetime.fromisoformat(index['generated_at'].replace('Z', '+00:00'))
        if generated.tzinfo is None:
            errors.append('focused index generated_at lacks UTC offset')
    except (TypeError, ValueError, KeyError, AttributeError):
        errors.append('focused index generated_at missing/invalid')
    sources = index.get('sources')
    expected = source_paths(root)
    if not isinstance(sources, dict) or set(sources) != expected:
        errors.append('focused source manifest is incomplete or includes unexpected paths')
    if isinstance(sources, dict):
        for name, digest in sources.items():
            file = safe_file(root, name)
            if not isinstance(digest, str) or not HEX64.fullmatch(digest) or file is None or sha(file) != digest:
                errors.append(f'focused source missing/changed: {name}')
    claims = index.get('claims')
    if not isinstance(claims, dict) or set(claims) != CLAIMS:
        errors.append('focused index does not contain exactly the three required claims')
        return errors
    for slug in sorted(CLAIMS):
        row = claims[slug]
        if not isinstance(row, dict) or row.get('status') != 'elaborated' or row.get('full_acceptance') is not False:
            errors.append(f'{slug}: not a completed, explicitly focused reading')
            continue
        reports = row.get('reports')
        if (not isinstance(reports, list) or not reports or
                any(not isinstance(r, dict) or r.get('status') != 'ok' or r.get('cached') is not False
                    for r in reports)):
            errors.append(f'{slug}: missing/unclean/possibly cached Lynx reports')
        artifacts = row.get('artifacts')
        if not isinstance(artifacts, list) or not artifacts:
            errors.append(f'{slug}: missing Lean artifacts')
            continue
        paths = set()
        for artifact in artifacts:
            if not isinstance(artifact, dict):
                errors.append(f'{slug}: malformed artifact')
                continue
            name = artifact.get('path')
            parts = Path(name).parts if isinstance(name, str) else ()
            if (len(parts) < 6 or parts[:3] != ('tmp', 'verification', 'claim-reading')
                    or not HEX64.fullmatch(parts[3]) or parts[4] != slug
                    or parts[-1].endswith('.lean') is False or name in paths):
                errors.append(f'{slug}: invalid/duplicate artifact path: {name}')
                continue
            paths.add(name)
            file = safe_file(root, name)
            digest = artifact.get('sha256')
            size = artifact.get('bytes')
            if (file is None or not isinstance(digest, str) or not HEX64.fullmatch(digest)
                    or type(size) is not int or size <= 0 or
                    file.stat().st_size != size or sha(file) != digest):
                errors.append(f'{slug}: Lean artifact missing/changed: {name}')
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', type=Path, default=ROOT)
    args = parser.parse_args()
    errors = validate(args.repo.resolve())
    print(json.dumps({'kind': 'FOCUSED_READINGS_NOT_FULL_PROOF_ACCEPTANCE',
                      'status': 'PASS' if not errors else 'BLOCKED', 'errors': errors}, indent=2))
    return 0 if not errors else 1


if __name__ == '__main__':
    raise SystemExit(main())
