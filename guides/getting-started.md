# Getting started

## Environment

The supported source-checkout environment is Ubuntu 26.04 x86_64 with Elixir
1.20.4 compiled against OTP 29, Erlang/OTP 29.1.2, uv 0.12.6 and Git. The
versions are pinned in `.tool-versions`, `.python-version`, `lean-toolchain`,
`mix.lock` and `uv.lock`. Other platforms have not been validated.

Python 3.13.15 and the `zstandard` helper are managed by uv. They support local
proof-tool installation, not the application runtime. Existing Elixir and OTP
are checked, not installed by the onboarding script.

```sh
uv sync --locked
uv run --locked python scripts/onboard.py --provision
mix deps.get
mix compile --warnings-as-errors
```

Onboarding verifies release-download checksums and installs Elan/Lean/Lake in
ignored `.local/`. It does not change shell profiles or global tools. The wrapper
sets the local proof-tool environment for each command. Lean is needed for the
explicitly selected formal test modules; plain `mix test` runs the ordinary suite by default, and using the application itself requires only Elixir/OTP.

## Run the demonstration

```sh
mix run scripts/demo.exs
```

The default seed is 4808. Set `HOLD_LEDGER_SEED` to another nonnegative integer
to change the synthetic identities. Each invocation creates a new temporary
journal directory and prints its location. The demonstration leaves those files
for inspection; remove that printed directory when finished.

## Use the pure API

Start an interactive session with:

```sh
uv run --locked python scripts/local_run.py iex -S mix
```

```elixir
alias HoldLedger.{Ledger, Spec}
s = Ledger.init(100, 2)
{s, :admitted, []} = Ledger.step(s, {:request, 1, 40})
{s, :duplicate, []} = Ledger.step(s, {:request, 1, 40})
true = Spec.valid?(s)
```

Amounts are positive integer cents; keys are integers. Pure transitions do not
write files or send network requests. See [Specification](specification.md) for
all events and [Runtime and recovery](runtime.md) for the journaled server.

## Use as a dependency

Until a published release is available, depend on an explicit repository commit:

```elixir
{:hold_ledger,
 git: "https://github.com/nshkrdotcom/hold_ledger.git",
 ref: "<full-commit-sha>"}
```

The application starts a task supervisor. It does not open a ledger automatically;
start a server explicitly or configure `:server_options` as described in the
runtime guide. Lynx, StreamData and ExDoc are test/documentation dependencies.

## Local quality checks

Run `mix test` before strict Credo
and Dialyzer. See [Testing](testing.md) for the complete command sequence and
[Verification](verification.md) for the separate expensive formal acceptance.
