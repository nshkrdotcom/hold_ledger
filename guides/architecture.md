# Architecture

The application separates pure accounting from persistence and processor effects.

```text
input event -> Server -> Journal.append_sync
                         |
                         v
                    Ledger.step -> new state + result + effect descriptions
                         |                         |
                         v                         v
                   Spec monitor              EffectExecutor -> Processor
                                                    |
                                                    v
                                      journaled processor-result event
```

## Pure state machine

`HoldLedger.Ledger` provides initialization, single-event transitions and finite
history replay. It uses tuples, lists, integers, atoms and named recursion.
It has no I/O, clock, process or hidden state.

`HoldLedger.Spec` independently computes validity, expected transitions and effect
predicates. Neither module calls the other. Tests compare them, and the formal
laws relate the translated ledger to specification predicates.

## Runtime

`HoldLedger.Server` owns one ledger and serializes inputs. It journals and syncs
each input before applying it or scheduling its effects. Its optional monitor
checks state validity and expected transitions using Spec.

`HoldLedger.Journal` stores a configuration record and ordered, hash-chained
input records in OTP `:disk_log`. Replay checks ordering, hashes, record shape
and capacity configuration. Corruption fails closed.

`HoldLedger.EffectExecutor` runs processor operations under a task supervisor
and reports their outcomes back through the server's journaled input path.
`HoldLedger.Processor` is the behavior; `HoldLedger.Processor.Sim` is its local
fault-injectable implementation.

## Responsibility boundaries

The formal target is the pure reducer. The runtime, journal, simulator, BEAM,
compiler/translation and OS/storage have separate testing or trust boundaries.
Hash chaining detects checked corruption; it does not authenticate an entire
journal against replacement by an attacker. One server is the intended owner
of one journal; distributed ownership and multi-account transactions are absent.
