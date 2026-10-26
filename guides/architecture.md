# Architecture

The application separates pure accounting from persistence and processor effects.

```text
input event -> Server -> Journal.append_sync
                         |
                         v
                    Composite.step -> ledger + obligations + result + effect descriptions
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
admitted input or a bounded rejection marker before applying state or scheduling effects. Its optional monitor
checks ledger/obligation coupling using the independent Spec.

`HoldLedger.Journal` stores a configuration record and ordered, hash-chained
input records in an application-owned length-prefixed file format. Replay streams verified frames and checks ordering, exact-byte hashes and capacity configuration. Corruption fails closed.

`HoldLedger.EffectExecutor` runs processor operations under a task supervisor
with monitored deadlines and reports correlated outcomes through the journal. The pure `Attempts` reducer controls task phases and slot release; `Outbox` reconstructs remote void obligations and durable attempt budgets. Their proof coverage is separate from ledger laws; consult the verification guide for accepted scope.
`HoldLedger.Processor` is the behavior; `HoldLedger.Processor.Sim` is its local
fault-injectable implementation.

## Responsibility boundaries

Formal targets include the ledger, composite fold, typed attempt lifecycle and
coupled processor model, each under its declared hypotheses. The runtime, journal, simulator, BEAM,
compiler/translation and OS/storage have separate testing or trust boundaries.
Hash chaining detects checked corruption; it does not authenticate an entire
journal against replacement by an attacker. One server is the intended owner
of one journal; distributed ownership and multi-account transactions are absent.

## Exposure and coupling

Authorized voids enter `:voiding` and retain amount/slot capacity until trusted
confirmation. The composite fold opens an obligation when entering voiding and
closes it in the same transition that releases capacity. Exact key equality and
obligation uniqueness are checked on replay as well as live application. Spec
has an independent composite oracle and does not call production helpers.

`Environment` models issued authorization identities, remote decisions and
terminal fencing with tuples/lists. It states processor assumptions explicitly;
a real adapter's capability declaration is an attestation, not a behavioral proof.
