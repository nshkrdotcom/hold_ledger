<p align="center">
  <img src="assets/hold_ledger.svg" alt="Hold Ledger" width="200" height="200">
</p>

# Hold Ledger

[![GitHub](https://img.shields.io/badge/GitHub-hold__ledger-181717?logo=github)](https://github.com/nshkrdotcom/hold_ledger)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

A payment processor might authorize a hold and lose the reply. Your server sees a timeout. Is it safe to give that money back to the customer's available balance?

No: the authorization may still be live. That small uncertainty is the thread running through Hold Ledger, an Elixir example for learning formal verification with [Lynx](https://github.com/josevalim/lynx) and Lean 4. It has a pure ledger, an independently written specification, a journaled OTP runtime, tests, and machine-checked laws. No prior Lean knowledge is needed: the crash course teaches enough to read a proof while you work with a small Elixir program.

The project is for developers who know Elixir and testing but are new to formal proofs. It also explores how to work with a coding agent on specifications and proofs **without letting a passing proof silently redefine what the program must do**. The agent can investigate, write code, propose contracts and attempt proofs. A person is needed when the requirements or accepted risks themselves must be decided.

## Choose where to start

You do not need to read the entire repository in order. Pick the route that matches what you want to do.

| You want to… | Start here | What you'll do |
|---|---|---|
| Understand Lean and Lynx from scratch | [Formal verification crash course](guides/formal_verification_crash_course.md) | Go from a familiar ExUnit test to a Lynx law, read Lean goals, plant a bug, then follow a real ledger law. You can read along without installing anything. |
| Verify something with a coding agent | [Agentic verification](guides/agentic_verification.md) | Challenge contracts and review evidence using Elixir examples; no Lean tactics required. |
| Review an agent-generated change | [Human review](guides/human_review.md) | Classify changes to code, proof bodies and their meaning; practice with seven deliberately tricky diffs. |
| Run the example or check a proof | [Getting started](guides/getting-started.md) | Set up the pinned tools, run the ledger, then select a focused proof or full verification. |

For shared lemmas, induction and history models, continue from the crash course to [Reading deeper proofs](guides/reading_deeper_proofs.md).

The [Specification assurance](guides/specification_assurance.md) guide explains why a correct proof may establish an inadequate requirement. [Verification](guides/verification.md) describes evidence and checker boundaries. The [assurance audit](guides/audit.md) is an advanced, system-wide review, not a prerequisite for the tutorial.

## Try it on a supported machine

The source-checkout environment is **Ubuntu 26.04 x86_64** with Erlang/OTP **29.1.2**, Elixir **1.20.4** (built with OTP 29), Python **3.13.15** through `uv` **0.12.6**, Git, and `bwrap` (Bubblewrap). The onboarding script checks existing Elixir/OTP installations and `bwrap`; it does not install them.

The examples use the Lynx commit pinned in `mix.lock` and Lean **4.35.0** from `lean-toolchain`; [Verification](guides/verification.md#coverage-and-provenance) identifies the exact versions.

From the repository root, after selecting the required Elixir/OTP installation:

```sh
uv sync --locked
uv run --locked python scripts/onboard.py --provision
export ELAN_HOME="$PWD/.local/elan"
export ELAN_TOOLCHAIN="$(cat lean-toolchain)"
export PATH="$ELAN_HOME/bin:$PATH"
mix deps.get
mix run scripts/demo.exs
```

The demo uses a simulated processor and a fresh temporary journal; it does not move money. The installed Lean/Lake tools stay under ignored `.local/`. If setup stops on a prerequisite, see [Getting started](guides/getting-started.md) and [Troubleshooting](guides/troubleshooting.md) rather than bypassing the check.

To see a **real ledger proof attempt**, start with the duplicate-request law (`po_a4_duplicate`):

```sh
uv run --locked python scripts/run_laws.py --slug po_a4_duplicate --stage proofs \
  --report tmp/verification/po_a4-learning.json
```

This is a focused development check, not whole-repository acceptance. The [crash course](guides/formal_verification_crash_course.md#read-a-ledger-law) walks through this law’s witness, statement and shared Lean proof after a smaller example. [Verification](guides/verification.md#run-checks) covers the full proof/export pipeline and its prerequisites.

## The ledger in a few steps

Hold Ledger models **one account** with two limits: the total amount reserved, in positive integer cents, and the number of concurrent holds. Every request has an integer key that is never reused, even after the request finishes.

A pure transition takes a state and event and returns `{next_state, result, effects}`. It describes I/O but does not perform it:

```elixir
alias HoldLedger.{Ledger, Spec}

s0 = Ledger.init(100, 2)
{s1, :admitted, []} = Ledger.step(s0, {:request, 11, 100})
{s2, :dispatched, [{:authorize, 11, 100}]} = Ledger.step(s1, {:dispatch, 11})
{s3, :marked_unknown, []} = Ledger.step(s2, {:timeout, 11})

true = Spec.valid?(s3)
{^s3, :insufficient_amount, []} = Ledger.step(s3, {:request, 12, 100})
```

The second request fails because a lost reply is not a decline. The `:unknown` entry still uses 100 cents and one slot. Retrying it uses its original key and amount. An authorized entry that is being voided likewise keeps its capacity until a trusted terminal confirmation arrives.

Here is the important part of the lifecycle:

```text
request -> reserved -> sent --timeout or restart--> unknown
                       ^                               |
                       +------- retry same key -------+

sent or unknown --approved--> authorized --void--> voiding
                                                (still held)
                                                     |
                                     trusted void confirmation
                                                     v
                                                   voided
                                               (capacity freed)
```

Every ledger state shown above retains capacity except `:voided`. A processor decline frees the hold; voiding an undispatched `:reserved` entry also frees it immediately. Terminal keys remain remembered. The [Specification](guides/specification.md) lists all events and results, including stale and malformed inputs.

## What the checks establish

Tests and proofs answer related but different questions. An ExUnit assertion checks a particular history; a StreamData property samples many histories; a Lean proof establishes its *stated theorem* for every input satisfying its assumptions. A valid-state preservation proof alone would allow a ledger that refuses every request. Hold Ledger therefore includes positive-admission laws, identity and effect laws, finite-history properties, and deliberately broken mutations that challenge them.

Try [planting the exact-fit bug](guides/formal_verification_crash_course.md#plant-a-bug-and-watch-the-checks): change `>` to `>=`, keep the law fixed, and see the test, property and proof attempt fail. The [mutation catalog](guides/testing.md#deliberate-mutations) extends that exercise to ten ledger faults.

Lynx and the checkers process the claim in these steps:

```text
Elixir reducer + law (`requires` / `expects`)
              |
       Core Erlang output
              |
        Lynx translation
              |
  Lean theorem + supplied proof
              |
  proof checking and, for full acceptance,
  fresh exports and independent checker runs
```

**A checked theorem does not choose the right requirement.** For example, a ledger could release capacity at the moment a void is *requested* and still leave its local counters internally consistent. To reject that behavior, the law must require capacity to remain held until confirmation. The [agentic walkthrough](guides/agentic_verification.md) lets you test this distinction yourself.

There are also important limits to the evidence:

| Evidence | What it covers | What it does not establish |
|---|---|---|
| Lean/Lynx laws | Specified pure reducer, composite, attempt and exposure-model properties under their hypotheses | Physical journal durability, a real processor's honesty, or universal compiler/translation correctness |
| ExUnit, properties and fault injection | Executed code paths, bounded generated examples, injected failures and OTP recovery cases | All possible runtime interleavings or physical power-loss behavior |
| Full proof acceptance | Fresh proof/export and axiom checks for the required obligations on the reviewed source | That the obligations themselves express every intended policy |

The external processor must deduplicate requests, report truthful outcomes, and permanently fence a voided identity against delayed authorization. A capability declaration is an integrator's attestation, not a remote-service proof. There is no remote exactly-once or eventual-release guarantee. The compiler, translator, kernel, operating system and storage also have explicit trust boundaries. Read [Verification](guides/verification.md), [Processors](guides/processors.md) and [Runtime and recovery](guides/runtime.md) before making deployment claims.

## Learning to work with an agent

An agent can carry out this workflow under agreed policy:

1. **Find the policy.** The agent collects requirements and traces; a person resolves a missing or disputed decision.
2. **Draft and challenge the claim.** The agent proposes `requires`/`expects`, valid inputs and deliberately wrong outputs. Check that the claim rejects the wrong outputs for the right reason.
3. **Implement and prove.** The agent can change code and proof tactics under an agreed policy. A theorem statement, called definition, trusted assumption or coverage change needs separate semantic review.
4. **Report the evidence.** Check which command ran, what source it covered, what passed, and what remains unknown. A timeout is not a counterexample or an accepted proof.

[Agentic verification](guides/agentic_verification.md) has a worked exercise and prompts; [Human review](guides/human_review.md) explains what may be delegated and includes a decision practice set. The repository's `AGENTS.md` contains instructions for an agent working on this codebase.

## Documentation map

These guides serve different moments in the same learning process. The first group teaches; the others are there when you need details.

| Guide | Use it for |
|---|---|
| [Getting started](guides/getting-started.md) | Prerequisites, local tools and first run |
| [Formal verification crash course](guides/formal_verification_crash_course.md) | Run a law, read a proof failure, plant a bug and inspect a ledger claim |
| [Reading deeper proofs](guides/reading_deeper_proofs.md) | Inspect predicates, follow shared proofs and read recursive history models |
| [Agentic verification](guides/agentic_verification.md) | A complete contract challenge and agent-assisted verification task |
| [Human review](guides/human_review.md) | Change classification, escalation and seven review exercises |
| [Specification assurance](guides/specification_assurance.md) | Vacuity, missing guarantees, contract comparison and research |
| [Architecture](guides/architecture.md) | How the pure core, reference model, runtime and proofs fit together |
| [Specification](guides/specification.md) | The exact ledger state and event contract |
| [Runtime and recovery](guides/runtime.md) | Journal, tasks, reconciliation and durable voids |
| [Processors](guides/processors.md) | The simulator and required remote-service behavior |
| [Testing](guides/testing.md) | Tests, mutations, differential checks and benchmarks |
| [Verification](guides/verification.md) | Law catalog, proof commands, acceptance and provenance |
| [Troubleshooting](guides/troubleshooting.md) | Setup, proof and runtime failure symptoms |
| [Assurance audit](guides/audit.md) | Advanced review of models, foundation and runtime assumptions |

## License

MIT. See [LICENSE](LICENSE).
