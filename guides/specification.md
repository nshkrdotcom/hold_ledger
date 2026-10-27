# Specification

This is the behavioral contract to consult **before** asking an agent to prove or change a ledger operation. The ledger models authorization holds for one account, not fund transfer or settlement. `HoldLedger.Spec` is an independently implemented executable reference for this policy; agreement with the implementation is useful evidence but cannot decide whether the policy itself is right.

An issued or potentially issued authorization continues consuming local capacity until reliable terminal evidence allows release. That is why timeout, restart and a local void of an authorized hold do not free it. Voiding an undispatched `:reserved` hold releases capacity immediately.

## State and validity

```elixir
{amount_limit, hold_limit, used_amount, used_holds, entries}
# each entry: {integer_key, positive_integer_amount, status}
```

Limits and used counters are nonnegative integers. Entries form a proper list
with unique integer keys and positive integer amounts. Known statuses are
`:reserved`, `:sent`, `:unknown`, `:authorized`, `:voiding`, `:declined` and `:voided`.

Reserved, sent, unknown, authorized and voiding entries consume their amount and one
hold slot. Declined and voided entries consume neither. Used counters equal
the sum and count of holding entries and cannot exceed the two limits.
Entries remain remembered even after they become terminal.

`Ledger.init(amount_limit, hold_limit)` returns an empty valid state for
nonnegative integer limits. Other arguments raise `FunctionClauseError`.
`Spec.valid?/1` rejects malformed or inconsistent states.

## Events

`Ledger.step(valid_state, event)` returns `{next_state, result, effects}`. Think of `effects` as requests for work outside the pure reducer, not proof that an external service received or completed that work. Read the event table with that distinction in mind.

| Event | Eligible status/condition | Result and change | Effects |
|---|---|---|---|
| `{:request, key, amount}` | Fresh key, positive amount, capacity available | `:admitted`; add reserved entry and counters | `[]` |
| Same key and amount | Any remembered status | `:duplicate`; unchanged | `[]` |
| Same key, different positive amount | Any remembered status | `:conflict`; unchanged | `[]` |
| Fresh request, slots exhausted | — | `:insufficient_holds`; unchanged | `[]` |
| Fresh request, amount unavailable | — | `:insufficient_amount`; unchanged | `[]` |
| `{:dispatch, key}` | Reserved | `:dispatched`; sent | `[{:authorize, key, amount}]` |
| `{:timeout, key}` | Sent | `:marked_unknown`; unknown | `[]` |
| `:restart` | Any valid state | `:restarted`; all sent become unknown | `[]` |
| `{:retry, key}` | Unknown | `:retried`; sent | `[{:authorize, key, amount}]` |
| `{:processor_result, key, :approved}` | Sent or unknown | `:authorized`; authorized | `[]` |
| `{:processor_result, key, :declined}` | Sent or unknown | `:declined`; release amount and slot | `[]` |
| `{:transport_ack, key}` | Any integer key | `:stale`; unchanged | `[]` |
| `{:void, key}` | Reserved | `:voided`; release amount and slot | `[]` |
| `{:void, key}` | Authorized | `:voiding`; retain amount and slot | `[{:void, key}]` |
| `{:void_confirmed, key}` | Voiding | `:voided`; release amount and slot once | `[]` |

Well-formed key events for absent keys return `:not_found`, except transport
acknowledgments, which always return `:stale`. Existing entries in ineligible
statuses return `:stale`. Malformed shapes, noninteger keys, nonpositive amounts
and unknown processor outcomes return `:malformed` before lookup.

For requests, duplicate/conflict checks precede capacity checks. If both limits
would be exceeded, the result is `:insufficient_holds`. An exact amount fit is admitted.
All non-applied results leave the entire state identical and emit no effects.

## Uncertain outcomes and identities

An entry is `:unknown` when an authorization may have executed but its outcome is unresolved. A timeout or restart never releases capacity. An unknown entry keeps its own
amount and hold slot, although unrelated requests can change global
counters. Retrying reuses the original key and amount. A transport acknowledgment
cannot authorize a hold. Declined and voided keys cannot allocate again.
An approved authorization continues consuming capacity while voiding, until a trusted terminal confirmation is journaled.

## Replay

`Ledger.run(valid_state, proper_event_list)` folds events in order and discards
effects. It does not execute historical requests. Runtime startup separately
applies a new `:restart` after replay, so recovered sent entries become unknown.
No finite-history theorem covers improper event lists, wall-clock execution,
key expiry, pruning or multiple owners.

## Pending voids and composite recovery

The ledger alone records the entry's status. The composite state also remembers the remote work still owed, so a crash cannot turn an unfinished void into freed capacity. `{:void_confirmed, key}` applies only to a voiding hold, returns `:voided`,
releases its amount and slot exactly once, and emits no effects. The [event rules](#events) also apply to stale, missing and malformed keys. This event is internal to Server; public attempts to submit it produce a rejection marker without storing the submitted payload.

The composite state is `{ledger, obligations}`, where each **void obligation** records remote void work still owed. The exact set of voiding keys
equals the keys in the void obligations, and each key has exactly one such record. Entering
voiding creates the obligation in the same pure transition. One synced
`{:void_confirmed, key}` record releases capacity and removes the obligation in
one composite fold, shared by live application and replay. Restart preserves
this coupling. Spec independently models the composite transition and its finite-history fold.

Errors, absent lookup records, deadlines and exhausted retries do not release
capacity. If the processor remains unavailable, capacity can stay reserved
indefinitely. There is no timeout release or operator write-off. See
[Troubleshooting](troubleshooting.md#a-hold-stays-voiding-or-an-adapter-is-rejected)
for inspection and retry steps.

A real adapter must attest to [permanent fencing](processors.md#terminal-attestation-and-retention), including voids received before authorization and delayed delivery after deduplication records expire. Startup validates the declaration, not its truth; the remote exposure guarantee depends on the processor honoring it.

When you ask an agent to change a transition, use these event rules to justify the expected outputs before consulting `Spec.expected_step/2`. The [agentic walkthrough](agentic_verification.md) shows that review in practice.
