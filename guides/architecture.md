# Architecture

When the processor's reply disappears, something in the system must remember that the request might still be live. Hold Ledger divides that job among a pure reducer, a journaled OTP server, a processor adapter and independent checks. This guide maps the pieces; start with [Specification](specification.md) for exact behavior or [Runtime and recovery](runtime.md) to run the server.

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

## From OTP to a proof

The [crash course](formal_verification_crash_course.md) focuses on the pure transitions. Here is how they relate to the running application:

| Task | Responsible code or check |
|---|---|
| Handle a message and update account state | `Server` accepts the input; `Ledger.step/2` computes the transition without I/O. |
| Check behavior across histories | StreamData samples histories; Lean proofs cover the inputs allowed by their preconditions. |
| Recover after restart | `Journal` reads verified records; `Composite` replays the transitions. |
| Call a processor | `EffectExecutor` performs the I/O described by the pure transition. |
| Record an uncertain outcome | The reducer marks the hold `:unknown` and keeps capacity reserved. |

A proof about `Ledger.step/2` does not show whether `Server` synced the journal before scheduling a task. That needs runtime tests and assumptions about storage and the processor.

## Pure state machine

Start here when a question is about **what state transition is allowed**, not about disk writes or network calls. `HoldLedger.Ledger` provides initialization, single-event transitions and finite
history replay. It uses tuples, lists, integers, atoms and named recursion.
It has no I/O, clock, process or hidden state.

`HoldLedger.Spec` independently computes validity, expected transitions and effect
predicates. Neither module calls the other. Tests compare them, and the formal
laws relate the translated ledger to specification predicates.

## Runtime

The server takes the pure transitions and makes them durable before any effect is scheduled. `HoldLedger.Server` owns one ledger and serializes inputs. It journals and syncs
admitted input or a fixed-shape rejection marker before applying state or scheduling effects. Its optional monitor
checks that voiding holds match the pending void records, using the independent Spec.

`HoldLedger.Journal` stores a configuration record and ordered, hash-chained
input records in an application-owned length-prefixed file format. Replay streams verified frames and checks ordering, exact-byte hashes and capacity configuration. Corruption fails closed.

`HoldLedger.EffectExecutor` runs processor operations under a task supervisor
with monitored deadlines and reports correlated outcomes through the journal. The pure `Attempts` reducer controls task phases and slot release; `Outbox` reconstructs remote void obligations and durable attempt budgets. Their proof coverage is separate from ledger laws; see the [verification reference](verification.md#model-boundaries) for their scope.
`HoldLedger.Processor` is the behavior; `HoldLedger.Processor.Sim` is its local
fault-injectable implementation.

## Responsibility boundaries

The proofs cover four parts, each under its own hypotheses:

- The pure ledger transitions.
- The composite state: the ledger together with pending void work.
- The attempt lifecycle, expressed with Lean data types.
- A model of the ledger and processor together.

The runtime, journal, simulator, BEAM,
compiler/translation and OS/storage have separate testing or trust boundaries.
Hash chaining detects checked corruption; it does not authenticate an entire
journal against replacement by an attacker. One server is the intended owner
of one journal; distributed ownership and multi-account transactions are absent.

## Exposure and coupling

Authorized voids enter `:voiding` and retain amount/slot capacity until trusted
confirmation. The composite transition creates a [void obligation](runtime.md#durable-voids), a record of remote work still owed, when a hold enters voiding. It removes that record in the same transition that releases capacity. Exact key equality and
uniqueness of void obligations are checked on replay as well as live application. Spec
has an independent composite oracle and does not call production helpers.

`Environment` models issued authorization identities, remote decisions and
[permanent fencing](processors.md#terminal-attestation-and-retention) with tuples and lists. It states processor assumptions explicitly;
a real adapter's capability declaration is an attestation, not a behavioral proof.

For the exact transitions, use [Specification](specification.md). For questions about tasks, journal sync and recovery, continue with [Runtime and recovery](runtime.md); for what the laws establish, see [Verification](verification.md).
