# Runtime and recovery

`HoldLedger.Server` owns one account and one explicit journal path. The
application starts `HoldLedger.EffectSupervisor` with at most 32 task children.

## Start and submit

```elixir
alias HoldLedger.{Server, Processor.Sim}
{:ok, processor} = Sim.start_link(dedupe: true)
{:ok, ledger} = Server.start_link(
  path: Path.join(System.tmp_dir!(), "my-hold-ledger.log"),
  caps: {10_000, 3},
  processor: {Sim, processor}
)
{:ok, :admitted} = Server.submit(ledger, {:request, 11, 7_000})
{:ok, :dispatched} = Server.submit(ledger, {:dispatch, 11})
:ok = Server.await_idle(ledger)
Server.status(ledger)
```

A dedicated path has one owner in this BEAM instance. Capacities must match the
persisted configuration. `start_link/1` accepts a registered `:name` and an
`:effect_supervisor`. Stop with `GenServer.stop/1`. Configure supervised startup
with `config :hold_ledger, :server_options, path: ..., caps: ...` before starting
the application; the default application does not open an account.

## Persistence and input authority

Admitted input is appended and synced before accounting or effects. Reserved
internal submissions return `{:error, :reserved_event}` after syncing a bounded
`{:rejected_submission, tag}` marker. Malformed inputs use a bounded
`{:malformed_submission, :other}` marker and return `{:ok, :malformed}`. Raw
arbitrary processor terms and rejected payloads are not retained. Frames have a
64 KiB payload limit. Oversized input fails before local application.

`submit/2`, `processor_callback/3`, and the processor callback mailbox route
trust the integrating application. They do not authenticate approved/declined
reports. Internal void completions and lookup observations use correlated task
references and cannot be submitted publicly. Code controlling the VM remains
outside this boundary.

Append/sync failure leaves accounting unchanged and poisons writes. An
unacknowledged append may still exist on disk. Recovery uses actual verified
history. The default Spec monitor checks validity after each live event; an
invalid state exits with a shutdown/quarantine reason, and the transient child
is not automatically restarted for that shutdown. Preserve the journal and use
read-only inspection. Do not skip a persisted input to restore availability.

## Attempts and deadlines

`HoldLedger.Attempts` is a separate pure lifecycle model with operation laws and
a typed finite-history theorem bridged to its translated implementation. Its
interleaving properties also check duplicate persistence/retirement intents.
The history proofs establish at-most-once persist intents and require persistence
before retirement; physical writes remain outside that model.
Server maps logical attempts to
`Task.Supervisor.async_nolink` tasks, monitor references, callers, and timers.
A result or completed shutdown enters committing; persistence success retires
it and releases the slot. Persistence failure poisons the lifecycle.

Options and defaults:

| Option | Default | Meaning |
|---|---|---|
| `:authorize_timeout` | 5,000 ms | Authorization task deadline |
| `:void_timeout` | 5,000 ms | Void task deadline |
| `:lookup_timeout` | 5,000 ms | Lookup task deadline |
| `:max_attempts` | 32 | Concurrent attempts per Server |
| `:void_retry_base` | 1,000 ms | Exponential retry base |
| `:void_retry_max` | 60,000 ms | Maximum retry delay |
| `:void_max_attempts` | 5 | Durable automatic void attempt budget |

All values must be positive integers. Retry delay is
`min(max, base * 2^min(attempts, 16))`, without jitter. The first retry defaults
to two seconds. Attempts rejected by startup/capacity still count toward the
void budget. A deployment can supply a separately configured task supervisor.

At a deadline Server kills the local task using `Task.shutdown/2`. An already
available shutdown result is handled before retiring its reference. Otherwise
an authorization becomes unknown and a void remains unresolved. Cancellation
never establishes that remote processing stopped. Task death and startup
exhaustion also produce durable uncertain outcomes. Successful tasks have their
monitor removed with `Process.demonitor(ref, [:flush])`; stale task results and
timers cannot complete retired work.

Nolink workers can survive Server death. Each task also arms an independent lifetime timer, so a blocked orphan cannot occupy the supervisor indefinitely. Recovered sent entries become unknown,
and old worker replies cannot change the replacement Server. A later trusted
callback or a new lookup may establish the outcome.

## Durable voids

