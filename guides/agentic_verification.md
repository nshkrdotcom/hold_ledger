# Agentic verification

Suppose an agent rewrites the ledger so a void request frees capacity immediately. It might still prove that the resulting counters are internally consistent. The proof is valid **for that claim**; the change is wrong because the processor may still hold the money.

Follow that void request from a requirement to a challenged contract and a review decision. You need Elixir and testing experience; the exercises use executable predicates and require no Lean tactics. The [crash course](formal_verification_crash_course.md) is a separate path for writing and running proofs.

## Read the contract and the state

A Lynx law has a precondition (`requires:`) and a postcondition (`expects:`). The precondition selects inputs; the postcondition states what the function must return for them. A **witness** is an input satisfying the precondition. A **counterexample** also makes the postcondition false. An impossible precondition makes a claim **vacuous**: the proof has no qualifying inputs to cover.

For the exercise, an `:authorized` hold has processor approval and still consumes capacity. A local void moves it to `:voiding`, where it stays held while confirmation is pending. Trusted confirmation makes it `:voided` and releases capacity. The [lifecycle diagram](../README.md#the-ledger-in-a-few-steps) places these states in the full request flow.

## Read the evidence before accepting a result

| Result in a report | What to inspect |
|---|---|
| Test or property pass | The executed inputs and assertions; a correct output may still satisfy a weak contract |
| Selected proof pass | The exact statement, its hypotheses and the source checked |
| Full proof acceptance | The required inventory, fresh exports, checker results and source identity |

[Human review](human_review.md#read-green-precisely) defines these evidence levels, including catalog status and CI results. Keep the result's scope attached to it when discussing a policy decision.

## Who decides what?

- **Continue under agreed policy.** The agent can gather evidence, challenge contracts, repair code and attempt proofs.
- **Review changed meaning.** A reviewer checks changes to claims, definitions, domains and trusted assumptions against the agreed requirements.
- **Resolve disputed requirements.** An authorized person decides missing policy and risk tradeoffs. If the reference contradicts independently justified behavior, bring back that discrepancy before changing the contract.

Use this decision flow when an agent reaches an uncertain case:

```text
Is the required behavior covered by agreed policy?
  No, or sources conflict -> Gather a distinguishing case; ask the policy owner.
  Yes -> Does the diff change a claim, domain, Spec or trusted assumption?
           Yes -> Review its meaning against the policy before accepting it.
           No  -> Continue the repair and run the relevant checks.

Did a check fail?
  Concrete counterexample -> Compare it with policy; repair the demonstrated error.
  No counterexample       -> Report the unresolved claim and investigate the goal.
```

A failed tactic does not by itself require a policy decision. Use the [responsibility table](human_review.md#what-to-delegate-and-what-to-decide) and [diff tiers](human_review.md#classify-the-diff) to review the resulting change.

## Find the named laws

A few proof labels appear below. `po_b1_void` checks that the void transition preserves ledger validity; `po_b3` constrains emitted effects; `po_exposure_retain` requires capacity to remain represented when a local void lacks release evidence. Each is a **law group**, a unit selected by the verification runner, registered in `verification/laws.json`. Uppercase labels such as PO-EXPOSURE name obligations; lowercase slugs select groups. Report filenames are chosen by the caller. The [law catalog](verification.md#law-catalog) names the others.

## The loop

### 1. Find the requirement and its boundary

Start with one behavior, not “verify the codebase.” For Hold Ledger, ask: **When may an authorized hold release capacity?**

Read [the policy](specification.md#uncertain-outcomes-and-identities) before the code. A local void request moves an `:authorized` hold to `:voiding`, retains its amount and slot, and emits a remote void intent. Only a trusted `{:void_confirmed, key}` releases that capacity.

Ask the agent to collect the relevant source: `guides/specification.md`, `lib/hold_ledger/ledger.ex`, `lib/hold_ledger/spec.ex`, the applicable `test/laws/*.exs` and ordinary traces. Have it distinguish the local request, the processor response and the journaled confirmation.

For this example, `guides/specification.md` defines the required behavior. When adopting it for a service, identify the person accountable for approving its release rules and processor assumptions. That person owns the policy decision; the tests and proofs supply evidence about the chosen rules.

The repository's `AGENTS.md` gives agents this concrete constraint:

> An uncertain hold still consumes capacity. Retries reuse identity and amount.
> Transport acknowledgments do not authorize payments.

That instruction constrains implementation work. Justify each expected output from the policy and record any authorized change to it. If the reference implementation conflicts with independently justified behavior, present the conflicting trace to the policy owner before changing the contract.

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

These are predicates from the existing `po_b3` and `po_exposure_retain` laws. The assertions compare their conclusions on one input. The exact-result predicate rejects each wrong output using the tuple chosen from policy.

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

The [predicate challenge](reading_deeper_proofs.md#challenge-a-missing-accounting-clause) shows how removing one accounting check changes which states `Spec.valid?` would accept.

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

Name the claim and source revision, give the command and result, and note unresolved work. For the example above, report the concrete predicate checks and their inputs. [Human review](human_review.md#what-to-inspect-in-the-agent-report) explains how to inspect the evidence.

## Work through a complete agent task

This **illustrative exchange** uses the repository’s policy, laws and premature-void mutation. It is scripted; command results remain unexecuted within the scenario. Give the bounded prompt to an agent and compare its reasoning with the exchange. Use the mutation runner’s isolated copies for experiments.

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
Policy: guides/specification.md, "Uncertain outcomes and identities": an
 authorized local void retains capacity until trusted confirmation permits
 release; its transition emits {:void, key}.
Claim delta: None to maintained laws. Reject validity alone as a substitute
 for the required transition: it permits early release and a missing effect.
Review tier: Not applicable (no diff).
Changed files: None.
Challenge evidence: From {100, 2, 100, 1, [{1, 100, :authorized}]}, both
 early_release and lost_effect satisfy validity but violate the exact output.
 po_b1_void checks validity; po_b3 checks effects; po_exposure_retain checks
 retention. The policy traces exercise pending voids.
Ordinary checks: Not run. Next commands:
 uv run --locked python scripts/local_run.py mix run tmp/contract_challenge.exs
 uv run --locked python scripts/local_run.py mix test test/human_policy_traces_test.exs --exclude laws
Formal evidence: Not run; no proof or full-acceptance result claimed.
Trusted assumptions: Processor outcomes are truthful and authenticated;
 terminal void confirmation permanently fences delayed authorization.
Unresolved: Execute the challenge and policy traces. Native mutation and
 formal checks remain unexecuted; this review establishes no new theorem.
```

**Reviewer:** “Keep the existing retention and effect requirements. The proposed validity-only replacement loses both guarantees. Run the listed checks and report their actual results. No new policy decision is needed; a failure should be investigated against the existing contract.”

The decision allows work to continue under agreed policy without treating the contract review as proof acceptance. For a report after execution, replace each `not run` entry with the exact command, result and log or report path. Include source hashes with formal evidence. [Human review](human_review.md#what-to-inspect-in-the-agent-report) gives the general report format.

### Check a report against its diff

Now suppose an agent submits this report excerpt:

```text
Claim delta: None; the law files are untouched.
Review tier: Tier 2, helper refactor.
Changed files: lib/hold_ledger/spec.ex
```

Its proposed diff keeps the lookup and adds one status:

```diff
   def exposed_entry?({_, _, _, _, entries}, key, amount) do
     case lookup(entries, key) do
-      {:ok, {^key, ^amount, status}} -> status in [:sent, :unknown, :authorized, :voiding]
+      {:ok, {^key, ^amount, status}} -> status in [:sent, :unknown, :authorized, :voiding, :voided]
       _ -> false
     end
   end
```

Before opening the answer, classify the diff and find a valid state for which this predicate changes its result. Does an entry's identity remaining in the ledger mean its capacity remains held? Explain what a retention conclusion would lose even though its law file is untouched.

<details>
<summary>Review decision — open after checking the diff</summary>

Consider `{100, 2, 0, 0, [{1, 100, :voided}]}`, key `1` and amount `100`. The state is valid: a voided entry remains remembered but consumes no capacity. The original predicate returns `false`; the proposed definition returns `true`.

**Reviewer:** “This is Tier 1: a changed Spec definition. A conclusion using this predicate could now accept a terminal entry with no retained capacity. The unchanged law file does not preserve that guarantee. Keep the original status set and investigate any proof failure under the existing contract.”

The report's label hid a changed guarantee. Following the predicate to a concrete state reveals it. [Human review](human_review.md#practice-on-seven-proposed-changes) provides further exercises with different ways to change a claim's meaning.

</details>

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

Preserve the logs and source identity when you run the experiments so the reviewer can reproduce the result.

## When to bring in a person

Use the [responsibility table](human_review.md#what-to-delegate-and-what-to-decide) and [diff classification rules](human_review.md#classify-the-diff) when a challenge exposes a disputed decision. Bring the specific conflict, distinguishing trace and relevant evidence to the reviewer; work covered by the agreed policy can continue.
