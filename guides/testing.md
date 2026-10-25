# Testing

Use the setup in [Getting started](getting-started.md), then run:

```sh
uv run --locked python scripts/local_run.py mix format --check-formatted
uv run --locked python scripts/local_run.py mix compile --warnings-as-errors
uv run --locked python scripts/local_run.py mix credo --strict
uv run --locked python scripts/local_run.py mix dialyzer
uv run --locked python scripts/local_run.py mix test --exclude laws --warnings-as-errors
uv run --locked python -m unittest discover -s tooling_tests -v
```

The ordinary suite covers deterministic transitions, malformed inputs, a worked
trace, independent spec comparisons, precondition witnesses and journal/runtime
faults. Twenty-two StreamData properties are configured for 10,000 eligible
examples each. The coverage helper reports candidate eligibility and discards.
All 29 formal groups are excluded from this command; they have separate runs
described in [Verification](verification.md). Multiple groups share one cold
verification request, while ordinary tests exercise the proof adapter’s
dependency ordering, cache invalidation and fail-closed result checks.

Credo runs its strict default checks on application code, tests, and scripts.
Dialyxir runs Dialyzer on the application and builds its PLTs under ignored
`_build/`; the first run takes longer. Neither check uses warning suppressions
or ignore files. These static checks are separate from tests and formal proofs.

## Targeted runtime tests

```sh
uv run --locked python scripts/local_run.py mix test \
  test/hold_ledger_journal_test.exs test/hold_ledger_runtime_test.exs --exclude laws
uv run --locked python scripts/local_run.py mix run scripts/demo.exs
```

Faults include injected append/sync/disk-full failures, actual truncated journal
files, process crashes, lost replies, repeated callbacks and concurrent inputs.
`allow_faults: true` enables the server's test-only injected-failure interface.
These tests do not model physical power loss or prove the storage hardware.

## Deliberate mutations

Nine examples under `mutants/` break terminal-key replay, timeout accounting,
retry identity, exact-fit admission, positive admission, transport-ack handling, required void effects, decline accounting and restart conversion.
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

This is expensive and is not part of routine basic checks. A planted mutation
is a detection experiment, not a newly discovered application bug. A failed
formal attempt alone is not a counterexample. The live reducer and Spec are
checked unchanged by the runner.

## Documentation and package

```sh
mix docs --warnings-as-errors
mix hex.build
```

All `guides/*.md` are included in HexDocs and the Hex source archive. Package
building is local; it does not publish anything. Source-checkout tests and proof
scripts are available in Git. CI runs ordinary checks, guide generation and
package building; an always-running formal gate requires full proof/export checks for proof-relevant changes. Native mutation experiments remain explicit manual options.

## Runtime lifecycle properties

The attempt lifecycle has independent transition assertions and StreamData interleaving properties. Controlled processor fixtures synchronize worker entry/replies through messages, including worker death, lookup exceptions, blocked calls and Server death with surviving nolink tasks. A tooling guard inspects effective ExUnit tags and rejects an outbox feature with a missing or skipped forged-completion regression. These tests are separate from the 29 ledger proof groups.

## Synthetic runtime measurements

`uv run --locked python scripts/local_run.py mix run scripts/runtime_bench.exs`
measures request p95, recovered startup time, retained Server memory and record
count for 100 and 1,000 entries with invariant monitoring enabled. Results depend
on the host and are not durability or production latency guarantees. Streaming
replay avoids retaining the event list, while permanent key retention and the
quadratic uniqueness check still limit account size. No compaction or key pruning
is performed.
