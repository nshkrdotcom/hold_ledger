# Specification assurance

Imagine proving that every void leaves a *valid* ledger. The theorem checks out, but the program frees a hold before the payment processor confirms its cancellation. The local state can still be valid: we simply asked the theorem the wrong question.

Formal verification establishes a claim about code under stated assumptions. **Specification assurance** asks whether that claim protects the behavior people actually need. This guide explains how to find a weak or misleading contract; [Agentic verification](agentic_verification.md) puts these ideas into a worked agent-assisted task, and [Human review](human_review.md) applies them to code changes.

## A proof, a contract, and an intention

A typical function contract specifies which inputs are allowed (a *precondition*) and what the function must guarantee for them (a *postcondition*). A theorem can also express an *invariant* that must hold across transitions. For Elixir/Lynx, the corresponding law fields are `requires:` and `expects:`.

It helps to keep three questions separate, because no single green check answers all of them:

| Question | Evidence that can answer it |
|---|---|
| Does the implementation satisfy its formal claim? | A completed check of the exact theorem, dependencies and translated source, with approved assumptions |
| Does the formal claim distinguish required from forbidden behavior? | Independently justified examples, wrong-output challenges, domain checks, counterexamples, contract comparison and targeted mutations |
| Does the chosen claim cover the requirements that matter? | Examination of the requirement sources, missing cases, tradeoffs and external boundaries; a decision when sources disagree |

You need evidence for each question. Two agents can agree on the same bad reference, and a person can misread policy too. **Independence comes from how an expected outcome is justified**, not whether an agent or human wrote it.

