# Guides

A lost processor reply leaves a hold unresolved. The ledger keeps its capacity
reserved; a timeout cannot release it. These guides follow that rule through
the code, the proofs and the review.

## Write and read proofs

Start with the crash course, then read the shared proofs. The agent guide takes
up the work of choosing and challenging the claim itself.

| Guide | Read it to… |
|---|---|
| [Formal verification crash course](formal_verification_crash_course.md) | Write an Elixir law and see why exact-fit requests must succeed. |
| [Reading deeper proofs](reading_deeper_proofs.md) | Read the shared lemmas behind lookup, accounting and finite histories. |
| [Agentic verification](agentic_verification.md) | Ask an agent to challenge a contract, then inspect the evidence. |

## Run the project

| Guide | Read it to… |
|---|---|
| [Getting started](getting-started.md) | Prepare the tools, run the demo and attempt a ledger proof. |
| [Testing](testing.md) | Choose a check script, run mutations and find the logs. |
| [Verification](verification.md) | Check which laws ran, on which source, and what the result establishes. |
| [Troubleshooting](troubleshooting.md) | Investigate a failed tool, proof stage or runtime operation. |

## Read the system

| Guide | Read it to… |
|---|---|
| [Architecture](architecture.md) | See how the pure core, specification, runtime and proof library fit together. |
| [Specification](specification.md) | Look up state tuples, events, results and capacity-release rules. |
| [Runtime and recovery](runtime.md) | Follow journal writes, effects, reconciliation and crash recovery. |
| [Processors](processors.md) | Understand the simulator and the guarantees a real processor must provide. |

## Review a guarantee

A proof can pass while the claim leaves an unwanted outcome open. The exercises
let you judge that outcome before reading the answer; the assurance guides
examine the requirements and assumptions behind it.

| Guide | Read it to… |
|---|---|
| [Human review](human_review.md) | Decide whether a diff repairs a proof or changes its promise. |
| [Practice reviewing a formal claim](interactive_review.md) | Choose a review exercise that needs no installed tools. |
| [Payment-hold review exercises](payment_hold_review_exercises.md) | Judge eight proposed payment outcomes against the policy. |
| [Reviewing changed guarantees](reviewing_changed_guarantees.md) | Spot excluded inputs and lost postconditions. |
| [Reading review evidence](reading_review_evidence.md) | Distinguish an available proof implementation from a completed check. |
| [Specification assurance](specification_assurance.md) | Check whether the claims rule out the failures you care about. |
| [Assurance audit](audit.md) | Trace the compiler, translation, storage and processor assumptions. |
