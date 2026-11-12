# Testing

A passing proof answers a universal question about a stated model. Tests answer different questions: does this example behave as required, does a fault path recover safely, and does a deliberately broken implementation get caught? Hold Ledger uses all of these checks because none replaces the others.

## Check helpers

All five Bash helpers work with no arguments and include locked dependency and
local tool setup. Run them from the repository root or invoke them by path.

| Helper | Checks |
|---|---|
| `./scripts/check_quick.sh` | Root formatting, compilation and ordinary tests/properties with warnings as errors; strict Credo; Dialyzer; Python tooling tests; catalog registration and static mutation patch checks. No formal proof attempts. |
| `./scripts/check_full.sh` | Every required law group, uncached proof checking, fresh exports, all six independent checker configurations and the axiom audit. Does not repeat quick checks. |
| `./scripts/check_mutants.sh` | A fresh targeted formal baseline, then all ten isolated mutants. Each runs its correct-source witness, mutated witness, ordinary suite and mapped formal attempt. |
| `./scripts/check_web.sh` | Phoenix compilation, formatting, strict Credo, Dialyzer and isolated ExUnit shards, documentation, asset setup/build, Python content checks and all three managed browser profiles. |
| `./scripts/check_all.sh` | Everything above, plus bounded BEAM/Lean differential checks, executable tutorials, demo, root documentation/package builds and original claim-reading production. Runs full formal acceptance once and reuses its validated baseline for mutants. |

The master starts independent group orchestrators concurrently. Each executable
command stage acquires CPU, estimated memory, a worker slot and exclusive build
ownership from one run-local coordinator. Nested law, mutation, differential
and tutorial commands join that coordinator rather than reserving a second
copy of the parent budget. Mutants become eligible immediately after the full
baseline passes. Command-stage completion releases the reservation; a group
waiting for its next stage does not retain CPU or memory tokens.

Automatic selection respects affinity, effective cpusets, cgroup quotas and
inherited allocations. Discovery reports fractional CPU capacity, available
RAM, PID headroom, disk space and pressure. The scheduler initially reserves
the larger of 2 GiB or 10% of available RAM. Memory reservations are estimates,
not hard OS limits. An oversized single command can run alone and is labeled
in the lease log. Group orchestration slots and executable command slots are
distinct: a lightweight launcher delegates its command reservations.

Each stage receives a CPU allocation bounded by its request and the run's
current parallelism. As groups finish, subsequent stages can take wider
allocations. Generated BEAM flags follow the granted width; explicit operator
flags remain intact. The repository's maintained Lynx extension replaces the serial batch;
module elaboration uses dependency-ready isolated Lean processes with transitive
run-local imports and one final combined export. All six
checker requirements and cold proof acceptance gates remain.

Every helper accepts the same options:

```sh
./scripts/check_all.sh              # Automatic workers; live output and a log
./scripts/check_all.sh --quiet      # Log output; print log path and final status
./scripts/check_all.sh --jobs 1     # Serial execution
./scripts/check_all.sh --jobs 6     # Worker ceiling; CPU/memory limits still apply
./scripts/check_all.sh --help
```

### Source copies, logs and reports

The runner holds its checkout lock before synchronizing the Python environment
and preparing dependencies. Setup finishes before workers start. The runner snapshots the current source,
including tracked edits and nonignored untracked files. Workers have independent dependency copies, builds, caches,
exports, reports and assets. Installed tools and the prepared Python environment
are shared. Temporary copies use reflinks when supported, with ordinary copies
as the fallback; writable files are never hardlinked. `tmp/` is already ignored.
You can edit the main checkout after the snapshot without changing worker inputs.

The helper prints a unique combined stdout/stderr log under
`/tmp/hold-ledger-check-<mode>.*.log`. Follow the printed file with `tail -f`.
Each command and its exit status are logged; silent commands emit 15-second
heartbeats. Concurrent terminal lines carry their group name.

The log identifies `tmp/check-runs/<run>/`, containing:

- `status.json`: detected resources, worker ceiling and each group's result.
- `leases.jsonl`: queued, granted, started and released command reservations, including CPU/memory allocations and oversized singleton labels.
- `logs/<group>.log`: command output for that group.
- `snapshot/`: the source used by every worker.
- `workers/<group>/`: isolated project and detailed generated evidence.

