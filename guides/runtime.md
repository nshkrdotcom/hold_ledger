# Runtime and recovery

`HoldLedger.Server` owns a ledger backed by one explicit journal path. The
application provides `HoldLedger.EffectSupervisor` for asynchronous effects.

## Start and submit

In an `iex -S mix` session:

```elixir
alias HoldLedger.{Server, Processor.Sim}
{:ok, processor} = Sim.start_link(dedupe: true)
{:ok, ledger} = Server.start_link(
  path: Path.join(System.tmp_dir!(), "my-hold-ledger.log"),
  journal_name: :my_hold_ledger,
  caps: {10_000, 3},
  processor: {Sim, processor}
)

{:ok, :admitted} = Server.submit(ledger, {:request, 11, 7_000})
{:ok, :dispatched} = Server.submit(ledger, {:dispatch, 11})
:ok = Server.await_idle(ledger)
Server.state(ledger)
Server.status(ledger)
```

Use a dedicated path and distinct journal name for each instance. Reusing a path
reopens that ledger's history; capacities must match its persisted configuration.
`start_link/1` optionally accepts a registered `:name`. Stop with
`GenServer.stop(ledger)` to close the journal.

For automatic supervision, configure before application startup:

```elixir
config :hold_ledger, :server_options,
  name: MyLedger,
  journal_name: :my_hold_ledger,
  path: "/var/lib/my_app/holds.log",
  caps: {10_000, 3}
```

Supply a `:processor` tuple for effect execution. The default has no external
processor. A consuming application's supervisor can instead start Server after
its processor, using explicit child options. There is no automatic journal path.

## Persistence and failures

Every input, including stale or malformed callbacks, is appended and synced
before the state transition. Append/sync errors leave the current memory state
unchanged, schedule no effects and poison the writer. A failed sync may still
leave an unacknowledged event on disk; recovery must inspect persisted history.

Startup validates the complete journal, folds events without reissuing old
effects, and appends a new restart event before serving calls. `Server.recovery/1`
returns the pre-restart and post-restart states and replay count. Any recovered
sent request becomes unknown. Invalid configuration or corruption prevents startup.

## Reconcile an unknown request

```elixir
Server.reconcile(ledger, 11)
Server.retry_after_lookup(ledger, 11)
```

Reconciliation queries the processor and journals an approved/declined result.
A reliable not-found result permits an explicit retry with the same identity.
An unavailable lookup leaves the hold unresolved. Direct `{:retry, key}` events
also exist; their safety depends on receiver deduplication.

`Server.await_idle/2` waits for pending effect tasks and their outcomes; it does
not resolve a permanently uncertain external result. Processor void receipts
are tracked separately from the ledger's local void intent.

## Runtime assumptions

Journal tests cover truncation, injected append/sync/disk-full failures,
process crashes, replay and concurrent requests. They do not establish behavior
under physical power loss or arbitrary storage corruption. The server is one
owner, not a distributed lock service. Never treat a local accounting transition
as proof of external exactly-once execution.
