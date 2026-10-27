# Getting started

You can learn the central idea of Hold Ledger without installing anything: a lost processor reply leaves a hold unresolved, so capacity stays reserved. Read the [crash course](formal_verification_crash_course.md) if that is your starting point. This guide is for when you want to run the code or check a proof yourself.

There are three useful milestones: run the simulated ledger, check one law, and, if needed, run the complete verification suite. The full checker pipeline is not required to finish the tutorial.

## Environment

The supported checkout runs on Ubuntu **26.04 x86_64**, with Elixir **1.20.4** compiled against OTP 29, Erlang/OTP **29.1.2**, `uv` **0.12.6**, and Git. uv manages Python **3.13.15** and `zstandard`. The version pins are in `.tool-versions`, `.python-version`, `lean-toolchain`, `mix.lock`, `uv.lock` and `scripts/toolchains.json`.

To run the demo or tutorial proofs, select the pinned Elixir/OTP versions in your existing installation, then run from the repository root:

```sh
uv sync --locked
uv run --locked python scripts/onboard.py --profile runtime --provision
export ELAN_HOME="$PWD/.local/elan"
export ELAN_TOOLCHAIN="$(cat lean-toolchain)"
export PATH="$ELAN_HOME/bin:$PATH"
mix deps.get
mix compile --warnings-as-errors
```

The `runtime` profile checks Elixir, OTP and Git without checking for `bwrap`. `--provision` installs checksum-pinned Elan, Lean and Lake in ignored `.local/`. It does not install Elixir/OTP or change global tools or shell settings. The exports select the local Lean toolchain for this shell.

Even ordinary `mix test` runs compile the test-only Lynx dependency through Lake, so they need Lean installed. The application itself needs only Elixir/OTP.

For the full independent proof checker, install `bwrap` (Bubblewrap) separately and check the complete toolchain:

```sh
uv run --locked python scripts/onboard.py --profile proofs
```

You don't need `bwrap` for the demo or focused proofs. The onboarding command checks for it but does not install it.

The guides also use this wrapper:

```sh
uv run --locked python scripts/local_run.py mix --version
```

`local_run.py` selects the repository-local tool environment for a single command. Use that form in examples if you don't want to rely on persistent shell exports. Do not use it as a way to bypass a failed version or checker prerequisite.

## Run the demonstration

```sh
mix run scripts/demo.exs
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

Run `mix test` first, then strict Credo and Dialyzer as needed. [Testing](testing.md) lists the commands and their scope; [Verification](verification.md) covers the separate, expensive formal checks. If prerequisites fail, use [Troubleshooting](troubleshooting.md) rather than changing version pins silently.
