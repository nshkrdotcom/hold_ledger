<p align="center">
  <img src="assets/hold_ledger.svg" alt="Hold Ledger" width="200" height="200">
</p>

# Hold Ledger

[![GitHub](https://img.shields.io/badge/GitHub-hold__ledger-181717?logo=github)](https://github.com/nshkrdotcom/hold_ledger)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

> An Elixir authorization-hold ledger with formal laws for its pure state machine, an independent specification, and a separately tested journaled OTP runtime.

**For reviewers:** Start with [Human review of a Lynx project](guides/human_review.md).
It covers the required checks, Hold Ledger's policies and trust assumptions,
and a review of the code behind its guarantees.

---

### Table of Contents
1. [Quickstart](#quickstart)
2. [The Real-World Problem](#the-real-world-problem)
3. [What Is This Project?](#what-is-this-project)
4. [The Three Layers of Assurance](#the-three-layers-of-assurance)
5. [The Lifecycle of an Authorization Hold](#the-lifecycle-of-an-authorization-hold)
6. [How Lynx and Lean 4 Work Here](#how-lynx-and-lean-4-work-here)
7. [Interactive Walkthrough](#interactive-walkthrough)
8. [Development Checks](#development-checks)
9. [What Is Proven vs. What Is Assumed](#what-is-proven-vs-what-is-assumed)
10. [Documentation Index](#documentation-index)
11. [License](#license)

---

## Quickstart

### Prerequisites
The validated environment is **Ubuntu 26.04 x86_64** with:
* Erlang/OTP `29.1.2`
* Elixir `1.20.4`
* Python `3.13.15` and `uv` `0.12.6`

### Setup and demo
Clone the repository and provision local tooling:
```sh
# Sync local python tools
uv sync --locked

# Verify existing Elixir/OTP and provision pinned Lean 4.35.0 locally in ignored .local/
uv run --locked python scripts/onboard.py --provision

# Fetch Elixir dependencies using Mix
mix deps.get
mix run scripts/demo.exs
```

---

## The Real-World Problem

Imagine you run an online debit engine or payment gateway. A customer swipes their card at a gas pump or books a hotel room:

1. **Authorization Request**: The merchant requests a $100 hold.
2. **Limit Check**: You check that the customer has at least $100 in available credit, and has not exceeded their concurrent open-hold quota.
3. **Dispatch**: You dispatch the hold request over the network to the card processor.
4. **The Network Drop**: 15 seconds pass. No response arrives. The connection drops.

What state is your system in now?

* If you assume the hold failed and release the $100, the processor may have authorized it. The customer pumps $100 of fuel, your processor settles the charge tomorrow, and your ledger is left with an unauthorized overdraft.
* If you assume it succeeded, but the request was actually dropped before reaching the processor, the customer’s funds remain trapped indefinitely until manual intervention.
* If your node crashes during the round trip and reboots, does your recovered state machine start resending requests and double-billing the card?
* If a duplicate callback arrives 10 minutes later after a timeout or void, does it corrupt your totals?

Most teams tackle these bugs with unit tests and integration tests. But distributed financial edge cases hide in the combinatorial explosion of network delays, crash timings, out-of-order deliveries, and retry loops.

**Hold Ledger** demonstrates conservative accounting and recovery by combining a pure state machine, an append-only journaled OTP runtime, property-based testing, and machine-checked formal proofs in **Lean 4** via **[Lynx](https://github.com/josevalim/lynx)**.

---

A lack of reliable processor evidence can retain capacity indefinitely. This includes pending voids: no timeout or operator write-off creates evidence that an authorization is gone. Reconciliation can resolve known outcomes, subject to the processor contract.

## What Is This Project?

`hold_ledger` models an account placing authorization holds against two independent limits:
1. **Amount Limit**: Total money reserved across all active holds (in positive integer cents).
2. **Slot Limit**: Maximum number of concurrent open holds.

The included processor is a deterministic simulator; this project does not connect to a payment service. The ledger does not implement settlement, expiration, key pruning, multiple accounts, or distributed ownership.

It separates the pure core, independent specification, runtime, and formal verification:

```
+----------------------------------------------------------------------------+
|                              RUNTIME (OTP)                                 |
|                                                                            |
|  Event -> Server -> Journal.append_sync (owned frames + hash chain)        |
|                          |                                                 |
|                          v                                                 |
|                     Composite.step (Pure Reducers)                         |
|                          |                                                 |
|                          +--------> EffectExecutor -> Processor.Sim        |
+--------------------------|-------------------------------------------------+
                           |
                           v
+------------------------------------+    +----------------------------------+
|      INDEPENDENT SPEC (ORACLE)     |    |      FORMAL PROOFS (LEAN 4)      |
|                                    |    |                                  |
|  HoldLedger.Spec                   |    |  Lynx compiles Elixir BEAM       |
|  * Recomputes totals from scratch  |    |  Core AST into Lean definitions. |
|  * Standalone validity invariant   |    |  Cataloged pure-core law groups  |
|  * Transition & effect predicates  |    |  6 checker configurations.       |
+------------------------------------+    +----------------------------------+
```

1. **Pure State Machine (`HoldLedger.Ledger`)**: No disk, no clock, no processes, no side effects. Given an input state and an event, it returns `{next_state, result_atom, effects}`.
2. **Independent Oracle (`HoldLedger.Spec`)**: An independently implemented reference specification. It recalculates totals from entries to check the reducer’s cached counters.
3. **Journaled Server (`HoldLedger.Server`)**: A GenServer managing application-owned framed storage with SHA-256 chaining. Admitted inputs sync *before* the pure reducer steps; rejected internal or malformed submissions produce bounded audit markers.
4. **Formal Verification (`Lynx` + `Lean 4`)**: Translates compiled Core Erlang into Lean definitions. Laws cover accounting, identity preservation, and other specified properties under their explicit preconditions, including valid input states. Terminal absorption and finite-history preservation are included in the catalog.

---

## The Three Layers of Assurance

The project combines three kinds of evidence:

| Level | Technique | How It Works | What It Catches |
|---|---|---|---|
| **1. Deterministic Tests** | ExUnit unit tests & worked traces | Runs hand-picked states against concrete inputs. | Regressions, happy paths, obvious edge cases. |
| **2. Generative Property Tests** | `StreamData` (bounded generated cases) | Generates thousands of arbitrary states, malformed terms, and random histories. | Off-by-one errors, weird term shapes, counter desyncs. |
| **3. Machine-Checked Proofs** | `Lynx` + `Lean 4` Theorem Prover | Proves universal mathematical statements ($\forall s, \forall e \dots$). | The stated properties for all inputs satisfying each law’s preconditions. |

Ten deliberate mutations under `mutants/` exercise exact-fit boundaries, timeout accounting, retry identity, and other contract violations. See the testing guide for the optional mutation experiment; a failed proof alone is not a concrete counterexample.

---

## The Lifecycle of an Authorization Hold

A hold is identified by an integer `key` and holds an integer `amount`. Its lifecycle progresses through a strictly monitored finite state machine:

```
request --admitted--> reserved --dispatch--> sent
sent --timeout/restart--> unknown
unknown --retry (same key/amount)--> sent

sent or unknown --approved result--> authorized
sent or unknown --declined result--> declined (capacity freed)
reserved   --void--> voided (capacity freed; no effect)
authorized --void--> voiding (capacity retained; remote void intent)
voiding --trusted void confirmation--> voided (capacity freed)
```

### Key Invariants:
* **Capacity is Held During Uncertainty**: The statuses `reserved`, `sent`, `unknown`, `authorized`, and `voiding` consume their amount from `amount_limit` and one slot from `hold_limit`. A timeout or a server reboot *never* releases capacity.
* **Idempotent Identity**: An active or terminal key can never be re-used for a fresh request. A matching request yields `:duplicate`; a differing amount yields `:conflict`.
* **Zero Effects on Non-Applied Operations**: Any rejected or stale transition returns the original state bit-for-bit unchanged and emits `[]` effects.
* **Absorbing Terminal States**: Once `:declined` or `:voided`, an entry remains terminal. The one-step laws and finite-history law cover arbitrary future events on valid ledgers.

---

## How Lynx and Lean 4 Work Here

Lynx translates compiled Core Erlang for the pure ledger and its laws into Lean 4 definitions. Handwritten proofs establish the law statements without admissions or custom axioms; the permitted foundational axioms are `propext`, `Quot.sound`, and `Classical.choice`. Exported proof objects can then be checked by six checker configurations.

The compiler and translator remain trusted. A separate differential harness compares sampled BEAM results with actual translated Lean definitions and kernel-checks a deterministic subset; samples do not prove universal correspondence. See the crash-course guide in the documentation index for Lean concepts, tactics, and a worked proof.

---

## Interactive Walkthrough

You don't need Lean installed to explore the pure engine or OTP runtime.

### 1. The Pure State Machine
Start an interactive shell:
```sh
iex -S mix
```

```elixir
alias HoldLedger.{Ledger, Spec}

# 1. Initialize an empty ledger with limit of $100.00 (10,000 cents) and 2 slots
s0 = Ledger.init(10_000, 2)
#=> {10000, 2, 0, 0, []}

# 2. Admit a fresh hold request for key 11, amount $70.00
{s1, :admitted, []} = Ledger.step(s0, {:request, 11, 7_000})
# Notice: used_amount is now 7000, used_holds is 1, entry is :reserved
#=> {{10000, 2, 7000, 1, [{11, 7000, :reserved}]}, :admitted, []}

# 3. Duplicate detection: same key, same amount
{^s1, :duplicate, []} = Ledger.step(s1, {:request, 11, 7_000})

# 4. Conflict detection: same key, different amount
{^s1, :conflict, []} = Ledger.step(s1, {:request, 11, 8_000})

# 5. Over-capacity rejection: slot limit reached
{s2, :admitted, []} = Ledger.step(s1, {:request, 12, 2_000})
{^s2, :insufficient_holds, []} = Ledger.step(s2, {:request, 13, 500})

# 6. Dispatch the hold -> generates an authorization effect
{s3, :dispatched, [{:authorize, 11, 7_000}]} = Ledger.step(s2, {:dispatch, 11})

# 7. Network drops! Timeout moves hold to :unknown (capacity is NOT released)
{s4, :marked_unknown, []} = Ledger.step(s3, {:timeout, 11})
true = Spec.valid?(s4)
# Used amount remains 9,000 cents; used slots remains 2.
```

### 2. The Journaled Server & Recovery
`HoldLedger.Server` wraps this pure state machine inside a GenServer backed by an append-only hash-chained journal. If the node crashes while a request is in-flight, it replays history on startup, applies a `:restart` event, and marks all pending `:sent` items as `:unknown`.

To see this in action, run the self-contained interactive demo:
```sh
mix run scripts/demo.exs
```
This script uses synthetic data and a fresh temporary journal. It exercises lost replies, restart/replay, lookup reconciliation, same-ID retry, voids, and processor deduplication.

---

## Development Checks

### Run tests and static checks
```sh
# Run deterministic tests, bounded StreamData properties, and fault injection
mix test --warnings-as-errors

# Run static analysis without warning suppressions
mix credo --strict
mix dialyzer

# Run Python tooling preflight and guard tests
uv run --locked python -m unittest discover -s tooling_tests -v
```

### Verify formal proofs
```sh
# Inspect the law catalog (static verification; no Lean or BEAM execution)
uv run --locked python scripts/run_laws.py --supported-only --inspect-only

# Verify single law group (uncached compilation & proof check)
uv run --locked python scripts/run_laws.py --slug po_a2 --stage proofs

# Full verification: Run all cataloged law groups through 6 checker configurations
uv run --locked python scripts/run_laws.py --supported-only --stage full --report tmp/verification/checked.json
```

---

## What Is Proven vs. What Is Assumed

The law catalog and required-obligations inventory define the maintained pure-core proof obligations, including terminal-state absorption and finite-history agreement with the independent specification. Catalog status `supported` means a proof implementation is available; acceptance requires a successful report whose source hashes match this checkout. Pending groups make release acceptance incomplete. The full verification command checks fresh proof exports with six checker configurations. See [Verification](guides/verification.md) for commands, provenance, and proof boundaries.

Formal laws concern their declared pure functions and explicit hypotheses; OTP recovery is tested separately. Pending voids retain capacity until one trusted confirmation retires the durable obligation. Remote exposure additionally depends on truthful processor decisions, deduplication and terminal non-resurrection; startup checks an integrator declaration, not processor behavior. There is no remote exactly-once guarantee.

```
[ FORMAL OBLIGATIONS — ACCEPTANCE MUST MATCH THE CURRENT SOURCE ]
---------------------------------------------------------------------------------------------
  * Specified laws for pure reducer functions (HoldLedger.Ledger)
  * Invariant preservation from valid states under arbitrary event terms (PO-S, PO-A1, etc.)
  * Exact accounting deltas and hold slot counting (L3, L5, L6)
  * Positive admission completeness (PO-A2)
  * Duplicate/conflict detection across all lifecycle statuses (PO-A4)
  * Effect generation matching stored key and amount (PO-B3)
  * Authorization gated strictly by processor approval (PO-B4)
  * Declined and voided entries remain terminal (PO-B5)
  * Finite-history oracle agreement, identity, terminal and approval properties (PO-C3)
  * Capacity retention and conditional remote live amount/count bounds (PO-EXPOSURE)
  * Typed lifecycle histories with unique slots/IDs and at-most-once retirement
  * Successful pure composite histories replay to the same abstract state
    (this does not prove journal framing, fsync, restart handling or coupling preservation)

[ TESTED VIA FAULT INJECTION & OTP TESTS ]
---------------------------------------------------------------------------------------------
  * Write-ahead log append & sync failure handling (Server poisoned on fault)
  * Recovery replay from the framed journal after sudden SIGKILL / crash
  * Crash between journal sync and in-memory reducer step
  * Frame/header hash verification and rejection of incomplete/corrupted records
  * Network reply timeouts and simulator fault injection

[ EXTERNAL ASSUMPTIONS (Outside the Verification Boundary) ]
---------------------------------------------------------------------------------------------
  * Processor deduplication honesty (a remote processor might not dedupe)
  * Operating system disk sync durability (fsync honoring physical media flushes)
  * Hardware memory safety and physical power-loss protection
  * Lean 4 kernel, BEAM compiler, and Core Erlang translator correctness
```

---

## Documentation Index

Deep-dive documentation is located in `guides/`:

| Guide | Description |
|---|---|
| [**Human Review**](guides/human_review.md) | Required review, financial policies, trust assumptions, and an assessment of Hold Ledger's source. |
| [**Architecture**](guides/architecture.md) | Structural split between pure state machine, persistence, and effect scheduling. |
| [**Specification**](guides/specification.md) | Full contract: state tuple shape, event semantics, transitions, error atoms. |
| [**Runtime and Recovery**](guides/runtime.md) | Using `HoldLedger.Server`, owned journal framing, crash recovery, and reconciliation. |
| [**Processors**](guides/processors.md) | The processor behavior contract and using `HoldLedger.Processor.Sim` for fault injection. |
| [**Verification**](guides/verification.md) | Detailed verification catalog, checker configurations, proof costs, and evidence identity. |
| [**Formal Verification Crash Course**](guides/formal_verification_crash_course.md) | Introduction to Lean, Lynx, and reading and writing proofs, with a worked law walkthrough. |
| [**Testing**](guides/testing.md) | Unit test structure, `StreamData` configuration, mutation testing runner, and benchmarks. |
| [**Getting Started**](guides/getting-started.md) | Detailed toolchain setup, Ubuntu 26.04 dependencies, and dependency installation. |
| [**Troubleshooting**](guides/troubleshooting.md) | Resolving toolchain drift, stack overflows in Nanoda, and disk lock issues. |

---

## License

MIT License