The [Lean reference](https://lean-lang.org/doc/reference/latest/ValidatingProofs/) explains how to inspect proof dependencies and axioms when evaluating untrusted work.

## Four common contract mistakes

Here are the failure modes worth checking before spending time on tactics. Each is easy to overlook when the actual implementation happens to behave correctly.

### An impossible precondition

Imagine a law that requires both `amount > 0` and `amount <= 0`. No input qualifies, so the law can prove an arbitrary conclusion without protecting any real request. This is **vacuity**. Construct at least one concrete input satisfying the precondition, and check whether important operating cases are admitted. A witness rules out a wholly impossible domain; it does not show that the domain is large enough.

### Excluding valid inputs

A rule requiring `amount < remaining` instead of `amount <= remaining` excludes exact-fit requests. In Hold Ledger, a fresh request must be admitted when its amount equals available capacity and one slot remains. A proof restricted to strict inequality might be sound but cover fewer inputs than the intended policy. The distinguishing case is `{100, 1, 0, 0, []}` with `{:request, 11, 100}`. The expected result is `:admitted`, not `:insufficient_amount`.

### Missing guarantees

A sorting function constrained only to return a sorted list could return `[]` for every input. The output is sorted but does not preserve the input's elements. A useful sorting contract needs both ordering and **multiset preservation**, so repeated values cannot disappear. For a valid input `[2, 2, 1]`, the output `[1, 2]` should be rejected by the contract even if the actual implementation always returns `[1, 2, 2]`.

The Hold Ledger analogue is a postcondition checking `Spec.valid?/1` but omitting the required `{:void, key}` effect or the `:voiding` transition. The wrong output can still contain a valid ledger. See the [worked void example](agentic_verification.md#3-try-to-break-the-contract).

### A stronger guarantee or an incorrect reference

Not every difference is a defect in the generated claim. A postcondition that also preserves duplicate counts may strengthen an incomplete sorting reference. Conversely, a generated precondition requiring nonempty input could reject valid empty inputs. Check which side of the contract differs, then ask what the original requirement says. Even an independently written reference such as `HoldLedger.Spec` needs challenges from requirements and expected traces; it is not ground truth because its code is called `Spec`.

## Challenge each side of a contract

A strong first test of a proposed law is to show it the outputs you **do not** want to permit. A correct implementation may never produce them, so testing only its own outputs won't expose a missing guarantee.

Let `P` be the candidate precondition and `Q` its postcondition. Check whether they admit the intended inputs and reject wrong outcomes. Here, **invalid input** means outside the *intended function domain*, not merely an event that a valid-state API is designed to reject with `:malformed`.

| Case | What to ask | What a failure suggests |
|---|---|---|
| Valid input, correct output | Does `P` admit the input, and does `Q` accept the intended result? | Valid input excluded or an overly restrictive output guarantee |
| Valid input, deliberately wrong output | Does `P` admit the input but `Q` reject the bad result? | A missing or too-weak output guarantee |
| Invalid input | Does `P` exclude it when the intended domain excludes it? | A precondition that admits more than intended |
| Boundary case | What happens at equality, zero, last slot or empty list? | A domain or guarantee mistake hidden by ordinary cases |
| Temporal trace | Do multiple operations preserve identity, capacity and the required ordering of effects? | Missing cross-step or environmental assumptions |
| Deliberate mutation | Do completed checks reject a *confirmed* policy-violating implementation? | Incomplete detection, if the mutation really changed behavior and checks finished |

This separates two tasks sometimes conflated as “negative testing.” A bad output for a **valid** input tests the postcondition. An **invalid** input tests the precondition. Testing only the results of the correct implementation leaves many missing postconditions undiscovered.

The [void example](agentic_verification.md#3-try-to-break-the-contract) applies this distinction to Hold Ledger. Finite challenges can expose missing clauses; they cannot establish that a contract covers every requirement. Challenge the reference as well as the candidate.

### Which mistakes can a proof expose?

For a fixed implementation, narrowing the precondition or weakening the postcondition reduces what must be proved. If the old claim was true, the reduced claim remains true, even when it drops an important requirement. An impossible precondition removes every case. Verifier acceptance cannot detect those omissions.

Widening the precondition or strengthening the postcondition asks more of the implementation. A counterexample may reveal that the new promise is false. But the implementation might satisfy it, and a failed proof attempt alone does not decide either way. Nor is a stronger postcondition automatically good policy. Adding “output elements are unique” to “output is sorted” strengthens that postcondition, but a sort that removes duplicates can satisfy both while violating the requirement to preserve the input’s elements.

A green proof still needs review against the required behavior, whichever direction the contract changed.

## Comparison needs a reference

Logical comparison can establish how two contracts relate *if the necessary implications are proved*. In the usual refinement view, permitting more valid inputs and guaranteeing at least as much about outputs is a stronger service contract. Be careful with the word **stronger**:

- A **stronger precondition** (`P` admits fewer inputs) makes the caller's obligation harder and reduces the implementation's promise.
- A **weaker precondition** admits more inputs and asks the implementation to work in more cases.
- A **stronger postcondition** (`Q` permits fewer outputs for each allowed input) promises more about a result.
- A **weaker postcondition** permits more outputs and therefore promises less.

If both directions of the relevant implications are proved under their stated conditions, the candidate and reference contracts are equivalent for those conditions. If only one direction is proved, a one-way refinement relation may be established. A rejected implication proof establishes only that the checker did not prove it. A counterexample satisfying one condition and violating the other can establish a genuine difference. Timeouts and incomplete obligations remain unresolved.

For example, compare the admission precondition with a candidate that excludes exact fits. The following expressions compare the two predicates on an exact-fit request:

```elixir
alias HoldLedger.Spec
reference = &Spec.request_eligible?/3
candidate = fn state, key, amount ->
  reference.(state, key, amount) and amount < elem(state, 0) - elem(state, 2)
end
s = {100, 1, 0, 0, []}

reference.(s, 11, 100)  # true
candidate.(s, 11, 100)  # false

# Reference implies candidate: false for this exact-fit request.
(not reference.(s, 11, 100)) or candidate.(s, 11, 100)
# Candidate implies reference: true, since candidate includes reference.
(not candidate.(s, 11, 100)) or reference.(s, 11, 100)
```

Read `A → B` as “if A holds, B must hold.” To compare the domains, check both directions:

- `reference → candidate`: every required input is admitted. The exact-fit request disproves this implication.
- `candidate → reference`: every admitted input belongs to the reference domain. This follows from the candidate’s definition, which includes the reference predicate.

A property test samples these implications. A proof must establish them for every state, key and amount under the stated assumptions. This compares preconditions only; compare the promised results separately.

Equivalence to a reference is not equivalence to human intention. In Hold Ledger, `Spec` shares no implementation with `Ledger` and recomputes totals, but its transition branches often follow the same policy structure. Comparison can catch implementation drift; it cannot settle a policy both versions misunderstood.

## What two Verus studies found

You can skip the research and still use the exercises above. It concerns Verus for Rust, not Lynx for Elixir, so its measured rates are not claims about Hold Ledger. The useful connection is the evaluation method: combine verifier results with independently justified input/output challenges and check the reference specification itself.

**VerusEval** evaluated LLM-generated Verus contracts using semantic triviality checks, validated input/output cases and comparison with reference contracts. It studied 13,716 artifacts from 762 tasks. Of the 7,081 verifier-accepted artifacts with an executable target function, 2,995 (42.3%) completed all three semantic checks without a flag; 3,790 (53.5%) were flagged by at least one. The remaining 296 (4.2%) were unflagged but had incomplete checks.

The I/O checks used the available validated cases; some suites lacked one or more case kinds.

The 53.5% figure is **not a confirmed error rate**. A comparison flag may mean only that an implication proof failed. Among flagged artifacts, 44.7% had a counterexample or a proved triviality obligation; 55.0% were flagged by comparison alone.

The study also looked for defects in reference contracts. Its authors screened a deliberately selected set of 61 references and identified 36 *candidate* defects. That is a yield in a selected sample, not an estimate of defect prevalence in the benchmark. Repairing one reference made 10 of its 11 failing artifact comparisons provably equivalent. The result is a reason to challenge the oracle as well as the generated contract.

See [VerusEval, sections 3–6](https://arxiv.org/html/2610.26464v1) (October 2026), and its [version history](https://arxiv.org/abs/2610.26464).

**Verus-SpecGym** studied agents writing Verus specifications for 581 Codeforces programming tasks. It evaluated generated preconditions and postconditions with executable checks, using examples and adversarial cases. The authors report that one LLM-based judge missed 26% of the failures caught by their evaluator in that setting. This supports using concrete challenges alongside model review. It does not make any finite suite a completeness proof.

See the [Verus-SpecGym paper](https://arxiv.org/abs/2605.26457) (May 2026) and [code and benchmark](https://github.com/formal-verif-is-cool/verus-spec-gym).

Both studies examine Verus, not Elixir/Lynx. Their methods suggest ways to challenge a specification. Their measured rates do not apply to Hold Ledger or production deployments.

## Where assurance stops

Hold Ledger's pure laws reason about translated Elixir functions under declared hypotheses. They do not by themselves establish that the BEAM compiler and translator agree on every program, that every journal sync survives physical failure, or that a real processor honors deduplication and terminal non-resurrection. [Verification](verification.md) distinguishes full proof acceptance from supported catalog entries and development attempts. [Testing](testing.md) distinguishes runtime and fault-injection evidence. [Assurance audit](audit.md) walks through the actual trust boundaries.
