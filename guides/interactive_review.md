# Practice reviewing a formal claim

Can a proved claim still permit behavior you would reject? These exercises
let you try that question without installing Phoenix or Lean. Choose the
part you want to practise; you do not need to read all three.

| You want to practise… | Exercise |
|---|---|
| Deciding whether an outcome meets the payment policy | [Eight payment-hold cases](payment_hold_review_exercises.md), starting with a correct local cancellation |
| Spotting a promise lost in a proposed edit | [Reviewing changed guarantees](reviewing_changed_guarantees.md), comparing excluded inputs, permitted outputs and actual executions |
| Deciding what a passing or incomplete check establishes | [Reading review evidence](reading_review_evidence.md), using sample reports and missing evidence |

Read each question and form your answer before opening the explanation.
Use [the specification](specification.md) to justify the required behavior.
If you want the concepts first, read [Specification assurance](specification_assurance.md).

## A pending authorization void

For a worked review, start at [P01](payment_hold_review_exercises.md#5-cancel-an-approved-hold-p01).
An authorized hold receives a local cancellation request. Compare the required
transition with an invented result that frees capacity immediately, then
predict which predicates accept it. Repair one part and check what remains wrong.

The [executable contract challenge](agentic_verification.md#3-try-to-break-the-contract)
checks the same predicates in Elixir. Continue with that walkthrough if you
want to work through a change with a coding agent. For classifying a real
diff and reporting its evidence, use [Human review](human_review.md).

## Use the optional workbench

The [Phoenix workbench](../apps/review_web/README.md) lets you edit the examples,
inspect source, compare claim results and save your judgment. Its P01–P08
labels match the payment exercises. It calculates individual examples and
can display a separately supplied proof report. Read that report to find
which proofs were checked.
A proposed alternative is an invented output, not an observed processor result.

## Evidence and limits

A review conclusion records your judgment for the cases and sources you
examined. A concrete check evaluates those cases; formal acceptance requires
the matching evidence defined in [Verification](verification.md). Processor
truthfulness and storage durability still need evidence outside the pure model.
