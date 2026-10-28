# Reviewing changed guarantees

A change can leave the program's output untouched while removing a promise
about that output. These exercises ask you to distinguish a changed guarantee
from a changed execution. Read each question before opening its answer.

You need to know that a law's `requires` selects inputs and its `expects`
states what must follow. For a first example, try the
[payment-hold exercises](payment_hold_review_exercises.md). The changes below
are hypothetical; judge them against [the specification](specification.md).

## 1. The code still works, but the claim covers less

**Requirement:** a fresh positive request that fits the amount and hold limits
must be admitted, including an exact fit.

Consider this proposed edit to an admission claim:

| Version | Additional amount condition |
|---|---|
| Baseline | `amount <= remaining` |
| Proposal | `amount < remaining` |

Assume the other eligibility conditions hold. Available capacity is 100 cents;
a fresh request asks for 100 cents. The implementation has not changed and
returns `admitted` on both sides.

**Question:** did the unchanged observed output establish that the revised
claim preserves the admission requirement?

<details>
<summary>Answer: this particular input lost claim coverage</summary>

<p>
The input satisfies the baseline condition and fails the proposed condition.
The proposed admission claim no longer promises an outcome for this case.
</p>

<p>
That is not an observation that the implementation rejected the request.
When the precondition is false, the claim makes no promise about that input.
Its proof could pass without covering the exact-fit case.
</p>

<p>
The written policy requires exact-fit admission. The revised claim drops
that case even though the implementation still handles it correctly.
</p>

<p>
Writing A for the baseline, B for the proposal and x for this input, the
difference is <code>Pre_A(x) and not Pre_B(x)</code>: x used to qualify and now does not.
</p>

</details>

## 2. A newly permitted output was never produced

Suppose an admission claim originally requires the exact reserved entry,
counters, `admitted` result and empty effects. A proposal keeps the same
eligibility condition but promises only that the resulting state is valid.

Consider a candidate result that leaves the starting empty state unchanged
and returns `insufficient_amount`, with no effects. It is structurally coherent
and its state is valid. The actual implementation still admits the request.

**Question:** what would acceptance of this candidate by the weaker promise
show? Did you find an implementation failure?

<details>
<summary>Answer: the proposed contract permits an unwanted alternative</summary>

<p>
On an input meeting both versions' conditions, the candidate satisfies the
proposed promise and violates the baseline's exact admission promise.
The candidate was supplied to challenge the claim. It was not observed as
an implementation output.
</p>

<p>
This exposes a difference in what the claims permit. It does not show that
the current program takes advantage of the permission, nor that every other
required law also permits this candidate.
</p>

<p>
For this input x and invented output y, the difference is
<code>Pre_A(x) and Pre_B(x) and Post_B(x,y) and not Post_A(x,y)</code>.
Both versions cover x, but only the proposal permits y.
</p>

</details>

## 3. The implementation actually behaves differently

Now leave the claim fixed and change the implementation's capacity check so
that it rejects equality. For the same exact-fit input, the baseline returns
`admitted` and the proposal returns `insufficient_amount`.

**Question:** how does this differ from exercise 1?

<details>
<summary>Answer: an actual execution changed</summary>

<p>
This comparison is between computed outputs of two identified implementations.
The proposal's result contradicts the exact-fit requirement.
</p>

<p>
In exercise 1, the executions could agree while the proposed claim stopped
covering the input. In exercise 2, the challenged candidate could be permitted
without either implementation producing it.
</p>

<p>
The first three exercises share an exact-fit input, but establish different
facts. In your review, name which fact you found and identify the versions
you compared. One execution cannot establish that the versions agree on
every other input.
</p>

</details>

## 4. A helper changed, but the law text did not

The law still calls `request_eligible?`. The helper's body changes from
including exact fits to excluding them. The law declaration itself has no diff.

**Question:** is it enough to review only the law declaration?

<details>
<summary>Answer: follow the definitions that give the claim its meaning</summary>

<p>
The law calls the helper, so changing the helper changes which inputs qualify.
The unchanged declaration now promises admission on fewer inputs.
</p>

<p>
Read the affected helper in both versions and challenge the relevant boundary.
Unchanged law text does not establish unchanged meaning. The same principle
applies to a Lean theorem that references a changed definition.
</p>

<p>
An operator edit needs its surrounding expression. For example, <code>&lt;</code> inside
a negation has a different effect from <code>&lt;</code> alone. Read both definitions and
test the boundary before deciding which cases were added or lost.
</p>

</details>

## 5. The precondition became weaker

A proposal lets a claim apply to more inputs while preserving its promise.
Someone calls this “erosion because the precondition changed.”

**Question:** is that conclusion justified?

<details>
<summary>Answer: a weaker precondition is not automatically erosion</summary>

<p>
Here the promise now applies to more inputs, so the implementation has more
to satisfy. Excluding inputs or permitting additional outputs would reduce
its obligations. Check which side of the contract changed.
</p>

<p>
For an extreme example, impossible conditions let a claim hold vacuously.
An input satisfying the conditions rules out total vacuity, but does not show
that the claim covers every important input.
</p>

<p>
Use the policy to decide whether the claim should cover the added inputs.
</p>

</details>

## 6. Search found no distinction

A bounded search checks 41 cases and finds no difference. Separately, a required
obligation has disappeared from the proposed inventory.

**Question:** can the search settle the review?

<details>
<summary>Answer: the missing obligation still needs review</summary>

<p>
The search compared only its 41 cases. A removed obligation might protect
behavior none of those cases exercises. If a claim is absent or the tool
cannot evaluate it, there is no comparison result for that claim.
</p>

<p>
Compare inventories against the prior required obligations, not just two files
edited together. A removed obligation, changed helper or changed assumption
can require attention without a machine-found counterexample.
</p>

<p>
Preserve the search bounds and missing evidence in the conclusion. “No
example found within these bounds” is an honest result.
</p>

</details>

## A short review note

A useful note identifies the policy, exact source pair, affected claim, concrete
input and separate actual/candidate outputs. It then explains the human judgment
and names anything unresolved. For example:

> Exact-fit admission remains required. With 100 cents available, the fresh
> 100-cent request meets the baseline admission condition and fails the proposed
> condition. Both actual executions admit it. The proposed claim loses coverage
> for this required case; repair the condition. This example does not assess
> other changed claims or establish full formal acceptance.

Continue with [Reading review evidence](reading_review_evidence.md) and
[Human review](human_review.md) for source, report and assumption checks.

The optional [change workspace](../apps/review_web/README.md) computes these
three kinds of comparison for supported cases. For the logic behind contract
comparison, see [Specification assurance](specification_assurance.md#comparison-needs-a-reference).
