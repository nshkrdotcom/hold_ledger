# Getting started

You can learn the central idea of Hold Ledger without installing anything: a lost processor reply leaves a hold unresolved, so capacity stays reserved. Read the [crash course](formal_verification_crash_course.md) if that is your starting point. This guide is for when you want to run the code or check a proof yourself.

There are three useful milestones: run the simulated ledger, check one law, and, if needed, run the complete verification suite. The full checker pipeline is not required to finish the tutorial.

## Environment

The supported checkout runs on Ubuntu **26.04 x86_64**, with Elixir **1.20.4** compiled against OTP 29, Erlang/OTP **29.1.2**, `uv` **0.12.6**, and Git. uv manages Python **3.13.15** and `zstandard`. The version pins are in `.tool-versions`, `.python-version`, `lean-toolchain`, `mix.lock`, `uv.lock` and `scripts/toolchains.json`.

## Check the checkout

The canonical entry points are zero-argument Bash scripts. From the repository root:

```sh
./scripts/check_quick.sh
./scripts/check_full.sh
```

Quick runs ordinary checks; full runs formal acceptance. Run both when you need
both kinds of evidence. Each includes setup, resolves the repository root from
its own location, and stops at the first failed command. They do not run the
separate Phoenix app's checks, Credo, Dialyzer, documentation builds or mutations.

Here is the breakdown of the commands in the scripts:

| Command | Purpose |
|---|---|
| `uv sync --locked` | Prepare Python tooling using the committed lockfile. |
| `uv run --locked python scripts/onboard.py --profile runtime --provision` | Quick: validate existing Elixir/OTP and Git; provision pinned local Elan/Lean/Lake. |
| `uv run --locked python scripts/onboard.py --profile proofs --provision` | Full: the same setup, plus validate the full checker prerequisites, including `bwrap`. |
| `uv run --locked python scripts/local_run.py mix deps.get` | Fetch the locked Mix dependencies using the local tool environment. |

Setup reuses the existing local Elan installation, matching Lean extraction and
toolchain link; it reruns validation. Downloads are checksum-verified and cached.
An incompatible or incomplete installation fails with a diagnostic rather than
silently replacing it. Neither helper installs Elixir/OTP, uv, Git or Bubblewrap,
or changes global tools or host security settings.

After setup, **quick** runs:

```sh
uv run --locked python scripts/local_run.py mix format --check-formatted
uv run --locked python scripts/local_run.py mix compile --warnings-as-errors
uv run --locked python scripts/local_run.py mix test --exclude laws
uv run --locked python -m unittest discover -s tooling_tests -v
```

These check formatting, compiler warnings, ordinary examples/properties/runtime
faults, and the Python proof tooling. Ordinary tests still compile Lynx through
Lake, so quick also needs the local Lean toolchain; it does not need Bubblewrap.

After setup, **full** runs:

```sh
uv run --locked python scripts/run_laws.py --supported-only --stage full \
  --report tmp/verification/checked.json
```

This checks every required group with uncached proofs, fresh exports, six checker
configurations and the allowed-axiom audit. Acceptance requires
`release_complete: true` in the report. Full does not repeat the ordinary checks.
Logs and exports stay under ignored `tmp/verification/`. See
[Verification](verification.md#run-checks) for acceptance details.

`local_run.py` selects the repository-local environment for one command, so no
shell exports are needed. After either helper has completed setup, you can use
it to run the demo or focused tutorial commands below.

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

Run `./scripts/check_quick.sh` first, then strict Credo and Dialyzer as needed. [Testing](testing.md) lists the commands and their scope; [Verification](verification.md) covers the separate, expensive formal checks. If prerequisites fail, use [Troubleshooting](troubleshooting.md) rather than changing version pins silently.