For full or master runs, formal acceptance is recorded in
`workers/full/tmp/verification/checked.json`; it requires `release_complete: true`.
In a master run, the mutation report is
`workers/full/tmp/verification/mutants.json`. Standalone mutation runs use
`workers/mutants/tmp/verification/mutants.json`. Other reports retain their usual
paths within their worker project. These locations retain execution results
without overwriting an earlier run. A passing orchestration status does not
replace reading the formal report.

A failed command stops its group; the master cancels remaining work and exits
nonzero. Ctrl-C or termination stops child processes, including nested Lean
sessions. Cancelled or incomplete checks cannot count as acceptance. Run one
helper at a time per checkout. Workspaces and reports are retained for inspection;
remove a completed run's printed directory when you no longer need it.

### Commands inside the helpers

`scripts/check_suite.py` defines the command groups, `check_resources.py` detects
machine capacity, `check_scheduler.py` owns resource reservations, and
`check_runtime.py` provides source isolation and child cleanup. The Bash wrappers share
`check_common.sh` for CLI options and logging. Setup uses `uv sync --locked`,
`onboard.py --provision`, locked Mix dependencies and `verify_pins.py`.

The quick group runs `mix format --check-formatted`,
`mix compile --warnings-as-errors`, `mix test --exclude laws --warnings-as-errors`,
`mix credo --strict`, `mix dialyzer`, Python `unittest` discovery in `tooling_tests`,
`run_laws.py --supported-only --inspect-only` and static `run_mutants.py`.
The full group runs `run_laws.py --supported-only --stage full`.
The mutation group runs `run_mutants.py --execute --jobs N`; the master adds
`--baseline-report` pointing to the full group's report. Reuse checks
the required laws, checker acknowledgments and permitted axioms.

The master's other groups run `run_differential.py --samples 100 --timeout 300`,
`check_tutorials.py`, `mix run scripts/demo.exs`, `mix docs --warnings-as-errors`,
`mix hex.build`, and the claim-reading producer under `MIX_ENV=test`.
The web group runs `mix precommit`, `mix docs --warnings-as-errors`,
`mix assets.setup`, `mix assets.build`, and Python `unittest` discovery in
`apps/review_web/scripts`. All Mix commands use `scripts/local_run.py`.

The ordinary suite covers deterministic transitions, malformed inputs, a worked
trace, independent spec comparisons, precondition witnesses and journal/runtime
faults. Ledger and composite StreamData properties use 10,000 generated examples. The attempt interleaving property runs 1,000 histories of at most 100 events each. The coverage helper reports candidate eligibility and discards.
The root `test/claim_source_parity_test.exs` verifies extraction parity to
`HoldLedger.ProofCase.law_declarations/1` for all registered DSL laws. It runs
in the root environment where Lynx test support is present, not in the
Phoenix runtime. In the separate `apps/review_web` project run `mix test`
and `mix precommit` to verify the Milestone A source compiler, event-to-formal
provenance, P01–P08 matrix, drift checks and strict codec. A static expected
matrix does not count as an executed test.

Plain `mix test` excludes the expensive `:laws` tag by default; `mix test --only laws` explicitly selects proof attempts. These modules invoke Lean verification rather than cheap property tests. Formal groups have separate runs
described in [Verification](verification.md). Multiple groups share one uncached
verification request, while ordinary tests exercise the proof adapter’s
dependency ordering, cache invalidation and fail-closed result checks.

Credo runs its strict default checks on application code, tests, and scripts.
Dialyxir runs Dialyzer on the application and builds its PLTs under ignored
`_build/`; the first run takes longer. Neither check uses warning suppressions
or ignore files. These static checks are separate from tests and formal proofs.

## Targeted runtime tests

These checks are for the OTP/journal boundary, which pure Lean proofs do not establish. They are useful after changing task handling, persistence or recovery.

```sh
mix test \
  test/hold_ledger_journal_test.exs test/hold_ledger_runtime_test.exs --exclude laws
mix run scripts/demo.exs
```

Faults include injected append/sync/disk-full failures, actual truncated journal
files, process crashes, lost replies, repeated callbacks and concurrent inputs.
`allow_faults: true` enables the server's test-only injected-failure interface.
These tests do not model physical power loss or prove the storage hardware.

### Runtime lifecycle properties

