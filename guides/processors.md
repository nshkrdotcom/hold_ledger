# Processors

`HoldLedger.Processor` defines three callbacks:

```elixir
authorize(context, integer_key, positive_integer_amount)
lookup(context, integer_key)
void(context, integer_key)
```

Configure Server with `processor: {YourProcessor, context}`. Authorization can
return `{:ok, :approved | :declined}`, `{:lost, :request | :reply}`, a delayed
reply, or a list of synthetic callbacks. Lookup returns an approved/declined
outcome, `:not_found`, or an error. Void returns a receipt or an error. See the
behavior's API documentation for exact types.

## Simulator

```elixir
alias HoldLedger.Processor.Sim
{:ok, sim} = Sim.start_link(dedupe: true)
:ok = Sim.queue_fault(sim, :authorize, :execute_then_drop)
Sim.snapshot(sim)
```

Faults are consumed FIFO per operation:

| Operation | Fault | Meaning |
|---|---|---|
| Authorize | `:drop_before` | Request never executes |
| Authorize | `:execute_then_drop` | Hold executes but the reply is lost |
| Authorize | `{:delay, milliseconds}` | Deliver the outcome later |
| Authorize | `:duplicate_callback` | Deliver the result twice |
| Authorize | `{:out_of_order, outcomes}` | Deliver specified outcomes in order |
| Lookup | `:unavailable` | Lookup cannot establish the outcome |
| Void | `:unavailable` | External void fails |

Default decisions are approved. Supply `decisions: [{key, :declined}]` to set
specific outcomes. The snapshot shows receiver records, active holds, attempts
and voids. With `dedupe: false`, retries can create multiple receiver holds for
one local request. The demo exhibits that mismatch.

## Contract required of a real adapter

A real processor must authenticate outcomes, retain deduplication identities
for the relevant lifetime, reject identity/payload conflicts and provide lookup
semantics strong enough for reconciliation. The ledger does not prove those
properties. Network success alone is insufficient evidence of authorization,
and a local void does not establish that remote capacity was released.

The simulator has no network integration and is not a production payment adapter.
