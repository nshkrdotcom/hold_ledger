<p align="center">
  <img src="assets/hold_ledger.svg" alt="Hold Ledger" width="200" height="200">
</p>

# Hold Ledger

[![GitHub](https://img.shields.io/badge/GitHub-hold__ledger-181717?logo=github)](https://github.com/nshkrdotcom/hold_ledger)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

Hold Ledger is a tutorial on formal verification with [Lynx](https://github.com/josevalim/lynx) and Lean 4 for developers who know Elixir. You’ll work through a small payment ledger, from ordinary tests to proofs of its behavior. You don’t need to know Lean to get started.

The ledger tracks payment holds. A processor can authorize a hold even when your server never receives the reply. After a timeout, the ledger must still count that hold against available capacity. The examples use cases like this to show how to state a requirement and prove that the code meets it.

You’ll write laws in Elixir, inspect the Lean code that Lynx generates, and work through the proofs. Later guides cover working with coding agents and checking whether the claims you’ve proved match your requirements.

A formal proof can be correct and still leave a release decision stuck. The theorem holds for the model, but the team responsible for the running service cannot tell whether that model describes what the software does. A more elegant proof won't answer their question.

AI may make proofs cheaper to write and repair. That helps, but it leaves a different bill: establishing that a specification describes the right behavior and that a model bears a credible relation to the code people run. When those links hold, a proof may expose a defect, clear a stalled release, or preserve a rule future developers must respect. The running code need not change for the evidence to be useful.

The value depends on what uncertainty the evidence removes and what people can do with it. A new feature, a high-consequence service, and a huge but easily recoverable internal application need different amounts of assurance.

## The migration that could pay for itself

Consider a fictional payment service replacing its journal. It keeps old and new storage paths running in parallel to compare recovery behavior. Parallel operation costs an extra $18,000 a week. The approved fallback plan is to watch both paths for eight more weeks before retiring the old one. More observation isn't a mathematical guarantee, but it's the risk decision the team has already made.

The release approvers are worried about one failure: a late task result, or a worker dying between a processor response and journal acknowledgment, might free capacity or record a final outcome that recovery cannot reconstruct. The engineering lead and operational risk owner set an early-exit rule *before* commissioning more work: an invariant covering every modeled transition, and controlled BEAM tests comparing the service's `GenServer`, task monitors, and journal with those transitions. They will also review the exceptions, including reliance on the storage system's durability contract. They know that even this package cannot cover every real scheduler order.

One option is a $12,000 fault-injection harness that takes two weeks. It drives chosen timeouts, `:DOWN` messages, failed acknowledgments, and replay sequences through the real code. The harness is useful on its own. But for this release, a set of successful traces cannot establish what happens in the untested combinations of those events. The approvers have made that limitation an explicit reason not to retire the old journal yet.

A second option costs $48,000 **in total**, including that harness, and takes three weeks. It adds an inductive proof of a precise rule: once an attempt has been sent, no allowed model transition retires it or frees its occupied slot before the outcome has been durably acknowledged. That covers modeled event combinations the harness never happened to schedule. The harness checks concrete traces against abstract transitions and the replayed journal state. The proof gives breadth inside the model; the harness gives evidence about the model's contact with the implementation. Neither substitutes for the other. The approvers review the unmodeled scheduler behavior and durability assumptions. They accept the remaining risk and authorize cutover. No bug has to be found for the evidence to matter.

If the old path can be retired at the end of week three rather than week eight, that eliminates **five weeks** of parallel running, not eight. At $18,000 a week, that's $90,000 in gross avoided cost. Subtract the $48,000 work and an estimated $6,000 for first-year proof upkeep: $36,000 remains, before any transition costs that differ between the options. Let the exercise slip to week five and the advantage vanishes. The timetable matters as much as the theorem.

That comparison only works under the release conditions stated above. If the $12,000 harness alone could have won sign-off in week two, six saved weeks would mean $108,000 gross, or $96,000 after the harness bill. Here it cannot meet the agreed release rule. That is why the additional proof is worth considering. If the approvers would accept tests alone, or a simpler design eliminated the risky transition, the larger effort would lose its justification.

## The large system that needs less proof

A second fictional example is a reporting platform spanning dozens of services. Its exports contain private customer data, and mistakes can disrupt regulatory filings. A proposal asks for $220,000 to formalize much of the existing transformation pipeline, plus ongoing maintenance. The risks are real, but the proposed scope is a poor fit.

Consider the export boundary. A queued export could use stale permissions and deliver a report to a requester who no longer has access, perhaps from another tenant. The proposed suite spends most of its effort on aggregation and formatting, assuming the permission service and queue behave correctly. Its proofs might be sound and still leave the most consequential failure almost untouched.

Suppose the security owner sets a concrete requirement: an export must not deliver a report to a requester lacking authority for its tenant at delivery time, even if permissions changed after the job was queued. A $45,000 effort could check that property in a bounded export model, challenge delayed authorization changes, and run conformance tests against the real queue and permission checks. It would not verify the whole platform. It might satisfy the important risk limit better than the $220,000 proposal. If financial-reporting rules also require independent evidence of aggregate correctness, or if failures propagate across both components, the scope should change. The issue isn't that the reporting system is harmless. It's that the proposed proof may be aimed at the wrong part of it.

These examples can't be reduced to expected incident cost alone. A company may set a maximum tolerable loss, a safety invariant it refuses to relax, or a contractual evidence requirement. For a rare catastrophic failure, compare options against that limit first. Only then ask which qualifying approach costs less. Unknown dependencies may justify a small exploratory model before the right property is even clear.

The payoff can arrive later. A specification may settle a dispute about intended behavior, speed an incident investigation, or keep a redesign from reviving an old mistake. These are real uses of verified knowledge. They deserve an owner, a likely lifespan, and an upkeep budget, even when no immediate release depends on them.

## What AI actually makes cheap

It's tempting to assume AI-generated proofs will leave teams buried in maintenance. That isn't necessarily true. For a Lean theorem whose statement and trusted assumptions are held fixed, a proof checker gives unusually crisp feedback on an attempted repair. An agent can try a new derivation and learn quickly whether it checks. That does not tell us whether the theorem was the right one, and it doesn't apply in the same way to a bounded scheduler search. A successful bounded check means no violation was found within the states and depth examined, not that an invariant holds for all executions.

AI can produce code faster, too. If that increases the number of changes a team ships, the need for verification can grow even if the defect rate per change stays constant. A proof integrated into development may prevent a bad design from reaching production. The economics of that work are quite different from retroactively proving an established system correct.

The harder problem is **specification fidelity**. If one model writes the feature, its tests, and the property to prove, it may repeat the same misunderstanding in all three. Running two agents from the same mistaken requirements doesn't create independence. Independence must come from the source of authority, not a second prompt. Domain owners need to supply the business rules, failure limits, and incident history; reviewers need to challenge the model without deferring to what the code already does. Then use model-based tests and deliberately forced runtime schedules to look for mismatches. None of this is free, and using AI to generate the harness does not remove the need for that review.

This repo attempts to provide a useful example of this boundary. It uses Lynx to translate Elixir laws into obligations checked with Lean, a proof assistant. Its acceptance inventory has 49 proof groups, including 14 native Lean groups with 21 required named theorems (the *native anchors*), and six checker configurations. Those anchors require specific theorems to be checked. They do not establish that a running `GenServer` handles every `:DOWN` race or journal replay as a concurrent model predicts. A proof about stale replies and attempt retirement needs a separate, explicit link to actual events before it can support that claim.

The migration notes record a genuine tooling defect: an optional batch guard expected a list where Lynx supplied a `MapSet`. That fix matters, but it is not a discovered ledger-runtime bug. Nor are deliberately broken test variants, correctly rejected by checkers, production defects. The reviewed snapshots don't include the Git history needed for a full findings tally. Hold Ledger runs a simulated processor and is meant to teach verification, so avoided payment losses would be the wrong measure of its value anyway.

## A stopping rule that doesn't punish the first week

Formal methods have a startup cost. Teams must learn the tools, get the proof runner working, and often build a reusable fault harness. A review after the first week would mostly measure that expense. Budget an initial learning period explicitly, then evaluate the next tranche after one representative property and its connection to the running system have been tested. Separate one-time setup from the cost of maintaining the next hundred obligations.

At that review, keep separate records of reproduced defects, established properties and their assumptions, decisions changed, and artifacts likely to be reused. For the last category, name the future maintainer or release gate rather than assigning a made-up dollar value to possible reuse. Compare the next tranche with a narrower model, tests, a simpler architecture, or leaving the code alone. The same scrutiny belongs on any expensive testing or observability program. Nobody needs an ROI meeting for each unit test.

A passing proof that finds no bug may pay for itself by settling a real uncertainty. It may also make the next redesign easier. But as proof production gets cheaper, the temptation to prove everything will grow. Spend first on the questions that can change a decision or protect something consequential. And know what evidence would justify stopping.

## Choose where to start

If you're new to Lean, start with the crash course. You'll run a small proof, break a capacity check, and write a law. Then read Reading deeper proofs for the shared lemmas and induction used by the ledger. The agent and review guides are a separate track.

| You want to… | Start here | What you'll do |
|---|---|---|
| Learn Lean through Elixir | [Formal verification crash course](guides/formal_verification_crash_course.md) | Run a small Lynx proof, inspect its Lean goal, catch an exact-fit bug and write a second law. You can read it without installing anything. |
| Follow a maintained proof | [Reading deeper proofs](guides/reading_deeper_proofs.md) | Read predicates, shared lemmas, induction and finite histories. |
| Run the code | [Getting started](guides/getting-started.md) | Set up the pinned tools and run the demo or a focused proof. |
| Work with a coding agent | [Agentic verification](guides/agentic_verification.md) | Challenge a contract and check evidence without writing Lean tactics. |
| Review agent-generated changes | [Human review](guides/human_review.md) | Decide whether a change fixes a proof or changes what is being proved. |

For practice without installing tools, choose a [review exercise](guides/interactive_review.md): judge a payment outcome, spot a changed guarantee, or read a proof report. These are optional exercises for the agent and review track.

[Specification assurance](guides/specification_assurance.md) deals with proofs of inadequate requirements. [Verification](guides/verification.md) explains what the checkers establish. The [assurance audit](guides/audit.md) covers the whole system and is not part of the first lesson.

## Run checks

From the repository root:

```sh
./scripts/check_quick.sh  # Ordinary tests, static analysis and tooling
./scripts/check_all.sh    # Everything, including formal checks, mutants and Phoenix
```

Every helper runs with no arguments. It logs to a unique
`/tmp/hold-ledger-check-<mode>.*.log` and displays output by default; add
`--quiet` to hide live output or `--jobs N` to set a worker ceiling. Automatic
scheduling uses available CPUs within workload memory budgets and task counts.
The master uses isolated copies of the current working tree, including
uncommitted changes, to run independent checks concurrently. Builds and reports
stay under ignored `tmp/check-runs/`; the log identifies the exact run directory.

For a narrower run, use `check_full.sh` (formal acceptance), `check_mutants.sh`
(the ten mutation experiments), or `check_web.sh` (the Phoenix app). Full formal
acceptance requires `release_complete: true` in the completed proof report.
See [Testing](guides/testing.md#check-helpers) for each helper's scope, commands,
logs and resource controls, and [Getting started](guides/getting-started.md) for
prerequisites. The helpers do not change global tools or install system packages.

## Try it on a supported machine

The supported checkout runs on **Ubuntu 26.04 x86_64**, with Erlang/OTP **29.1.2**, Elixir **1.20.5** (built with OTP 29), Python **3.13.15** through `uv` **0.12.6**, and Git. The demo and focused proofs don't need `bwrap` (Bubblewrap). The full independent checker does. Onboarding checks your existing Elixir/OTP installation; it won't install those tools.

The examples use the Lynx commit pinned in `mix.lock` and Lean **4.35.0** from `lean-toolchain`; [Verification](guides/verification.md#coverage-and-provenance) identifies the exact versions.

From the repository root, after selecting the required Elixir/OTP installation:

```sh
./scripts/check_quick.sh
uv run --locked python scripts/local_run.py mix run scripts/demo.exs
```

The demo uses a simulated processor and a fresh temporary journal; it does not move money. Lean and Lake stay in ignored `.local/`. The quick helper includes the setup described above. See [Getting started](guides/getting-started.md) for the full-checker setup and [Troubleshooting](guides/troubleshooting.md) if setup fails.

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

The verified core uses fixed tuples, proper lists, integers, atoms, guards, direct calls and named recursion. These are this project’s constraints, not a complete list of Lynx capabilities. A GenServer or Ecto application needs separate reasoning about processes, I/O and dependencies; translating the reducer does not verify those operations. Here, effects connect the pure core to a runtime whose processor and storage assumptions remain explicit.

The pinned Lynx README reports human design and review of the translation layer and runtime design, and limited review of agent-written proofs and Lean deserialization. See the [translation boundary](guides/verification.md#domains-and-limits) for what the checkers establish.

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

The optional [Phoenix learning and review app](https://github.com/nshkrdotcom/hold_ledger/blob/main/apps/review_web/README.md)
connects a computed payment walkthrough to Elixir laws, Lynx translation and
Lean proof evidence. Start at `/`, follow the lesson at `/start`, investigate
cases in `/lab`, or practice reviewing a changed claim at `/lens/po_a2`.
The Claim Atlas at `/atlas` registers 49 claim groups in eight curated reading
families. Case Lab compares the code result with a hypothetical What-if output
for one concrete case and saves review notes with JSON/Markdown exports.
Optional source-bound questions and follow-ups send the displayed context only
when submitted. Case checks, source readings, formal reports and human judgments
remain separate evidence. The app contacts no payment processor. The
[manual exercise](guides/interactive_review.md) also works without the app.

## Guides

The [guide index](guides/README.md) collects the lessons, check procedures,
system references and review exercises.

## License

MIT. See [LICENSE](LICENSE).