The attempt lifecycle has independent transition assertions and StreamData interleaving properties. Controlled processor fixtures synchronize worker entry/replies through messages, including worker death, lookup exceptions, blocked calls and Server death with surviving nolink tasks. A tooling guard inspects effective ExUnit tags and rejects an outbox feature with a missing or skipped forged-completion regression. These tests are separate from the ledger proof groups.

## Deliberate mutations

A mutation is an intentionally wrong copy of source code. The exercise asks whether the stated checks distinguish that wrong behavior from the agreed policy. Each example under `mutants/` includes a patch and a concrete assertion against the correct behavior.

| Mutant | What it breaks | Targeted law group |
|---|---|---|
| M1 — terminal reuse | Reuses a released key instead of reporting a duplicate | `po_a4_duplicate` |
| M2 — timeout release | Frees capacity while an authorization remains unknown | `po_b1_timeout` |
| M3 — retry identity | Changes the identity of a retried authorization | `po_b3` |
| M4 — exact fit | Rejects a request that exactly fits the available capacity | `po_a2` |
| M5 — always reject | Refuses otherwise eligible requests | `po_a2` |
| M6 — transport acknowledgment | Treats delivery acknowledgment as approval | `po_b4` |
| M7 — missing void effect | Omits the required remote void intent | `po_b3` |
| M8 — decline accounting | Increases used amount when a decline should release it | `po_b1_processor_result` |
| M9 — restart conversion | Leaves sent entries unchanged instead of marking them unknown | `po_b7` |
| M10 — premature void release | Frees capacity before terminal void confirmation | `po_exposure_retain` |

Mutation commands stream output to the terminal and logs under
`tmp/verification/mutant-logs/`. Each command reports its start, finish and
elapsed time every 15 seconds while running, including during silent Lean checks.

These are the targets selected by `scripts/run_mutants.py`. The concrete assertions establish the planted violations; a failed proof attempt alone does not establish that a law detected the fault.

Check that all patches apply in isolated copies, without native execution:

```sh
uv run --locked python scripts/run_mutants.py
```

Run the complete native experiment with the helper:

```sh
./scripts/check_mutants.sh
```

It verifies the targeted baseline laws once, then runs as many independent
mutants as usable CPUs and the memory budget permit, up to all ten. Each mutant
still runs its assertions, ordinary suite and
formal attempt in order. Failed assertions on a deliberately broken copy are
expected evidence; an infrastructure failure is incomplete, not detection.

A complete matching uncached acceptance report can supply the baseline without
repeating the same checks:

```sh
uv run --locked python scripts/run_mutants.py --execute \
  --baseline-report tmp/verification/checked.json --report tmp/mutants.json
```

The runner requires a completed full proof run with all six checker acknowledgments
and the permitted-axiom audit before baseline reuse.
This is expensive and is not part of routine basic checks. A planted mutation
is a detection experiment, not a newly discovered application bug. A failed
formal attempt alone is not a counterexample. The live reducer and Spec are
checked unchanged by the runner.

### Generated operator mutations

To try generated changes to arithmetic and comparison operators:

```sh
uv run --locked python scripts/mutation_campaign.py --formal-budget 1
```

The generated operator changes and logs for each candidate stay under ignored
`tmp/mutation-campaign/`. Correct-source controls run first. Each candidate runs
ordinary examples and executable properties. Only candidates that pass the ordinary checks
consume the targeted-proof budget. Passing the targeted proof does not show that a mutant passes every required law. Tool failures and candidates left unchecked when the budget runs out are reported separately.
Run the ten hand-written mutants separately with `run_mutants.py`.

## Documentation and package

### Execute the tutorial examples

CI runs examples extracted from the crash course, Reading deeper proofs and Agentic verification. From a source checkout with the pinned tools, run the same check locally:

```sh
uv run --locked python scripts/check_tutorials.py
```

The runner checks the README example, standalone Lean examples, ledger witnesses, accounting and contract challenges, the capacity law and the over-capacity exercise, and selected source excerpts. It requires the exact-fit mutant to produce both a concrete ordinary failure and the documented proof diagnostic. It also checks that `omega` alone fails on the unchanged translated claim. Each command has a five-minute timeout; logs and extracted files go under `tmp/tutorial-checks/`. These development proofs do not run the full exported-checker acceptance pipeline.

### Build the guides and source package

