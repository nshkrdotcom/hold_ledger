# Testing

A passing proof answers a universal question about a stated model. Tests answer different questions: does this example behave as required, does a fault path recover safely, and does a deliberately broken implementation get caught? Hold Ledger uses all of these checks because none replaces the others.

Use the setup in [Getting started](getting-started.md), then run:

```sh
mix format --check-formatted
mix compile --warnings-as-errors
mix test
mix credo --strict
mix dialyzer
uv run --locked python -m unittest discover -s tooling_tests -v
```

The ordinary suite covers deterministic transitions, malformed inputs, a worked
trace, independent spec comparisons, precondition witnesses and journal/runtime
faults. Ledger and composite StreamData properties use 10,000 generated examples; the attempt interleaving property has its own bounded configuration. The coverage helper reports candidate eligibility and discards.
Plain `mix test` excludes the expensive `:laws` tag by default; `mix test --only laws` explicitly selects proof attempts. These modules invoke Lean verification rather than cheap property tests. Formal groups have separate runs
described in [Verification](verification.md). Multiple groups share one cold
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

## Deliberate mutations

A mutation is an intentionally wrong copy of source code. The exercise asks whether the stated checks distinguish that wrong behavior from the agreed policy. Ten examples under `mutants/` break terminal-key replay, timeout accounting,
retry identity, exact-fit admission, positive admission, transport-ack handling, required void effects, decline accounting, restart conversion and premature void release.
Each includes a patch and a concrete assertion against the correct behavior.

Check that all patches apply in isolated copies, without native execution:

```sh
uv run --locked python scripts/run_mutants.py
```

The optional native experiment first verifies the targeted baseline laws, then
runs concrete assertions, ordinary tests and targeted formal attempts on copies:

```sh
uv run --locked python scripts/run_mutants.py --execute --report tmp/mutants.json
```

A complete matching cold acceptance report can supply the baseline without
repeating the same checks:

```sh
uv run --locked python scripts/run_mutants.py --execute \
  --baseline-report tmp/verification/checked.json --report tmp/mutants.json
```

The runner requires the entire source manifest to match and rechecks the stored
export hash/size, six checker acknowledgments and axiom audit before reuse.
This is expensive and is not part of routine basic checks. A planted mutation
is a detection experiment, not a newly discovered application bug. A failed
formal attempt alone is not a counterexample. The live reducer and Spec are
checked unchanged by the runner.

## Documentation and package

Build HexDocs to check that the guides render, and build the Hex archive to check packaging. These commands do not execute tutorial code blocks. Run the examples under `tmp/` with the commands in each guide when changing them; CI does not execute those examples.

```sh
mix docs --warnings-as-errors
mix hex.build
```

All `guides/*.md` are included in HexDocs and the Hex source archive. Package
building is local; it does not publish anything. Source-checkout tests and proof
scripts are available in Git. CI runs ordinary checks, guide generation and
package building; an always-running formal gate requires full proof/export checks for proof-relevant changes. Native mutation experiments remain explicit manual options.

## Runtime lifecycle properties

The attempt lifecycle has independent transition assertions and StreamData interleaving properties. Controlled processor fixtures synchronize worker entry/replies through messages, including worker death, lookup exceptions, blocked calls and Server death with surviving nolink tasks. A tooling guard inspects effective ExUnit tags and rejects an outbox feature with a missing or skipped forged-completion regression. These tests are separate from the ledger proof groups.

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
a small deterministic subset plus golden literal vectors. Encoder unit tests
check exact types, float bits, existing atoms, malformed tags and nesting.
Compiled comparison and kernel checking are distinct evidence, neither universal
translator correctness. Unexpected failures and warning diagnostics fail the run.
Samples include generated Ledger/Spec inputs and deterministic lifecycle,
composite, environment and coupled-exposure traces. Those traces exercise
deadline/shutdown/retirement, duplicate completion, void-before-authorize fencing
and exposure validity. Selected valid non-reachable states supplement reachable
histories. The report lists comparison counts by module and function.

The codec is independently implemented in `verification/DifferentialCodec.lean`.
Cross-engine golden vectors exercise encode and decode in both directions.
The harness retains every encoded case and source hashes. On a semantic mismatch,
a bounded shrinker accepts only candidates that reproduce the evaluator mismatch;
the minimized case and its identity remain in `tmp/differential/mismatch.json`.
Translation and evaluator failures cannot become shrink successes. The CI campaign is
bounded; use `--samples 1000` for a larger deterministic run.

For a broader, finite syntax-aware arithmetic/comparison campaign:

```sh
uv run --locked python scripts/mutation_campaign.py --formal-budget 1
```

The generated operator universe and per-candidate logs stay under ignored
`tmp/mutation-campaign/`. Correct-source controls run first. Each candidate runs
ordinary examples and executable properties. Only unresolved ordinary survivors
consume the targeted-proof budget. Targeted acceptance is not full-catalog
survival; tool failures and budget-limited candidates remain separately classified.
The curated ten mutation experiment remains a separate native check.

Kernel codec coverage is deliberately recorded separately: atom encode/decode and
literal vectors are kernel-checked. The pinned decimal parser did not reduce in
the kernel pilot; integer/float parsing comparisons use compiled Lean execution.
That limitation is recorded in the differential report, not counted as a passing
numeric-parser kernel proof.

To understand how a maintained law is written, return to the [crash course](formal_verification_crash_course.md#read-a-ledger-law). To claim full proof acceptance, use the exact source, exports and checker requirements in [Verification](verification.md).
