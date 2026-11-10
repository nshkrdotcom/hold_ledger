# Getting started

You can learn the central idea of Hold Ledger without installing anything: a lost processor reply leaves a hold unresolved, so capacity stays reserved. Read the [crash course](formal_verification_crash_course.md) if that is your starting point. This guide is for when you want to run the code or check a proof yourself.

There are three useful milestones: run the simulated ledger, check one law, and, if needed, run the complete verification suite. The full checker pipeline is not required to finish the tutorial.

## Environment

The supported checkout runs on Ubuntu **26.04 x86_64**, with Elixir **1.20.5** compiled against OTP 29, Erlang/OTP **29.1.2**, `uv` **0.12.6**, and Git. uv manages Python **3.13.15** and `zstandard`. The version pins are in `.tool-versions`, `.python-version`, `lean-toolchain`, `mix.lock`, `uv.lock` and `scripts/toolchains.json`.

## Check the checkout

Start with ordinary checks, or run the complete suite:

```sh
./scripts/check_quick.sh
./scripts/check_all.sh
```

No arguments or shell exports are required. Both resolve the repository root
from their script location. Each checks the installed Elixir/OTP and Git,
prepares locked Python/Mix dependencies, and provisions checksum-verified
repository-local Elan/Lean/Lake. Full formal checks and mutations also require
an existing Bubblewrap (`bwrap`). The helpers do not install system packages
or replace global tools.

Setup reuses matching local tools and cached downloads. An incompatible or
incomplete installation fails with a diagnostic. Ordinary tests compile Lynx
through Lake, so even the quick helper needs the local Lean toolchain.

The helpers detect usable CPUs, CPU quotas and available memory. Independent
work uses at most four workers by default; `--jobs N` overrides that limit and
`--jobs 1` runs serially. `--quiet` hides live output while retaining the log.
For example:

```sh
./scripts/check_all.sh --quiet --jobs 4
```

Each run prints its `/tmp/hold-ledger-check-<mode>.*.log` path. Source snapshots,
workspaces, per-group logs and reports stay under `tmp/check-runs/<run>/`.
The snapshot includes uncommitted source changes; subsequent edits in your main
checkout do not change the worker inputs. Run one helper at a time per checkout.

[Testing](testing.md#check-helpers) lists all five helpers and unpacks their
commands. [Verification](verification.md#run-checks) explains full proof acceptance
and focused lower-level commands. `scripts/local_run.py` remains available for
running one command with the repository-local tools, including the demo below.

## Run the demonstration

```sh
uv run --locked python scripts/local_run.py mix run scripts/demo.exs
```

The demo creates a fresh temporary journal and uses a deterministic simulated processor. It shows a lost reply, restart, reconciliation, retry and void. Its default seed is `4808`; set `HOLD_LEDGER_SEED` to another nonnegative integer to vary synthetic identities. The script prints the journal directory and leaves it for inspection. Remove that **printed temporary directory** when you are finished, not an active application journal.

The demo shows that `:unknown` holds keep their capacity after a lost reply. The crash course [connects this behavior to a ledger law](formal_verification_crash_course.md#which-law-catches-which-mistake) and a mutation that releases capacity too early.

## Use the pure API

For a smaller experiment, start an interactive shell:

```sh
uv run --locked python scripts/local_run.py iex -S mix
```

Then run:

```elixir
alias HoldLedger.{Ledger, Spec}
s0 = Ledger.init(100, 2)
{s1, :admitted, []} = Ledger.step(s0, {:request, 1, 40})
{^s1, :duplicate, []} = Ledger.step(s1, {:request, 1, 40})
true = Spec.valid?(s1)
```

The state did not change on the duplicate request. Amounts are positive integer cents and keys are integers. `Ledger.step/2` is pure: returned effects describe I/O but never execute it. See [Specification](specification.md) for every event, and [Runtime and recovery](runtime.md) for the journaled server.

## Check your first law

Start with the [exact-fit law](formal_verification_crash_course.md#a-first-lynx-law) if you haven't written a Lynx proof before. Then check the ledger's duplicate-request law:

```sh
uv run --locked python scripts/run_laws.py --slug po_a4_duplicate --stage proofs \
  --report tmp/verification/po_a4-learning.json
```

`po_a4_duplicate` says that requesting a recorded key at its original positive amount returns the same state, `:duplicate` and no effects. The [crash course](formal_verification_crash_course.md#read-a-ledger-law) follows this claim from a concrete witness into its shared Lean proof. This command attempts the pinned Lean proof, but does not run the independent export/checker stage. A failure or timeout does not by itself mean the law is false; inspect the log and [Troubleshooting](troubleshooting.md).

For full acceptance with fresh exported proof objects, follow [Verification](verification.md#run-checks). It needs the complete pinned environment and independent checker prerequisites, including `bwrap`; a focused proof attempt is not a substitute.

To inspect the shared admission proof and its predicates next, use [Reading deeper proofs](reading_deeper_proofs.md).

## Use as a dependency

Until a release is published, use a chosen repository commit rather than an unpinned branch:

```elixir
{:hold_ledger,
 git: "https://github.com/nshkrdotcom/hold_ledger.git",
 ref: "<full-commit-sha>"}
```

The application starts a task supervisor but does not open a ledger automatically. Start `HoldLedger.Server` explicitly or set `:server_options` as shown in [Runtime and recovery](runtime.md). Lynx, StreamData and ExDoc are test or documentation dependencies, not processor services.

## Optional source claim evaluator (workbench UI pending)

The ledger and Lean lessons work independently of Phoenix. For the local
practice workbench, use the pinned BEAM tools and run:

```sh
cd apps/review_web
mix deps.get
mix assets.setup
mix assets.build
mix phx.server
```

Open `http://localhost:4000/` to confirm app startup only. The old case and
receipt routes were removed in Milestone A; the replacement interactive UI is
Milestone B work and the configured AI work is Milestone C. For now, run the
source evaluator and typed-codec tests in this separate Phoenix project, or
use the [no-server review exercise](interactive_review.md).

## Local quality checks

Run `./scripts/check_quick.sh` first; it includes strict Credo and Dialyzer. [Testing](testing.md) lists the commands and their scope; [Verification](verification.md) covers the separate, expensive formal checks. If prerequisites fail, use [Troubleshooting](troubleshooting.md) rather than changing version pins silently.
