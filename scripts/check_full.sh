#!/usr/bin/env bash
set -euo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
if (( $# )); then
  echo "Usage: $0 (no arguments)" >&2
  exit 2
fi

uv sync --locked
uv run --locked python scripts/onboard.py --profile proofs --provision
uv run --locked python scripts/local_run.py mix deps.get

uv run --locked python scripts/run_laws.py --supported-only --stage full \
  --report tmp/verification/checked.json
