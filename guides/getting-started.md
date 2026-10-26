# Getting started

You can learn the central idea of Hold Ledger without installing anything: a lost processor reply leaves a hold unresolved, so capacity stays reserved. Read the [crash course](formal_verification_crash_course.md) if that is your starting point. This guide is for when you want to run the code or check a proof yourself.

There are three useful milestones: run the simulated ledger, check one law, and, if needed, run the complete verification suite. The full checker pipeline is not required to finish the tutorial.

## Environment

The **source-checkout environment** is Ubuntu **26.04 x86_64**, with Elixir **1.20.4** compiled against OTP 29, Erlang/OTP **29.1.2**, `uv` **0.12.6**, Git, and `bwrap` (Bubblewrap). Python **3.13.15** and the `zstandard` helper are managed by uv. Version pins live in `.tool-versions`, `.python-version`, `lean-toolchain`, `mix.lock`, `uv.lock` and `scripts/toolchains.json`.

The onboarding command below checks `bwrap` as part of its default proof-tool profile, even if you plan to run only a focused proof. The full independent checker uses it to isolate proof checking.

The installer verifies your **existing** Elixir and OTP installations; it does not install or replace them. It downloads checksum-pinned Elan, Lean and Lake into ignored `.local/`, without changing shell profiles, global tools or host security settings. Python supports that tooling; it is not part of the Elixir application's runtime.

From the repository root, with the required Elixir/OTP already selected:

```sh
uv sync --locked
uv run --locked python scripts/onboard.py --provision
export ELAN_HOME="$PWD/.local/elan"
export ELAN_TOOLCHAIN="$(cat lean-toolchain)"
export PATH="$ELAN_HOME/bin:$PATH"
mix deps.get
mix compile --warnings-as-errors
```

The exports activate the local toolchain in this shell. A fresh `mix test` compiles the test-only Lynx dependency, which invokes Lake, so test compilation needs Lean/Lake even though ordinary tests exclude formal laws by default. The application itself needs only Elixir/OTP.

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

You should see that `:unknown` holds keep their capacity after a lost reply. That behavior is the question we will later turn into a proof obligation.

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

Once the toolchain is ready, check one maintained law rather than starting the full suite:

```sh
uv run --locked python scripts/run_laws.py --slug po_a2 --stage proofs \
  --report tmp/verification/po_a2-learning.json
```

`po_a2` says an eligible request must be admitted, including an exact fit. It's stronger than merely requiring valid counters. The [crash course](formal_verification_crash_course.md#apply-the-workflow-to-the-ledger) explains the relation between the law and a concrete boundary case. This command attempts the pinned Lean proof, but does not run the independent export/checker stage. A failure or timeout does not by itself mean the law is false; inspect the log and [Troubleshooting](troubleshooting.md).

For full acceptance with fresh exported proof objects, follow [Verification](verification.md#run-checks). It needs the complete pinned environment and independent checker prerequisites, including `bwrap`; a focused proof attempt is not a substitute.

## Use as a dependency

Until a release is published, use a chosen repository commit rather than an unpinned branch:

```elixir
{:hold_ledger,
 git: "https://github.com/nshkrdotcom/hold_ledger.git",
 ref: "<full-commit-sha>"}
```

The application starts a task supervisor but does not open a ledger automatically. Start `HoldLedger.Server` explicitly or set `:server_options` as shown in [Runtime and recovery](runtime.md). Lynx, StreamData and ExDoc are test or documentation dependencies, not processor services.

## Local quality checks

Run `mix test` first, then strict Credo and Dialyzer as needed. [Testing](testing.md) lists the commands and their scope; [Verification](verification.md) covers the separate, expensive formal checks. If prerequisites fail, use [Troubleshooting](troubleshooting.md) rather than changing version pins silently.
