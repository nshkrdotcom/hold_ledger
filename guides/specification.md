# Specification

The ledger models one account placing authorization holds. It does not transfer
or settle funds. `HoldLedger.Spec` is the executable oracle for this contract.

## State and validity

```elixir
{amount_limit, hold_limit, used_amount, used_holds, entries}
# each entry: {integer_key, positive_integer_amount, status}
```

Limits and used counters are nonnegative integers. Entries form a proper list
with unique integer keys and positive integer amounts. Known statuses are
`:reserved`, `:sent`, `:unknown`, `:authorized`, `:declined` and `:voided`.

Reserved, sent, unknown and authorized entries consume their amount and one
hold slot. Declined and voided entries consume neither. Used counters equal
the sum and count of holding entries and cannot exceed the two limits.
Entries remain remembered even after they become terminal.

`Ledger.init(amount_limit, hold_limit)` returns an empty valid state for
nonnegative integer limits. Other arguments raise `FunctionClauseError`.
`Spec.valid?/1` rejects malformed or inconsistent states.

## Events

`Ledger.step(valid_state, event)` returns `{next_state, result, effects}`.

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
| `{:void, key}` | Authorized | `:voided`; release amount and slot | `[{:void, key}]` |

Well-formed key events for absent keys return `:not_found`, except transport
acknowledgments, which always return `:stale`. Existing entries in ineligible
statuses return `:stale`. Malformed shapes, noninteger keys, nonpositive amounts
and unknown processor outcomes return `:malformed` before lookup.

For requests, duplicate/conflict checks precede capacity checks. If both caps
would fail, the hold limit takes precedence. An exact amount fit is admitted.
All non-applied results leave the entire state identical and emit no effects.

## Uncertain outcomes and identities

A timeout or restart never releases capacity. An unknown entry keeps its own
amount and hold contribution, although unrelated requests can change global
counters. Retrying reuses the original key and amount. A transport acknowledgment
cannot authorize a hold. Declined and voided keys cannot allocate again.
An approved authorization continues consuming capacity until explicitly voided.

Effects describe intended I/O. The pure API does not establish that a processor
received or honored them. A local void is not proof of a successful external void.

## Replay

`Ledger.run(valid_state, proper_event_list)` folds events in order and discards
effects. It does not execute historical requests. Runtime startup separately
applies a new `:restart` after replay, so recovered sent entries become unknown.
No finite-history theorem covers improper event lists, wall-clock execution,
key expiry, pruning or multiple owners.
