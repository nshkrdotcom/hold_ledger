# Processors

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
outcome, `:not_found`, or an error. Void returns `{:ok, :voided}`, `{:ok, :already_voided}`, or an error. Not-found is unresolved. See the
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
and an authorized void keeps capacity held until terminal confirmation.

The simulator has no network integration and is not a production payment adapter.

## Void identity and completion

Repeated void calls use the same hold key in the configured account/processor scope. The adapter must make that operation repeatable for the required retention lifetime, including execution with a lost reply. A local task kill does not cancel remote work. Unexpected replies and arbitrary error terms are normalized into bounded failure atoms; they cannot mark a void complete. `:not_found` is not confirmation of a void.

## Terminal attestation and retention

`capabilities(context)` returns
`%{terminal_confirmation: true, non_resurrection: :permanent}` for a supported
adapter. This is an integrator attestation. Validation checks its presence and
shape, not the service's actual behavior. Callback authority, correct payload
binding, truthful declines and deduplication remain external assumptions.

A positive void confirmation must establish terminal non-exposure: even a void
that arrives before the first authorize must fence the identity, preventing every
later delayed or repeated authorization. The guarantee must survive expiration
of ordinary deduplication/lookup records. This contract uses permanent fencing;
an adapter that cannot attest to it is unsupported. `not_found` is unresolved.
The in-memory simulator retains tombstones until that simulator is stopped;
it is not evidence that a real processor or a restarted simulator persists them.

`dedupe: false` is an intentionally unsupported simulator configuration for Server.
It remains useful for direct simulator experiments demonstrating failed receiver
assumptions. A supported processor can still be unavailable indefinitely; in that
case a voiding hold retains capacity indefinitely without a write-off path.
