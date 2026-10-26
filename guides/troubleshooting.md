# Troubleshooting

## Runtime or toolchain mismatch

```sh
uv run --locked python scripts/onboard.py --profile runtime
uv run --locked python scripts/onboard.py --profile proofs
uv run --locked python scripts/local_run.py python scripts/doctor.py
```

Select the installed Elixir 1.20.4/OTP 29.1.2 pair before onboarding. A matching
OTP major version is not enough. Provision pinned Lean locally with
`uv run --locked python scripts/onboard.py --provision`. A checksum failure must
be resolved by obtaining the pinned release, not by bypassing verification.
An interrupted extraction produces an explicit incomplete-installation error;
inspect only the named local tool directory before retrying.

## Proofs do not run or fail

For explicit formal verification, use `scripts/local_run.py` so Lean/Lake resolve to `.local/`. The full independent
checker needs `bwrap` and a host that permits its sandbox namespaces. A missing
sandbox is a failed prerequisite; do not disable isolation to report acceptance.

A proof may fail because of an incorrect law, an incomplete proof, translation
changes, exhausted resources or a missing tool. Inspect the log under
`tmp/verification/` and obtain a concrete Elixir counterexample before calling
it an application bug. `--supported-only` requires every cataloged group;
missing, skipped or failed proof results cannot count as acceptance.

Nanoda may overflow its worker stack on B3. The checker runner retains the failed
bundled result and tries the same pinned binary/export in a sandbox with one
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

Voiding retains capacity until positive terminal confirmation. Inspect the
pending obligation and its durable attempt budget; an authorized operator can
use `Server.redrive_void/2`. An exhausted budget, absent lookup record or elapsed
time does not release capacity. If the processor never provides reliable
confirmation, capacity stays held indefinitely.

A `:missing_terminal_attestation` startup error means the adapter declaration is
absent or unsupported. Implement the processor contract only if the integrator
can attest to permanent terminal non-resurrection, including void-before-authorize.
A declaration passing validation is not evidence that the remote service is honest.
