# Processors

A local timeout tells you only that your process stopped waiting. The external processor might already have authorized the money. Hold Ledger therefore needs more from a real adapter than a successful network request: stable identities, truthful outcomes, safe retries and terminal void confirmation that cannot later be undone.

This guide describes that boundary and the deliberately limited simulator. It does **not** supply a production payment adapter. For what the ledger does with callbacks, see [Runtime and recovery](runtime.md).

`HoldLedger.Processor` defines four callbacks:

```elixir
capabilities(context)
authorize(context, integer_key, positive_integer_amount)
lookup(context, integer_key)
void(context, integer_key)
```

Configure Server with `processor: {YourProcessor, context}`. Authorization can
return `{:ok, :approved | :declined}`, `{:lost, :request | :reply}`, a delayed
reply, or a list of synthetic callbacks. Lookup returns an approved/declined
outcome, `:not_found`, or an error. Void returns `{:ok, :voided}`, `{:ok, :already_voided}`, or an error. See the
behavior's API documentation for exact types.

## Simulator

Use the simulator to see what the ledger can conclude after a failed request. It can drop a reply after executing an authorization, deliver callbacks twice, or keep lookup unavailable. Try a lost reply:

```elixir
alias HoldLedger.Processor.Sim
{:ok, sim} = Sim.start_link(dedupe: true)
:ok = Sim.queue_fault(sim, :authorize, :execute_then_drop)
{:lost, :reply} = Sim.authorize(sim, 11, 100)
[%{key: 11, amount: 100, status: :active}] = Sim.snapshot(sim).active
```

The call reports a lost reply, but the snapshot shows an active hold. Faults are consumed in the order queued for each operation:

| Operation | Fault | Meaning |
|---|---|---|
| Authorize | `:drop_before` | Request never executes |
| Authorize | `:execute_then_drop` | Hold executes but the reply is lost |
| Authorize | `{:delay, milliseconds}` | Deliver the outcome later |
| Authorize | `:duplicate_callback` | Deliver the result twice |
| Authorize | `{:out_of_order, outcomes}` | Return callbacks in the supplied list order; choose that order to simulate unexpected delivery |
| Lookup | `:unavailable` | Lookup cannot establish the outcome |
| Void | `:unavailable` | External void fails |

Default decisions are approved. Supply `decisions: [{key, :declined}]` to set
specific outcomes. The snapshot shows receiver records, active holds, attempts
and voids.

With `dedupe: false`, retries can create multiple receiver holds for one local request. Server rejects this unsupported configuration, but direct simulator calls can demonstrate the failure. The [demo](getting-started.md#run-the-demonstration) includes that experiment.

## Contract required of a real adapter

The adapter boundary is a trust boundary, not another fact established by the pure-state proofs. A real processor must authenticate outcomes, retain deduplication identities
for the relevant lifetime, reject identity/payload conflicts and provide lookup
semantics strong enough for reconciliation. The ledger does not prove those
properties. Network success alone is insufficient evidence of authorization,
and an authorized void keeps capacity held until terminal confirmation.

## Void identity and completion

Repeated void calls use the same hold key in the configured account/processor scope. The adapter must make that operation repeatable for the required retention lifetime, including execution with a lost reply. A local task kill does not cancel remote work. Unexpected replies and arbitrary error terms become one of a fixed set of failure atoms; they cannot mark a void complete. `:not_found` leaves the outcome unresolved and is not confirmation of a void.

## Terminal attestation and retention

A processor must guarantee that a confirmed void cannot later become an active authorization. This is **permanent fencing**: once the key is voided, no delayed or repeated authorization may create or reactivate a hold for that key. It applies even if the void arrives before the first authorization, and it must survive expiry of ordinary deduplication and lookup records.

For example, suppose the amount limit is 100 and there are two slots. One key holds 100 while its void is pending. Releasing that capacity before confirmation could admit another 100, leaving the processor holding 200. Even after confirmation, that risk returns if a delayed authorization can reactivate the voided key. The [audit traces](audit.md#hold-ledger-the-top-level-view) examine both cases.

`capabilities(context)` must return
`%{terminal_confirmation: true, non_resurrection: :permanent}`. Here
`non_resurrection` is the API name for permanent fencing. The declaration is an
integrator's attestation: startup checks its shape and values, not the service's
behavior. An adapter that cannot make this guarantee is unsupported. Callback
authentication, correct identity/amount binding, truthful declines and
deduplication also remain external assumptions.

The simulator remembers voided keys in records called *tombstones*. Those records
last only until the simulator stops; they do not demonstrate persistence across
a restart or in a real service.

A supported processor can still remain unavailable. The [retention rule](specification.md#pending-voids-and-composite-recovery) then applies; see [Troubleshooting](troubleshooting.md#a-hold-stays-voiding-or-an-adapter-is-rejected) for inspection and retry options.

If you are changing the adapter or its deployment, pair this contract with the [durable-void path](runtime.md#durable-voids) and [runtime fault tests](testing.md#targeted-runtime-tests). Check the service's behavior as well as its declaration.
