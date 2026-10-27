# Troubleshooting

Start with the symptom you actually see; a missing native tool, a failing proof, and an unresolved payment outcome require different responses. Do not edit an agreed law, remove an uncertain hold, or disable a checker to get a green result. If you're just setting up the project, begin with [Getting started](getting-started.md).

## Runtime or toolchain mismatch

```sh
uv run --locked python scripts/onboard.py --profile runtime
uv run --locked python scripts/onboard.py --profile proofs
uv run --locked python scripts/local_run.py python scripts/doctor.py
```

Select the pinned Elixir/OTP pair listed in [Getting started](getting-started.md#environment) before onboarding. A matching
OTP major version is not enough. Provision pinned Lean locally with
`uv run --locked python scripts/onboard.py --provision`. A checksum failure must
be resolved by obtaining the pinned release, not by bypassing verification.
An interrupted extraction produces an explicit incomplete-installation error;
inspect only the named local tool directory before retrying.

A fresh `mix test` compiles the test-only Lynx dependency, whose build invokes
Lake. If that fails with `System.cmd("lake", ...)` and `:enoent`, activate the
repository-local toolchain as shown in [Getting started](getting-started.md).

## A proof fails or does not start

A failed proof attempt is not automatically a counterexample. First check whether Lean ran, what it reported, and whether the contract has an independently justified witness.

For explicit formal verification, use `scripts/local_run.py` so Lean/Lake resolve to `.local/`. The full independent
checker needs `bwrap` and a host that permits its sandbox namespaces. A missing
sandbox is a failed prerequisite; do not disable isolation to report acceptance.

A proof may fail because of an incorrect law, an incomplete proof, translation
changes, exhausted resources or a missing tool. Inspect the log under
`tmp/verification/` and obtain a concrete Elixir counterexample before calling
it an application bug. To require every cataloged group, run:

```sh
uv run --locked python scripts/run_laws.py --supported-only --stage full \
  --report tmp/verification/checked.json
```

Missing, skipped or failed proof results cannot count as acceptance.

Nanoda is one of the independent proof checkers used in the full verification stage. If it reports a worker-stack overflow, the runner retains the failed bundled result and retries with the same pinned binary/export in a sandbox with one
thread and a 256 MiB process stack. It only counts acceptance if the retry
succeeds and the allowed-axiom audit passes. It never changes host policy.

## Journal will not open

Check path permissions, an already-owned path and the persisted capacity
configuration. A truncated or invalid chained record fails replay. Preserve the
journal for inspection; deleting it discards request identities and unresolved
holds. Use `Journal.inspect_file/1` for read-only diagnostics. `Journal.recover_tail/2` creates a separate verified-prefix file only for an incomplete final frame under the documented interrupted-append assumption. It never repairs arbitrary corruption.

## An operation stays unknown

A lost response cannot establish the external outcome. Use reconciliation when
the processor provides a trustworthy lookup. Unavailable lookup does not release
capacity. Repeated retries require receiver deduplication and may be unsafe
against a processor that lacks it. See [Runtime and recovery](runtime.md).

## Local disk use

`.local/` holds downloaded proof toolchains, `deps/` dependencies, `_build/`
compiled output, `.venv/` Python helpers, and `tmp/` proof logs/exports and
mutation scratch copies. `doc/` and `hold_ledger-*.tar` are generated docs/package
outputs. They are ignored and can be regenerated. Removing `.local/` requires
reprovisioning; remove only known disposable paths, never an active journal.

## A hold stays voiding or an adapter is rejected

Voiding retains capacity until positive terminal confirmation. Inspect the pending void record and its durable attempt budget with
`Server.inspect_work(ledger, :voids, 0, 100)`. After the automatic budget is
exhausted, an authorized operator can use `Server.redrive_void(ledger, key)` to
reset it and retry. Preserve the journal while investigating. Retries do not
change the [capacity-retention rule](specification.md#pending-voids-and-composite-recovery).

A `:missing_terminal_attestation` startup error means the adapter declaration is
absent or unsupported. Implement the processor contract only if the integrator
can attest to [permanent fencing](processors.md#terminal-attestation-and-retention), including a void received before authorization.
A declaration passing validation is not evidence that the remote service is honest.

[Runtime and recovery](runtime.md#lookup-and-inspection) explains the inspection and reconciliation calls.
