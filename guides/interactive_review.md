# Review the meaning of a formal claim — manual exercise

You are deciding whether a proved claim actually rules out behavior people
would reject. This exercise needs neither Phoenix nor Lean. The original policy
is in [the specification](specification.md); committed expectations are in
`test/human_policy_traces_test.exs`.

## A pending authorization void

Before state: `{100, 2, 100, 1, [{1, 100, :authorized}]}`. Event:
`{:void, 1}`. Predict whether the hold should retain its capacity, release it,
or need more policy. Record your reason before revealing the transition.

<details>
<summary>Inspect the actual transition and challenge it</summary>

The next state is `{100, 2, 100, 1, [{1, 100, :voiding}]}`, result
`:voiding`, effects `[{:void, 1}]`. A remote void is pending, not confirmed.
A subsequent `{:request, 2, 100}` returns `:insufficient_amount`.

Try a hypothetical after-state with zero counters and a `:voided` entry,
result `:voided`, and **no effect**. `Spec.valid?/1` and
`Spec.effects_valid?/5` accept this particular projection, but
`Spec.exposed_entry?/3` rejects lost exposure. The same second request could
be admitted, even though the remote authorization might still exist. This
is a local counterfactual, not a remote processor observation.

Compare original `test/laws/po_b1_void_test.exs` (validity),
`po_b3_test.exs` (effects) and `po_exposure_retain_test.exs` (retention),
including their exact `requires` and `expects` expressions. The
[agentic walkthrough](agentic_verification.md#3-try-to-break-the-contract)
contains executable predicate exercises.

</details>

## Other counterexamples

A timeout of a sent authorization cannot manufacture a terminal decline:
capacity remains reserved while the outcome is uncertain. `po_b1_timeout`
ensures after-state validity, not exposure retention by itself. In an
exact-fit request, `po_a2` requires positive admission; an implementation that
always rejects may still preserve valid states.

The optional [Phoenix workbench](../apps/review_web/README.md) implements
this human reasoning loop at `/workbench`: start a P01–P08 review, read the
original source and linked map, edit the complete bounded before/event/
hypothetical-output/follow-on witness, inspect the source-derived pointwise
matrix, answer the critical Escape question, and export the saved review.
Selecting a different seed opens a separate review to preserve card scope.
Only deliberate pin and human answer submits are persisted; intermediate
drafts are not. The app uses a *single* A-derived evaluator and strict codec.
No AI call or remote
processor call is made; the former teaching-case UI, receipts and `/review`
paths are removed. C handles configured AI, not this B app.

## Evidence and limits

Keep policy, pure execution, source-claim evaluation, checked Lean report and
human judgment separate. Source/BEAM digests identify the current pointwise
evaluator; they do not constitute a Lean proof. A stale or absent independent
checker report is not proof acceptance. A candidate that passes some tested
bindings does not establish that all obligations or external processor
assumptions are satisfied. This exercise does not certify Phoenix, journaling,
processor honesty or deployment safety.
