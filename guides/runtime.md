# Runtime and recovery

The pure ledger can say that a timeout leaves a hold `:unknown`. A running service has harder work: record the request durably, survive a crash, and avoid treating a lost reply as proof that the processor did nothing. `HoldLedger.Server` is the OTP layer that carries out those transitions with a journal and supervised effects.

`HoldLedger.Server` owns one account and one explicit journal path. The application starts `HoldLedger.EffectSupervisor` with at most 32 task children. Read [Specification](specification.md) first if you need the meaning of an event; this guide describes what happens when the event reaches the server.

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

`caps: {10_000, 3}` sets an amount limit of 10,000 cents and a limit of three concurrent holds.

A dedicated path has one owner in this BEAM instance. These limits must match the
persisted configuration. `start_link/1` accepts a registered `:name` and an
`:effect_supervisor`. Stop with `GenServer.stop/1`. Configure supervised startup
with `config :hold_ledger, :server_options, path: ..., caps: ...` before starting
the application; the default application does not open an account.

## Persistence and input authority

The ordering is deliberate: an accepted event must survive a restart before any local state transition or processor effect depends on it. Admitted input is appended and synced before accounting or effects. Reserved
internal submissions return `{:error, :reserved_event}` after syncing a
`{:rejected_submission, tag}` marker. Malformed inputs use a
`{:malformed_submission, :other}` marker and return `{:ok, :malformed}`. Arbitrary processor terms and rejected payloads are not retained. These markers have fixed shapes and tags from a finite set; their size does not grow with the rejected payload. Frames have a
64 KiB payload limit. Oversized input fails before local application.

The integrating application must authenticate approved/declined reports before passing them to `submit/2`, `processor_callback/3`, or the processor callback mailbox. Server trusts these reports. Internal void completions and lookup observations use correlated task
references and cannot be submitted publicly. Code controlling the VM remains
outside this boundary.

Append/sync failure leaves accounting unchanged and marks the writer **poisoned**: it refuses further commits and new attempts because an unacknowledged append may still exist on disk. Recovery uses the verified records on disk. The default Spec monitor checks validity after each live event; an
invalid state exits with a shutdown/quarantine reason, and the transient child
is not automatically restarted for that shutdown. Preserve the journal and use
read-only inspection. Do not skip a persisted input to restore availability.

## Attempts and deadlines

A deadline can end a *local task* without ending the processor's remote work. `HoldLedger.Attempts` tracks each local attempt through its phases. The [lifecycle proof reference](verification.md#lifecycle-history-theorem) describes its logical guarantees and their limits.
Server maps logical attempts to
`Task.Supervisor.async_nolink` tasks, monitor references, callers, and timers.
When a result or completed shutdown arrives, the attempt enters `:committing`. A successful journal write retires the attempt and releases its slot. Persistence failure poisons the lifecycle.

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

Voids bring the central safety rule into the runtime: capacity stays held until trusted completion, even if the server crashes or retries. An authorized void enters `:voiding`, retains its amount and slot, and creates
exactly one **void obligation**, a durable record of remote void work still owed. It stores the key and retry metadata; it is not a proof obligation. A reserved void releases immediately with no
remote call. The composite invariant requires exactly one void obligation for each voiding key, with no extra obligations. `Composite.step/2` applies the same transition during live operation and replay;
`Spec.expected_composite_step/2` independently models its behavior.

Only correlated `{:ok, :voided}` or `{:ok, :already_voided}` results produce the
single journal event `{:void_confirmed, key}`. After sync, one composite transition
changes the entry to `:voided` and removes the obligation. There is no separate
retirement record or observable half-completed durable state. Public submission
of this event is rejected. Not-found, errors, deadlines and lost replies retain
both capacity and the obligation.

Recovery replays the accepted journal prefix, checks composite validity, records and syncs restart, then retries pending voids. Historical authorization effects are never
reissued. The key, within its account/processor scope, is the remote identity.
Exactly one active/stopping void attempt exists per key in one Server lifetime;
remote work and orphaned workers can overlap a replacement lifetime, so repeated
calls must remain safe remotely.

After the durable automatic attempt budget is exhausted, the hold and obligation
remain visible. `Server.redrive_void(ledger, key)` resets that budget explicitly;
active keys return `{:error, :attempt_active}`. The [retention rule](specification.md#pending-voids-and-composite-recovery) still applies after retries are exhausted. See [Troubleshooting](troubleshooting.md#a-hold-stays-voiding-or-an-adapter-is-rejected) for the operator response.

Configured processors must supply an integrator-attested declaration through
`capabilities/1`. Startup rejects missing, malformed or unsupported declarations;
it cannot detect a false claim. See [Processors](processors.md#terminal-attestation-and-retention) for the permanent fencing guarantee required before confirmation can release capacity.

## Lookup and inspection

```elixir
# Look up key 11 and record the observed outcome.
Server.reconcile(ledger, 11)
# Look it up, then retry the same key if it is still eligible and not found.
Server.retry_after_lookup(ledger, 11)

# Each page starts at offset 0 and contains at most 100 items.
Server.inspect_work(ledger, :unknown, 0, 100)    # unknown holds
Server.inspect_work(ledger, :voids, 0, 100)      # pending void work
Server.inspect_work(ledger, :conflicts, 0, 100)  # conflicting processor reports
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

Inspect the file without changing it before attempting recovery. The journal uses the application-owned `HOLDJNL1` format. Each frame contains a
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

Use [Testing](testing.md#targeted-runtime-tests) to exercise fault paths. Before connecting an external service, read the [Processor contract](processors.md#contract-required-of-a-real-adapter); a successful local restart test cannot establish the remote guarantees.
