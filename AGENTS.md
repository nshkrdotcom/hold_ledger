# Working with Hold Ledger

Read README.md and the relevant guides before changing behavior.

## Repository map

- `lib/hold_ledger/ledger.ex`: pure authorization-hold state machine.
- `lib/hold_ledger/spec.ex`: independently implemented behavioral specification.
- `lib/hold_ledger/`: journal, server, effect executor and processor simulator.
- `test/`: examples, property tests, runtime faults and formal laws.
- `verification/laws.json`: current law catalog; `baseline.json`: prior proof provenance.
- `scripts/`: local proof-tool setup, proof checking, mutation examples and demo.
- `guides/`: user documentation included in HexDocs and the source package.

## Behavior and proof constraints

Keep Ledger and Spec independent: neither may call the other. Preserve the
specification in `guides/specification.md`; do not change both implementations
just to make a failing test pass. The pure core uses fixed tuples, proper lists,
integers, atoms, guards, direct calls and named recursion. Keep I/O, clocks and
processes in the runtime layer.

An uncertain hold still consumes capacity. Retries reuse identity and amount.
Transport acknowledgments do not authorize payments. Journal inputs must sync
before state changes or effects. Processor deduplication and storage durability
are external assumptions, not consequences of the pure proofs.

Do not narrow a law's preconditions to obtain a pass or add proof admissions.
All cataloged groups are supported; do not silently exclude obligations.
A proof timeout or failure is not a concrete bug; reproduce a counterexample
before claiming one. Report ordinary tests, formal checks and external
assumptions separately.

## Commands

Use the pinned Elixir/OTP pair in `.tool-versions`. Python/uv only support local
proof tooling; they are not application runtime dependencies. Lean provisioning
is repository-local and checksum-verified. Do not alter global tools or host
security settings to work around a failed check.

```sh
uv sync --locked
uv run --locked python scripts/onboard.py --provision
uv run --locked python scripts/local_run.py mix deps.get
uv run --locked python scripts/local_run.py mix format --check-formatted
uv run --locked python scripts/local_run.py mix compile --warnings-as-errors
uv run --locked python scripts/local_run.py mix test --exclude laws
uv run --locked python -m unittest discover -s tooling_tests -v
mix docs --warnings-as-errors
mix hex.build
```

The zero-argument Bash entry points are `scripts/check_quick.sh`,
`check_full.sh`, `check_mutants.sh`, `check_web.sh` and `check_all.sh` (all under
`scripts/`). They share `--quiet` and `--jobs N`; see `guides/testing.md#check-helpers`
for exact scope, source snapshots and evidence paths. Prefer these for complete
local runs; use the commands above for focused work.

Run checks appropriate to the change. Formal verification and native mutation
runs are expensive; run them when requested or when needed to validate changes
to a law or core behavior, not for documentation-only changes. Commands are in
`guides/verification.md` and `guides/testing.md`. Keep generated logs, exports,
dependencies, toolchains and archives ignored. Use synthetic fixtures only.

When adding a guide, include it in `mix.exs` documentation extras and verify
that it appears in the Hex package. Keep README focused on using the project.
Do not introduce phase logs, handoffs, delivery checklists or generated reports
into user documentation. Do not use subagents without explicit authorization.

## Changes

Preserve existing claims, statements, domains, Spec independence, all required
groups and theorem anchors, six checker configurations and permitted axioms.
Keep Ledger's policy traces and rerun affected traces for behavior changes.
A failed proof or timeout is not a counterexample; replay an actual failing
input before claiming a semantic defect. Do not change a claim to hide failure.
Before adding a law, state its policy source, requires/expects, domain and a
wrong-output challenge. Keep generated logs and exports ignored. Report actual
commands and outcomes concisely; distinguish tests, proofs and external
processor/storage assumptions. Work on local main, commit regularly, and do
not push or create branches. Use automatic CPU/memory-bounded parallelism.
