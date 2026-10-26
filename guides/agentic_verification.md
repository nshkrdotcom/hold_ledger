# Agentic verification

Suppose an agent rewrites the ledger so a void request frees capacity immediately. It might still prove that the resulting counters are internally consistent. The proof is valid **for that claim**; the change is wrong because the processor may still hold the money.

We'll follow that example from a requirement to a challenged contract and proof evidence. An agent can gather policy, write code, propose laws, generate counterexamples and attempt proofs. The question is not who typed the theorem. It's **who has authority to decide what the theorem must promise**, and what evidence supports that decision. If you've never seen a Lynx law, start with the [crash course](formal_verification_crash_course.md).

## Who decides what?

| Moment | Agent's work | Evidence or decision needed |
|---|---|---|
| Find the requirement | Gather the specification, traces and competing interpretations | A person resolves missing or conflicting policy; an agreed requirement can be reused without asking again |
| Draft the claim | Propose `requires`, `expects`, definitions and exact examples | Review the domain, guarantees and any new assumption before calling it the accepted contract |
| Challenge it | Produce admissible inputs, deliberately wrong outputs and mutants | Check expected behavior against policy, not just against the implementation or `Spec` |
| Implement and prove | Write code, tests, lemmas and tactics under an agreed contract | Lean checks a theorem; it does **not** judge policy or remote-service truth |
| Deliver the change | Show the diff, source identity, commands, results and open questions | A reviewer decides whether any semantic or trust-boundary change is authorized |

You don't need a new human decision for every keystroke. Under an already agreed policy, an agent can repair a bug and run the checks. Stop when a new release rule, narrower domain, different reference meaning or new remote assumption would be accepted. [Human review](human_review.md) gives the detailed escalation rule.