Build HexDocs to check rendering and the Hex archive to check packaging:

```sh
mix docs --warnings-as-errors
mix hex.build
```

All `guides/*.md` are included in HexDocs and the Hex source archive. Package
building is local; it does not publish anything. Source-checkout tests and proof
scripts are available in Git. CI runs ordinary checks, guide generation and
package building; an always-running formal gate requires full proof/export checks for proof-relevant changes. Native mutation experiments remain explicit manual options.

## Synthetic runtime measurements

`mix run scripts/runtime_bench.exs`
measures request p95, recovered startup time, retained Server memory and record
count for 100 and 1,000 entries with invariant monitoring enabled. Results depend
on the host and are not durability or production latency guarantees. Streaming
replay avoids retaining the event list, while permanent key retention and the
quadratic uniqueness check still limit account size. No compaction or key pruning
is performed.

## Translation comparisons

Lynx works on compiled Core Erlang, so compiler/translation correspondence deserves its own checks. This harness compares selected actual executions with translated definitions; sampling does not prove general equivalence.

```sh
uv run --locked python scripts/run_differential.py --samples 100 --timeout 300
```

The deterministic seed is recorded in `tmp/differential/report.json`. The harness
translates actual compiled definitions and evaluates the emitted modules using
Lean's normal frontend. It compares sampled outcomes to BEAM and kernel-checks
a small deterministic subset plus golden literal vectors.

Encoder unit tests
check exact types, float bits, existing atoms, malformed tags and nesting.
Compiled comparison and kernel checking provide different evidence. Neither proves that the translator is correct for every program. Unexpected failures and warning diagnostics fail the run.

Samples include generated Ledger/Spec inputs and deterministic lifecycle,
composite, environment and coupled-exposure traces. Those traces exercise
deadline/shutdown/retirement, duplicate completion, void-before-authorize fencing
and exposure validity. Selected valid non-reachable states supplement reachable
histories. The report lists comparison counts by module and function.

The codec is independently implemented in `verification/DifferentialCodec.lean`.
Cross-engine golden vectors exercise encode and decode in both directions.
The harness retains the encoded comparison cases.

On a semantic mismatch,
the shrinker tries a limited number of smaller cases and accepts only candidates that reproduce the evaluator mismatch;
the minimized case and its identity remain in `tmp/differential/mismatch.json`.
Translation and evaluator failures cannot become shrink successes. CI uses 100 generated samples; use `--samples 1000` for a larger deterministic run.

Kernel codec coverage is deliberately recorded separately: atom encode/decode and
literal vectors are kernel-checked. The pinned decimal parser did not reduce in
the kernel pilot; integer/float parsing comparisons use compiled Lean execution.
That limitation is recorded in the differential report, not counted as a passing
numeric-parser kernel proof.

To understand how a maintained law is written, return to the [crash course](formal_verification_crash_course.md#read-a-ledger-law). To claim full proof acceptance, use the exact source, exports and checker requirements in [Verification](verification.md).

### Durable command jobs

To keep output and final status after a terminal or chat interruption, run a
command through `scripts/logged_job.py --directory tmp/jobs/<unique-name> -- <command>`.
The directory must be new. It contains `output.log` from command start and an
atomically updated `status.json` with command, PID, completion time and exit code.
Cancellation records an incomplete result and cleans up the command's process tree.

### Isolated test and evaluation workers

The Phoenix helper and `mix precommit` balance test files across independent
BEAM VMs. Each shard owns a relocated build and temp directory. Existing
application singletons, ETS tables and environment-changing tests remain
isolated without weakening their assertions. Per-file timing observations
improve subsequent balancing; exact file coverage and aggregate results are
retained under `tmp/exunit-runs/`.

Differential histories are generated once with their original seed. Independent
assertion batches execute concurrently with stable case indices and all eight
kernel pilots retained. Tutorial tasks use private builds and preserve the
expected compiler/tactic failures. Generated mutation campaigns select formal
survivors in manifest order after parallel ordinary execution.

Resource admission can backfill smaller ready work while an older task waits;
after 30 seconds the oldest task takes priority. Process-tree RSS/PID samples
increase underestimated reservations and seed conservative future estimates.
These remain scheduling estimates, not hard memory limits; shared RSS pages
may be counted more than once. Observations stay in ignored local storage.
