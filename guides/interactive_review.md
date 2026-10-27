# Review the meaning of a formal claim

You are deciding whether a claim rules out unacceptable behavior. You do not
need to check Lean proof terms by hand. The original policy is
[the specification](specification.md); concrete expectations are committed in
`test/human_policy_traces_test.exs`.

## Try it without a server

Before `{100, 2, 100, 1, [{1, 100, :authorized}]}`, event `{:void, 1}`.
Predict: should the 100 cents and slot stay reserved, be released, or is more
policy needed? Write a reason before opening the answer.

<details>
<summary>Inspect the transition and challenge</summary>

The next state is `{100, 2, 100, 1, [{1, 100, :voiding}]}`, result `:voiding`,
effects `[{:void, 1}]`. Cancellation is pending; it is not remote confirmation.
A subsequent `{:request, 2, 100}` returns `:insufficient_amount`.

Try a hypothetical output with zero counters and a `:voided` entry, without
effects. `Spec.valid?/1` and `Spec.effects_valid?/5` both accept it for this
input; `Spec.exposed_entry?/3` rejects it. A second 100-cent request may now
be admitted while the original remote hold might exist. This is a local
counterfactual, not a verified remote execution.

Compare `po_b1_void` (validity), `po_b3` (effects) and `po_exposure_retain`
(retention), including their actual preconditions and referenced shared Lean
theorems. The full [agentic walkthrough](agentic_verification.md#3-try-to-break-the-contract)
contains executable predicate evaluations.

</details>

## Use the optional workbench

Follow [setup](getting-started.md#optional-human-review-interface), then open
`http://localhost:4000/review/void_pending`. Predict, reveal, try wrong outputs,
toggle hypothetical conclusions, follow the next request, and open original
policy/code/law/Lean sources. The switchboard compares concrete predicates;
it does not edit a theorem or run Lean.

Also inspect `timeout_unknown`: a timeout leaves capacity reserved, not declined.
`po_b1_timeout` establishes validity, not a universal retention theorem. In
`exact_fit`, compare positive eligible admission (`po_a2`) with a reducer that
rejects equality or everything: validity alone would miss the defect.

## Keep the evidence separate

Policy comes from source. Case facts are computed from this checkout. Formal
status comes only from a matching pre-existing report. Scripted or AI explanation
is a reading aid. A human decision is a separate object.

Reports are optional; absent means not supplied. Proof-only attempts are
 development evidence. Selected checked exports do not imply full catalog
acceptance. Stale sources invalidate an old acceptance claim. The app never
runs a proof command from the browser.

Choose accept for named scope, reject, needs policy, or insufficient evidence.
For acceptance/rejection, write your own rationale and select evidence IDs.
The immutable receipt binds the decision to the packet and source hashes;
its read-only page offers Markdown export. It is not a proof certificate or
permission to deploy. Old receipts remain available after source changes.

## Optional AI explanation

The default uses ASM and Codex with `gpt-6.1-sol` at low effort. Configuration is
documented in `apps/review_web/README.md`. Set
`HOLD_LEDGER_REVIEW_EXPLAINER=scripted` for offline explanations. Questions and
source excerpts go to the selected provider in inference mode. Explanations must cite IDs in the current packet,
remain visibly labeled, and never supply computed facts or a decision. Open
citations and mark misleading text; an existing citation does not prove that
a sentence follows from it. A provider failure leaves the workbench usable.

## Limits

This demo helps humans review the meaning and limits of formal claims over a
pure Elixir ledger. It does not verify Phoenix, GenServer, journal durability,
remote exactly-once behavior or processor honesty. Curated cases and anchors
are not a general parser or a completeness proof for requirements. The browser
cannot edit sources or execute arbitrary Elixir or Lean. Local single-user
practice is the supported deployment.
