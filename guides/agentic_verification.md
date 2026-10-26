# Verify the behavior you meant

An implementation could release an authorized hold before the processor confirms its void and still leave Hold Ledger's counters consistent. The law `po_b1_void` checks that the resulting ledger is valid. Other laws are needed to rule out premature release and missing effects.

Use this workflow to move from a policy question to a checked claim. An agent can draft requirements, contracts, traces, proofs and counterexamples. Judge the work by the evidence behind each decision, whoever wrote it.

New to Lynx? Work through the [runnable crash course](formal_verification_crash_course.md) first.

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

Check the *contract*, not just the implementation. A correct implementation returning the correct value does not tell you whether its contract would permit a bad value.

Save this example as `tmp/contract_challenge.exs`. It tests two candidate postconditions for one authorized hold: validity alone, and the exact transition required by policy.

```elixir
alias HoldLedger.{Ledger, Spec}
import ExUnit.Assertions

s = {100, 2, 100, 1, [{1, 100, :authorized}]}

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
assert effects_ok.(early_release_no_effect)
refute retained.(early_release_no_effect)
```

Run it with:

```sh
uv run --locked python scripts/local_run.py mix run tmp/contract_challenge.exs
```

Validity alone accepts all three outputs. The exact-result predicate rejects both planted mistakes; its expected tuple comes from policy rather than from calling `Ledger` or `Spec`.

The existing laws already address these faults:

- `po_b3` uses `effects_valid?` to check effects against the event, result and stored identity. It rejects the lost effect, but accepts premature release when the output contains no effect.
- `po_exposure_retain` requires the issued key and amount to remain in an exposed status when the event is not release evidence, under its valid-state and lookup hypotheses. It rejects both premature-release outputs but permits the missing effect.

Together the predicates reject all three wrong outputs. These assertions check one input; the laws state the general claims.

Other useful challenges target different questions:

| Challenge | What it probes in Hold Ledger |
|---|---|
| Valid request that exactly fills amount and last slot | Whether the contract requires positive admission, not just bounded state (`PO-A2`) |
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
- **A correct input is excluded:** the precondition may be too strong. Check the promised input domain before narrowing it.
- **A reference disagrees with a stronger generated guarantee:** the reference might omit a useful promise, or the generated postcondition might demand behavior the requirements do not call for. Stronger postconditions constrain implementations; stronger preconditions constrain callers. Check the original requirement and construct a distinguishing case.
- **A proof attempt fails without a counterexample:** the mathematics may be true but the proof incomplete; the claim remains unresolved.
- **A model proof passes but a runtime test fails:** inspect translation, task lifetimes, journal ordering and external assumptions. The pure proof does not decide those questions.

Ask the agent to construct a distinguishing case or prove the relevant implication. The [research guide](specification_assurance.md#comparison-needs-a-reference) explains what contract comparisons establish and how to interpret incomplete checks.

### 6. State the result and what remains open

Name the claim and source revision, give the command and result, and note unresolved work. The example above checks concrete outputs against predicates; it does not establish a new universal proof. [Human review](human_review.md#what-to-inspect-in-the-agent-report) explains how to inspect the evidence.

## When to bring in a person

Let the agent continue gathering evidence, attempting proofs and checking already-agreed claims. Escalate when a new requirement would be selected, an input domain would shrink, an external assumption would change, the reference looks wrong, or challenges disagree. The [per-change review guide](human_review.md) gives declaration-level rules and explains what evidence could eventually justify delegating some of these decisions with less human intervention.
