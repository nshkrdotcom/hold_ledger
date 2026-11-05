#!/usr/bin/env bash
set -euo pipefail

cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
if (( $# )); then
  echo "Usage: $0 (no arguments)" >&2
  exit 2
fi

uv sync --locked
uv run --locked python scripts/onboard.py --profile runtime --provision
uv run --locked python scripts/local_run.py mix deps.get

uv run --locked python scripts/local_run.py mix format --check-formatted
uv run --locked python scripts/local_run.py mix compile --warnings-as-errors
uv run --locked python scripts/local_run.py mix test --exclude laws
uv run --locked python -m unittest discover -s tooling_tests -v
