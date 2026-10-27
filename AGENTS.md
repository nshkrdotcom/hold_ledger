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

Run checks appropriate to the change. Formal verification and native mutation
runs are expensive; run them when requested or when needed to validate changes
to a law or core behavior, not for documentation-only changes. Commands are in
`guides/verification.md` and `guides/testing.md`. Keep generated logs, exports,
dependencies, toolchains and archives ignored. Use synthetic fixtures only.

When adding a guide, include it in `mix.exs` documentation extras and verify
that it appears in the Hex package. Keep README focused on using the project.
Do not introduce phase logs, handoffs, delivery checklists or generated reports
into user documentation. Do not use subagents without explicit authorization.

## Review contract for agent changes

Read `guides/human_review.md` before classifying proof work. Reports orient the
reviewer; the actual diff determines its tier. Any changed Lean declaration,
theorem signature, import, option, syntax or elaborator needs Tier 1 review;
only confirmed proof-body-only changes qualify for Tier 3.

Report the claim delta, Tier 1 files and reasons, commands/results, and unresolved
work in the change summary. Flag changes to assumptions, domains, Spec/models,
inventories, foundations, gates or skips; do not silently weaken guarantees to repair proofs.
Use the report fields in `guides/human_review.md`, including
`Decision needed (human): none` when existing authority covers the work. State the
question, options, consequences and work that can continue. Keep failed checks
and timeouts under `Unresolved`, with an owner and next action.
Human policy approval already given for a change remains valid within its scope.

Commit independently chosen policy traces as tests. Re-run those traces for
Ledger changes. For proof failures, execute the same claim's witness/property,
replay any counterexample, and distinguish implementation errors from proposed
claim corrections. No counterexample leaves the claim unresolved. Report timeout
changes with justification and fresh evidence; a timeout never counts as success.

Before authoring a new law, cite the policy source and propose the actual
`requires`/`expects`, effective domain and a wrong-output challenge. Stop for
unapproved semantic changes. Report actual proof commands and evidence scope.
Review Studio lives in `apps/review_web/`, a separate Mix project; preserve the
root package and proof paths. Never infer checked status from catalog support.