An authorized void enters `:voiding`, retains its amount and slot, and creates
exactly one durable obligation. A reserved void releases immediately with no
remote call. The composite invariant requires the exact voiding-key set to equal
the unique obligation-key set. `Composite.step/2` is the shared live/replay fold;
`Spec.expected_composite_step/2` independently models its behavior.

Only correlated `{:ok, :voided}` or `{:ok, :already_voided}` results produce the
single journal event `{:void_confirmed, key}`. After sync, one composite transition
changes the entry to `:voided` and removes the obligation. There is no separate
retirement record or observable half-completed durable state. Public submission
of this event is rejected. Not-found, errors, deadlines and lost replies retain
both capacity and the obligation.

Recovery folds every accepted prefix, checks composite validity, durably records
restart and redrives pending voids. Historical authorization effects are never
reissued. The key, within its account/processor scope, is the remote identity.
Exactly one active/stopping void attempt exists per key in one Server lifetime;
remote work and orphaned workers can overlap a replacement lifetime, so repeated
calls must remain safe remotely.

After the durable automatic attempt budget is exhausted, the hold and obligation
remain visible. `Server.redrive_void(ledger, key)` resets that budget explicitly;
active keys return `{:error, :attempt_active}`. An unavailable processor can hold
capacity indefinitely. There is no timeout release or operator write-off.

Configured processors must supply an integrator-attested declaration through
`capabilities/1`. Startup rejects missing, malformed or unsupported declarations;
it cannot detect a false claim. See [Processors](processors.md) for the permanent
terminal fence required before confirmation can release capacity.

## Lookup and inspection

```elixir
Server.reconcile(ledger, 11)
Server.retry_after_lookup(ledger, 11)
Server.inspect_work(ledger, :unknown, 0, 100)
Server.inspect_work(ledger, :voids, 0, 100)
Server.inspect_work(ledger, :conflicts, 0, 100)
```

Lookup intent is synced before launching asynchronous work. Server remains
responsive while lookup blocks; exceptions and deadlines become unavailable
observations. Concurrent lookup for the same key returns `{:error, :lookup_in_progress}`.
A result is journaled and applied against current eligibility. In particular,
not-found cannot retry a key already resolved while lookup was running.
Lookup-first retry still requires receiver deduplication and reliable lookup
semantics: not-found alone cannot exclude an older request still in transit.

`await_idle/2` waits for current attempts and journaled outcomes, not scheduled
future retries or permanent uncertainty. Its default caller timeout is 5 seconds.
Poisoned writers return an error. Dead callers are removed from waiter tracking.

`status/1` includes the ledger, pending count, poison reason, at most 100 recent
void receipts/conflicts, and at most 100 unresolved voids. `inspect_work/4`
paginates unknown entries and unresolved voids; receipt/conflict pages are within
the most recent 100 retained observations. The full journal preserves evidence.
An approval for a declined entry or a decline for an authorized entry records a
conflict without changing the entry. Results for voiding or voided entries remain
stale without an additional conflict record. `recovery/1` exposes
before/after-restart states and replay count.

## Journal inspection and tail recovery

The journal uses the application-owned `HOLDJNL1` format. Each frame contains a
32-bit payload length, 64-bit sequence, predecessor SHA-256, header SHA-256,
exact serialized payload, and frame SHA-256. Header integrity is checked before
length; frame integrity is checked before decoding. Replay streams a verified
fold and does not retain the full event list in Server.

```elixir
HoldLedger.Journal.inspect_file("/var/lib/my_app/holds.log")
HoldLedger.Journal.recover_tail("/var/lib/my_app/holds.log", "/var/lib/my_app/recovered.log")
```

Inspection is read-only. Recovery is an explicit operation that creates a new
file exclusively and leaves the source untouched. It only copies the verified
prefix when the final frame is incomplete at EOF; complete corrupt headers or
payloads are rejected. The recovered file and containing directory must sync
before success. Never replace an active journal. Review the failure and select
the recovered path explicitly before restarting.

This recovery rule assumes interrupted append after an intact durable prefix
and honest durable-sync semantics. It does not justify discarding acknowledged
history damaged later, repairing interior corruption, or accepting rollback.
A complete shorter prefix remains valid without an external freshness anchor.
Tests do not establish physical power-loss protection or arbitrary storage safety.