A few proof labels appear below. `po_b1_void` checks that the void transition preserves ledger validity; `po_b3` constrains emitted effects; `po_exposure_retain` requires capacity to remain represented when a local void lacks release evidence. They are individual **law groups** in `verification/laws.json`, not magic assurances about the whole system. The [law catalog](verification.md#law-catalog) names the others.

## The loop

### 1. Find the requirement and its boundary

Start with one behavior, not “verify the codebase.” For Hold Ledger, ask: **When may an authorized hold release capacity?**

Read [the policy](specification.md#uncertain-outcomes-and-identities) before the code. A local void request moves an `:authorized` hold to `:voiding`, retains its amount and slot, and emits a remote void intent. Only a trusted `{:void_confirmed, key}` releases that capacity.

Ask the agent to collect the relevant source: `guides/specification.md`, `lib/hold_ledger/ledger.ex`, `lib/hold_ledger/spec.ex`, the applicable `test/laws/*.exs` and ordinary traces. Have it distinguish the local request, the processor response and the journaled confirmation.

The requirement needs a basis outside the proof: written policy, expected outcomes justified against that policy, or an explicit decision to change it. If sources disagree, identify the conflict instead of choosing whichever interpretation verifies.

### 2. Compare candidate contracts

Have the agent write each candidate in plain English before writing Lean. For the void example:

| Candidate | What it permits | Decision |
|---|---|---|
| “The returned state is valid.” | Immediate release with consistent counters | Too weak for this requirement |
| “Voiding an authorized entry keeps its amount and slot, records `:voiding`, and emits `{:void, key}`.” | The required local transition | Covers the local obligation |
| “A local void request means the processor has already removed the remote authorization.” | A claim about an external service | Unsupported; outside the pure reducer |

A contract consists of its conclusion **and** the inputs under which that conclusion is required. Inspect every referenced predicate; changing a helper's definition can change a theorem's meaning while leaving its statement untouched. `Spec.valid?/1` excludes malformed ledger states, but `Ledger.step/2` accepts arbitrary event terms on a valid state and specifies `:malformed` results for malformed events. Do not exclude those events just because they make a proof harder.

### 3. Try to break the contract

First challenge the *contract* itself. A correct implementation returning the correct value does not tell you whether its contract would permit a bad value.

Save this example as `tmp/contract_challenge.exs`. It tests two candidate postconditions for one authorized hold: validity alone, and the exact transition required by policy.

```elixir
alias HoldLedger.{Ledger, Spec}
import ExUnit.Assertions

s = {100, 2, 100, 1, [{1, 100, :authorized}]}

# Check the input assumptions before testing candidate outputs.
assert Spec.valid?(s)
assert Spec.lookup(elem(s, 4), 1) === {:ok, {1, 100, :authorized}}
refute Spec.release_evidence?({:void, 1}, 1)

# Required outcome of Ledger.step(s, {:void, 1}):
correct = {{100, 2, 100, 1, [{1, 100, :voiding}]},
           :voiding, [{:void, 1}]}

# Wrong: frees capacity before terminal confirmation.
early_release = {{100, 2, 0, 0, [{1, 100, :voided}]},
                 :voided, [{:void, 1}]}

# Wrong: records the pending void but omits the remote intent.
lost_effect = {{100, 2, 100, 1, [{1, 100, :voiding}]},
               :voiding, []}

weak = fn {state, _result, _effects} -> Spec.valid?(state) end
required = fn output -> output === correct end

assert Ledger.step(s, {:void, 1}) === correct
assert Enum.all?([correct, early_release, lost_effect], weak)
assert required.(correct)
refute required.(early_release)
refute required.(lost_effect)

# Predicates used by the maintained PO-B3 and PO-EXPOSURE laws:
effects_ok = fn {state, result, effects} ->
  Spec.effects_valid?(s, {:void, 1}, state, result, effects)
end
retained = fn {state, _result, _effects} ->
  Spec.exposed_entry?(state, 1, 100)
end

assert effects_ok.(correct) and retained.(correct)
refute effects_ok.(early_release)
refute retained.(early_release)
refute effects_ok.(lost_effect)
assert retained.(lost_effect)

# Without the effect, premature release passes only the effects check.
early_release_no_effect = put_elem(early_release, 2, [])
assert weak.(early_release_no_effect)
refute required.(early_release_no_effect)
assert effects_ok.(early_release_no_effect)
refute retained.(early_release_no_effect)
```

Run it with:

```sh
uv run --locked python scripts/local_run.py mix run tmp/contract_challenge.exs
```

The input satisfies the retention law’s assumptions: it is valid, key `1` and amount `100` are integers, the matching entry is `:authorized`, and a local void request is not release evidence. The predicates distinguish these outputs:

| Output | `valid?` | `effects_valid?` (PO-B3) | `exposed_entry?` (PO-EXPOSURE) |
|---|---|---|---|
| `correct` | true | true | true |
| `early_release` | true | false | false |
| `lost_effect` | true | false | true |
| `early_release_no_effect` | true | true | false |

`effects_valid?` rejects `early_release` because a `:voided` result must carry no effects. Removing the effect makes that check pass, even though capacity was released too early. The retention predicate catches that mistake. Conversely, retention alone accepts `lost_effect`.

These are predicates from the existing `po_b3` and `po_exposure_retain` laws. The assertions check their conclusions on one input; they do not establish new universal proofs. The exact-result predicate rejects each wrong output using the tuple chosen from policy.

The `early_release` and `lost_effect` outputs match `mutants/10_premature_void_release` and `mutants/07_void_effect`, respectively. The [mutation instructions](testing.md#deliberate-mutations) explain how to run those isolated examples.

Other useful challenges target different questions:

| Challenge | What it probes in Hold Ledger |
|---|---|
| Valid request that exactly fills amount and last slot | Whether the contract requires positive admission, not just bounded state (`PO-A2`) |
| Invalid ledger `{100, 2, 0, 1, [{1, 100, :authorized}]}` | Whether `Spec.valid?` excludes a state whose amount counter disagrees with its entries |
| Invalid request amount `0` on a valid state | Whether the specified result is `:malformed`; it is not an invalid *ledger state* |
| Timeout followed by another request | Whether `:unknown` retains capacity |
| Void, delayed confirmation, then another request | Whether capacity is held until confirmation and released once |
| Duplicate/retry with an existing key | Whether identity and stored amount are preserved |
| Mutation that releases capacity at local void | Whether the planted early release violates the retention conclusion (`mutants/10_premature_void_release`) |

Ask the agent for boundary and temporal traces. For each expected result, cite the relevant clause in `guides/specification.md` before consulting `Spec.expected_step/2`. If the policy does not settle the case, record the requirement question. [Specification assurance](specification_assurance.md#challenge-each-side-of-a-contract) explains how these checks complement one another.

### 4. Implement and prove without moving the target

Once the contract is selected, the agent can implement, repair tactics, add lemmas and run the appropriate checks. It can also propose a different contract, but that proposal must be separate from the proof repair. Do not change `Ledger` and `Spec` together just to make their results agree.

Use [Verification](verification.md) to select the applicable laws and distinguish a development proof attempt from full acceptance.

Run the existing policy traces with:

```sh
uv run --locked python scripts/local_run.py mix test test/human_policy_traces_test.exs --exclude laws
```

The [Testing guide](testing.md#deliberate-mutations) covers isolated mutant runs and how to interpret their results.

### 5. Resolve disagreements

When the code, contract, expected trace and reference disagree, identify the exact disagreement first.

- **A verified implementation admits a wrong output:** the contract may be missing a guarantee. Try a wrong-output pair and inspect the postcondition.
- **A required input is excluded:** the precondition may be too strong. Compare it with the promised input domain and widen it if the requirement covers the case.
- **A reference disagrees with a stronger generated guarantee:** the reference might omit a useful promise, or the generated postcondition might demand behavior the requirements do not call for. Stronger postconditions constrain implementations; stronger preconditions constrain callers. Check the original requirement and construct a distinguishing case.
- **A proof attempt fails without a counterexample:** the mathematics may be true but the proof incomplete; the claim remains unresolved.
- **A model proof passes but a runtime test fails:** inspect translation, task lifetimes, journal ordering and external assumptions. The pure proof does not decide those questions.

Ask the agent to construct a distinguishing case or prove the relevant implication. [Specification assurance](specification_assurance.md#comparison-needs-a-reference) explains what contract comparisons establish and how to interpret incomplete checks.

### 6. State the result and what remains open

Name the claim and source revision, give the command and result, and note unresolved work. The example above checks concrete outputs against predicates; it does not establish a new universal proof. [Human review](human_review.md#what-to-inspect-in-the-agent-report) explains how to inspect the evidence.

## Work through a complete agent task

This is a **teaching scenario**, not a transcript of a tool run and not a report of a new checked theorem. It uses the real policy, law names and mutation supplied in this repository. You can give the first prompt to your coding agent, then compare its work with the guide. Keep the source intact; use the mutation runner's isolated-copy workflow for experiments.

### Give the agent a bounded request

```text
Investigate mutants/10_premature_void_release as a specification challenge.
The agreed policy is in guides/specification.md: an authorized local void
must keep capacity and issue a void intent until trusted confirmation.

Before modifying code, return:
1. The policy sentence and the files that support it.
2. The valid starting state and required output for a local void.
3. A weak candidate claim, the required stronger claim, and a deliberately
   wrong output that distinguishes them.
4. The existing laws and witnesses that address this case.
5. The smallest focused commands to check the existing baseline.

Do not weaken any existing law, change Spec to match Ledger, add axioms,
claim a failed tactic is a counterexample, or edit the live reducer.
Report any missing or conflicting requirement rather than selecting one.
```

The following illustrative exchange uses the exact state from the contract challenge.

**Agent:** “The policy in Specification, under ‘Uncertain outcomes and identities,’ requires an authorized void to retain capacity and emit a void intent. For this input, the required output is:”

```elixir
s = {100, 2, 100, 1, [{1, 100, :authorized}]}
# required Ledger.step(s, {:void, 1}):
{{100, 2, 100, 1, [{1, 100, :voiding}]}, :voiding, [{:void, 1}]}
```

**Agent:** “Requiring the resulting state to satisfy `Spec.valid?` would check that the counters agree with the entries.”

**Reviewer:** “Would that permit freeing the hold before confirmation? Show a wrong output that satisfies that claim.”

**Agent:** “Yes. The `early_release` output above sets the entry to `:voided` and both counters to zero. It is internally valid but violates retention. The `lost_effect` output also passes validity while omitting the void intent. The exact transition rejects both. Adding release evidence as a precondition would instead exclude the local void we need to cover.”

These three proposed contracts can now be classified **before** looking at any proof:

| Proposed claim | What would still pass? | Judgment |
|---|---|---|
| After `{:void, 1}`, `Spec.valid?` holds | Consistent counters after immediate release | Too weak: a valid state can violate retained capacity |
| An authorized hold enters `:voiding`, keeps amount and slot, and emits `{:void, key}` | The intended local transition; no claim of remote completion | Suitable local requirement, provided its precondition covers all intended authorized holds |
| Same as the previous claim, but require `Spec.release_evidence?({:void, key}, key)` | No ordinary local void satisfies the new condition | Vacuous for this case: the precondition assumes release evidence that a local request lacks |

The second claim is not the entire remote guarantee. It must be joined with the confirmation/coupled-model obligations and explicit assumptions about the processor. The agent should point to those boundaries instead of claiming a single law proves remote correctness.

### Challenge the result, then run the existing checks

Have the agent use the executable `tmp/contract_challenge.exs` example from [step 3](#3-try-to-break-the-contract) as its local test: the weak validity predicate accepts incorrect `early_release` and `lost_effect` results, while the chosen guarantees distinguish them. If the agent offers a simpler claim, ask for an *incorrect output for a valid input* that it still accepts but the original contract rejects. Finding one exposes a lost guarantee; failing to find one does not establish that the contracts are equivalent.

The maintained policy traces can be checked without changing production source:

```sh
uv run --locked python scripts/local_run.py mix test test/human_policy_traces_test.exs --exclude laws
```

To experiment with the deliberate mutation, first inspect its patch and witness at `mutants/10_premature_void_release/`. Then use [Testing](testing.md#deliberate-mutations) to validate patches and, when the proof toolchain is ready, run the isolated native mutation experiment. A proof compilation failure, timeout or tactic error is **inconclusive** unless a valid counterexample has been established. The mutation runner's reports describe what actually completed.

### Ask for a reviewable report

The exchange ends with a report and a review decision. This illustrative report describes a contract review before executing checks; its `not run` entries leave that work visible.

```text
Requirement: An authorized local void retains its amount and slot until
trusted confirmation; its transition emits {:void, key}.
Policy source: guides/specification.md, "Uncertain outcomes and identities"
Claim delta: None to maintained laws. Reject validity alone as a substitute
for the required transition: it permits early release and a missing effect.
Changed files: None.
Review tier: Contract review (Tier 1 meaning/scope review); no proof repair.
Challenge: Starting from {100, 2, 100, 1, [{1, 100, :authorized}]}, both
 early_release and lost_effect satisfy validity but violate the exact output.
Existing coverage: po_b1_void checks validity; po_b3 checks effects;
 po_exposure_retain checks retention. The policy traces exercise pending voids.
Ordinary checks: Not run. Next commands:
 uv run --locked python scripts/local_run.py mix run tmp/contract_challenge.exs
 uv run --locked python scripts/local_run.py mix test test/human_policy_traces_test.exs --exclude laws
Formal checks: Not run; no proof or full-acceptance result claimed.
External assumptions: Processor outcomes are truthful and authenticated;
 terminal void confirmation permanently fences delayed authorization.
Unresolved: Execute the challenge and policy traces. Native mutation and
 formal checks remain unexecuted; this review establishes no new theorem.
```

**Reviewer:** “Keep the existing retention and effect requirements. The proposed validity-only replacement loses both guarantees. Run the listed checks and report their actual results. No new policy decision is needed; a failure should be investigated against the existing contract.”

The decision allows work to continue under agreed policy without treating the contract review as proof acceptance. For a report after execution, replace each `not run` entry with the exact command, result and log or report path. Include source hashes with formal evidence. [Human review](human_review.md#what-to-inspect-in-the-agent-report) gives the general report format.

The reviewer checks the actual diff and evidence; the report is not an authority. A sample response that says **“proof-only change, no claim delta”** while changing a referenced definition is misleading even if the theorem signatures are unchanged. Try identifying this failure in [Human review, exercise E](human_review.md#practice-on-seven-proposed-changes).

### A second request: repair a failed proof without changing policy

```text
The focused proof attempt for po_b1_timeout failed. Diagnose the first
unresolved goal and run its existing witness/property. Keep the maintained
requires/ expects clauses and called Spec definitions unchanged. You may
propose proof-body changes or helper lemmas only after checking whether those
changes alter any theorem statement, assumption, import or trusted definition.
If you find a concrete counterexample, show an input satisfying the current
precondition and violating the conclusion; do not quietly modify the law.
If no counterexample is found, report the proof as unresolved, with the goal,
command, diagnostic and limits of the tests you ran.
```

This is a useful default for proof repair because it prevents a common failure: changing the contract until an implementation passes it. If the agent proposes a different contract, review that proposal separately as a change in meaning. Don't treat it as a tactic repair.

### What would require a human here?

Repairing premature release under the existing rule doesn't require inventing a new policy. But a request to “release every void after 24 hours, even without confirmation” directly conflicts with the requirement to retain capacity while external authorization is possible. The agent should show the conflicting trace and the exposure consequence, then ask the authorized person to decide. It must not change the specification or introduce a processor guarantee to make the proof easier.

You can learn this workflow without running a full prover. If you do run the experiments, preserve the logs and source identity, and distinguish a concrete local check from universal proof acceptance.

## When to bring in a person

The agent can continue gathering evidence, attempting proofs and checking agreed requirements. Bring the decision back to a person when a new requirement is needed, an important input domain may shrink, an external assumption changes, the reference contradicts independently justified behavior, or challenges expose competing policies. Record the question and the evidence before asking for a decision. The [per-change review guide](human_review.md) gives declaration-level rules and explains how evaluation could eventually justify delegating narrower classes of decisions.
