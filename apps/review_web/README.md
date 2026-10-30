<p align="center">
  <img src="assets/review_web.svg" alt="Hold Ledger · Verification" width="200" height="200">
</p>

# Hold Ledger · Verification

[![GitHub](https://img.shields.io/badge/GitHub-hold__ledger-181717?logo=github)](https://github.com/nshkrdotcom/hold_ledger)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

Hold Ledger Review Web is an interactive guide to formal verification with
[Lynx](https://github.com/josevalim/lynx) and Lean. Follow a payment hold,
inspect the Elixir laws that describe its behavior, and review what the proofs
establish. The app runs locally as a separate Phoenix project inside
[Hold Ledger](https://github.com/nshkrdotcom/hold_ledger).

A processor can approve a payment authorization even when its reply never
reaches the ledger. The 100¢ example shows why the ledger keeps that amount
reserved after a timeout. Case Lab lets you try events and compare the code's
result with an output you propose.

The app also asks whether a claim requires the behavior you need. A ledger
that refuses every request can still keep its totals consistent. The exact-fit
review shows how a small change to a claim can leave an important requirement
uncovered. You can start without knowing Lean, or go directly to the source
and verification evidence.

## Run locally

Use the Elixir/OTP versions in
[Getting started](https://github.com/nshkrdotcom/hold_ledger/blob/main/guides/getting-started.md).
That guide also covers Python and `uv`. Onboarding checks your existing
Elixir/OTP installation and provisions the pinned local proof tools.
From the repository root:

```sh
uv sync --locked
uv run --locked python scripts/onboard.py --profile runtime --provision
uv run --locked python scripts/local_run.py --cwd apps/review_web mix deps.get --check-locked
uv run --locked python scripts/local_run.py --cwd apps/review_web mix assets.build
uv run --locked python scripts/local_run.py --cwd apps/review_web mix phx.server
```

Open [localhost:4000](http://localhost:4000) and choose **Follow a payment
hold**. Amounts are integer cents: `100` means $1.00. The examples model one
account and do not contact a payment processor.

| You want to… | Start here |
|---|---|
| Learn through one concrete example | [Follow a payment hold](http://localhost:4000/start) |
| Connect familiar Elixir to Lean | [Elixir to Lean](http://localhost:4000/translation) |
| Understand how the project fits together | [Reading map](http://localhost:4000/how-it-fits) |
| Experiment with a claim | [Case Lab](http://localhost:4000/lab) |
| Review a proposed claim change | [Guided practice](http://localhost:4000/lens/po_a2) |

## Follow a hold through a missing reply

The [walkthrough](http://localhost:4000/start) starts with an empty account,
a 100¢ amount limit, and two hold slots. An authorization hold reserves an
amount for possible later capture; capture and settlement are outside this
model. A new request must fit both the available amount and a free slot.

Select a moment to compare the account before and after its event. The
walkthrough uses the ledger's transitions, so the state, result, and requested
work describe the same case.

| Moment | What happens | Amount held | Free slots |
|---|---|---|---|
| Empty account | All 100¢ and both slots are available. | 0¢ | 2 |
| Request 11 asks for 100¢ | The exact fit is admitted and reserved locally. | 100¢ | 1 |
| Dispatch | The ledger records the hold as sent and requests authorization. | 100¢ | 1 |
| Timeout | The reply is missing, so the ledger marks the outcome unknown. | 100¢ | 1 |
| Request 12 asks for another 100¢ | The request is refused because no amount is available. | 100¢ | 1 |

The processor may have approved the first authorization before its reply was
lost. A timeout tells the ledger that the reply is missing, not that the
request failed. Keeping the hold counted prevents the second request from
reusing that capacity.

Choose **Open this moment in Case Lab** to create a review session containing
the selected history. Continue from that state, try another event, or propose
a different result. Optional source details, background reading, and a
self-check are available as you go.

## Follow the Elixir-to-Lean connection

[Elixir to Lean](http://localhost:4000/translation) uses the exact-fit admission
claim, PO-A2, to connect the Elixir law, its supporting source, generated Lean,
and the proof statement. The example has 100¢ available, a free slot, and a
new request for all 100¢.

The pieces have different jobs:

1. **Ledger computes the result.** A pure transition returns the next state,
   a result, and requested effects. The runtime carries out that outside work.
2. **Spec describes the expected behavior independently.** Its eligibility
   predicate checks that the state, request ID, amount, and capacity are suitable.
3. **The Elixir law states the claim.** `requires` selects the inputs it covers.
   `expects` states what must hold for those inputs. PO-A2 requires the exact
   admitted output, including the new reserved entry and updated counters.
4. **Lynx translates supported compiled Elixir into Lean.** It produces
   definitions and theorem statements from the source and laws.
5. **Lean checks the supplied proof.** The proof establishes that statement
   under its assumptions. Matching verification reports record which source
   and scope were checked.

Generated material is available when it matches the reviewed source.
Missing or stale material is labeled unavailable, with a route to the evidence
needed to inspect it. Reading source text and checking a proof are separate
activities.

The [reading map](http://localhost:4000/how-it-fits) connects the policy, six
payment requirements, independent Ledger and Spec implementations, claims,
proof support, and verification reports. It is a suggested reading order,
not a proof dependency graph. The current catalog has 49 claims: 35 Elixir
laws translated through Lynx and 14 claims stated directly in Lean.

For a longer lesson, the
[formal verification crash course](https://github.com/nshkrdotcom/hold_ledger/blob/main/guides/formal_verification_crash_course.md)
starts with a small law, then follows a ledger proof. You can read it before
installing the proof tools.

## Try a case in Case Lab

Open [Case Lab](http://localhost:4000/lab), choose a claim, and read its payment
requirement. **Guided** starts with the requirement, the input, the outputs,
and what the case shows. **Inspector** opens the detailed conditions and proof
material alongside the case on wider screens. Switching views preserves your
proposed output, history, and unsaved events. You can open **Proof** or
**Conditions** directly from either view.

**Read full claim** opens the actual `requires` and `expects` expressions, or
the native Lean declaration. Enter an amount or choose **1¢ less**, **All
available**, or **1¢ more** to explore the admission boundary.

**Code returned** shows the result computed by the ledger. **Proposed output ·
not run** lets you ask whether the selected claim accepts a different answer.
You can edit the result, amount held, hold status, and requested effects. An
effect describes outside work, such as asking the processor to cancel a hold;
it does not establish that the work was delivered or completed.

The result separates input coverage, output acceptance, and account
consistency. Read them together:

| Check result | What to examine |
|---|---|
| The claim accepts the proposed output | Compare it with the payment requirement. The output may expose a gap in the claim, but acceptance alone does not establish a defect. |
| The claim rejects the proposed output | Open the conditions to see which part of the required result failed. |
| The claim does not cover this input | Find the condition that excludes it, then ask whether the policy still requires behavior for that case. |
| No event check is available | Read the source to inspect the claim's scope. |
| The check could not be completed | Inspect the reported problem before drawing a conclusion. |

Expand a condition to see the values used in the comparison. A *binding* is
one combination of values for the claim's variables. The output selector lets
you inspect either the code result or your proposed output with those values.

The editor preserves the counters you enter, including inconsistent totals.
**Recalculate totals** updates them from the edited entries when you request
it. The JSON editor accepts up to eight entries and integers up to 1,000,000.
**Full differences** includes additions, removals, ordering changes, and
ambiguous matches. An invalid edit clears the previous successful check.

### Continue from a result

Use **Run another event** to try a dispatch, timeout, retry, cancellation, or
confirmation. You can branch from a proposed output to inspect what would
follow from it. The paths share their earlier history: one continues from the
code's result and the other from your proposed output.

**Run on both paths** applies the same next event to both paths. For example,
propose releasing an authorized hold when cancellation has only been requested,
then try another request on each path. The alternative can admit work using
capacity the first authorization may still need. These are two histories using
the selected implementation; comparing source versions is a separate task.

### Save a case or a review note

Events remain temporary until you choose **Save to timeline**. **Reset**
returns to the saved timeline, and reloading discards unsaved work.
**Edit starting state** creates a separate saved session.

Saves check the session revision to detect changes from another tab. Commands
save individually; if a conflict interrupts a sequence, the page reports what
was saved and keeps the remaining steps unsaved.

Use **Flag concern**, **Open question**, or **Mark reviewed** to record a review
note, with optional context. The note identifies the claim and case, or the
selected finding when you are reviewing stored comparison evidence. Notes
have their own revision checks and do not save pending events.

**Review notes** opens the history and session export. **Download local repair
packet** appears when a selected source comparison has matching evidence
accepted by the packet validator. Source changes block stale computations and
exports. A saved note records your judgment; it does not change an explanation's
editorial status or establish formal acceptance.

## Practice reviewing a claim change

Claim Lens offers two studies:
[Admit a request that fits exactly](http://localhost:4000/lens/po_a2) and
[Keep an issued hold until its own release evidence](http://localhost:4000/lens/po_exposure_retain).
Each brings together a policy passage, the actual claim, a concrete input, and
a modeled change to the claim. An example that changes only the proof body
helps you distinguish a changed argument from a changed promise.

In **Review first**, read the requirement and proposed change, inspect the
case, and choose a conclusion. Select **Keep my answer and show the
explanation** to reveal the worked explanation and coverage comparison. You
can say that the evidence is insufficient. **Explore freely**, at
`/lens/:slug?mode=explore`, shows the explanation while you try the example.
**See the worked explanation** opens that mode without recording an answer.

Open **Optional · add your reasoning and source notes** to connect the policy,
claim, example, and remaining assumption in writing. After confirmation, you
can copy the argument as Markdown. Your classification and notes stay in the
current page. They are not saved to review notes or sent to an assistant.
Changing the input, proposed claim change, study, or mode clears the attempt.
**Try again** and reloading also start a new attempt.

After feedback, further comparisons cover a missing cancellation effect
(P02), premature release (P05), and correct cancellation before dispatch (P08).
These fixed exercises come from the review guide. Claim Lens does not edit
source or check a revised Lean proof.

## Explore the deliberate faults

[Deliberate code faults](http://localhost:4000/examples) presents M1–M10 with a
concrete input, expected behavior, source details, and the claim intended to
catch each fault. These examples are kept outside the default implementation.
For instance, [M7](http://localhost:4000/examples?example=M7) removes a required
cancellation effect while leaving the hold and its counters intact. The
related effects claim is PO-B3.

The page reads the repository's examples; it does not run a new mutation
campaign. Follow the
[testing guide](https://github.com/nshkrdotcom/hold_ledger/blob/main/guides/testing.md)
when you want fresh execution evidence.

Claim profiles also link to the eight payment-policy exercises, P01–P08.
P08 shows correct cancellation before dispatch. The
[source map](http://localhost:4000/repository) lists all eighteen examples,
with their inputs, expected or proposed outputs, and source paths.

## Get help without leaving the case

**Help** opens a guide for the current page. **Help with controls** lists its
relevant actions; choose one to read what it does without running it. This
works on touch screens as well as with a mouse or keyboard. Term help includes
a short definition, a repository example, why it matters, and relevant limits
and reading links.

Use **Extra explanations** inside Help to show or hide inline hints. That
setting is separate from Case Lab's Guided/Inspector view. The `?` shortcut
opens page help when you are not typing in a field. Escape closes open help
and returns focus to its control.

The [glossary](http://localhost:4000/glossary) includes both payment and review
terms, including bindings, clauses, helpers, inspection basis, source
generation, and the coupled model. Technical names such as *candidate* and
*fencing* lead to the same explanations as their interface labels.

## Read the source and verification evidence

In Case Lab, **Conditions** explains the selected result and **Proof** opens
the related Lean source. Selecting a reviewed clause can open its linked Lean
passage; **Read full proof** opens the complete source. These links depend on
the reviewed source bytes. Missing, stale, or ambiguous connections are marked
unavailable.

Claim profiles label their explanations **Editorial draft** because owner
review of the prose is not recorded. That label is separate from registration,
case results, proof reports, and your saved review notes.

| Evidence | What it establishes |
|---|---|
| Registered claim | The claim belongs to the catalog. |
| Case check | How the claim treats this concrete input and output. |
| Source reading | A reviewed connection between Elixir and Lean text. |
| Focused elaboration | Lean elaborated the selected generated declarations for the recorded source. |
| Accepted full verification report | The required checks passed for the source bytes and claim scope recorded in the report. |

A checked theorem establishes its stated conclusion under its assumptions.
Its connection to the payment policy and the faithfulness of the translation
still need review. The
[Evidence page](http://localhost:4000/assurance) explains the evidence types and
links to Lean's proof-validation guide. Full acceptance requires the project's
six checker configurations and permitted-axiom audit; a catalog count or source
excerpt is not a substitute for that report.

**Open coupled processor case** shows local knowledge alongside the modeled
processor state. Issuing authorization, delivering a processor decision, and
recording that decision locally are separate steps. An approval keeps the hold
active; its trusted decline or void confirmation can release it.
**Assumptions** lets you vary supported processor behavior, including whether
cancellation stays final. The
[processor](https://github.com/nshkrdotcom/hold_ledger/blob/main/guides/processors.md)
and [runtime](https://github.com/nshkrdotcom/hold_ledger/blob/main/guides/runtime.md)
guides describe what a real service and durable storage must provide.

**Verification files** contains generated sources and matching reports. To
produce focused readings for the three primary worked claims, run from the
repository root:

```sh
MIX_ENV=test uv run --locked python scripts/local_run.py \
  mix run apps/review_web/scripts/produce_claim_readings.exs
```

The files are written to ignored `tmp/verification/claim-reading`. Full
acceptance uses a matching report for the complete required scope and the
`ProofEvidence` validation described in the
[verification guide](https://github.com/nshkrdotcom/hold_ledger/blob/main/guides/verification.md).

## Compare two source versions

Stage each trusted local Git worktree from the repository root:

```sh
python3 apps/review_web/scripts/stage_part3_snapshot.py \
  --source /absolute/path/to/trusted/worktree \
  --destination /absolute/path/to/hold_ledger/tmp/review_studio/snapshots
```

Provision compatible pinned dependencies offline in each snapshot's ignored
`tmp/part3_build` directories. In Case Lab, choose the staged snapshots under
**Compare source versions**. **Run on both versions** evaluates the active
input in separate BEAM processes. The opening **Example change** is a built-in
illustration.

Compare the inputs each claim covers, the outputs it permits, and the result
each implementation returns. A stored difference gives you a case to review
against the policy. Finding no difference in the tried cases does not establish
equivalence.

Use trusted source: process isolation prevents module mixing but does not
sandbox hostile code. The browser does not install dependencies or accept
executable uploads.

## Ask an assistant about a case

In the header, type a question and choose **Ask an assistant**, or press Enter,
to send it with the displayed case and source. On smaller screens, **Ask an
assistant** opens the question panel, where **Send question** submits it.
Local learning links are also available if you want to continue reading
without a model request.

Before sending, use **Shares case + source** and **Context** to inspect the
prompt and context. They include the selected input and output, policy, Ledger
and Spec source, runtime and processor guides, and the active claim and Lean
excerpts. Private review notes are excluded, and the app refuses oversized or
stale context. Each submission authorizes that question and its displayed
context.

The configured provider is **Codex**. Requests use your existing Codex
authentication and ask for `gpt-6.1-terra` with medium reasoning. The model has
no editing or shell tools, and the app uses no fallback provider. Answers
appear beside the case with source links and response details. Treat them as
generated explanations; check proof results in the evidence panels.

**History** searches local questions and reopens saved answers without a
provider call. You can copy or export a question, submit a follow-up with its
historical case, or choose **Ask using current case**. Typing, inspecting
context, reopening history, and reloading send nothing. Question actions leave
pending events and review notes unchanged.

Prompts, source context, answers, errors, and request events are stored in
ignored `tmp/review_studio/questions/<trace-id>/events.jsonl` with owner-only
permissions. Logs exclude credentials and private provider reasoning. A
request is sent only after it can be logged; if an answer cannot be saved,
the page reports the failure. Cancel, timeout, and restart do not resend
requests automatically. **Clear history…** asks for confirmation before
deleting question logs. Deletion is refused while a question is running.

## Find a page or source file

The main navigation contains **Explore**, **Case Lab**, and **Claims**.
**Guides** opens the learning and reference pages. When a claim is selected,
**For this claim** connects its overview and Case Lab case; **Guided practice**
also appears for the two supported Claim Lens studies.

| Page | What you can find |
|---|---|
| [Explore](http://localhost:4000/) | The interactive payment example and suggested starting points. |
| [Payment walkthrough](http://localhost:4000/start) | The account before and after each event in the missing-reply example. |
| [Reading map](http://localhost:4000/how-it-fits) | How the policy, implementation, claims, and evidence fit together. |
| [Elixir to Lean](http://localhost:4000/translation) | The exact-fit law, related source, and available generated material. |
| [Deliberate code faults](http://localhost:4000/examples) | Ten source mutations and their concrete examples. |
| [System](http://localhost:4000/system) | The components and seven ledger states. |
| [Payment requirements](http://localhost:4000/guarantees) | The six behaviors the policy requires. |
| [Claim catalog](http://localhost:4000/atlas) | All 49 claims in eight reading families. |
| [Reading claims](http://localhost:4000/proofs) | Input conditions, required results, and the exact-fit example. |
| [Evidence and assumptions](http://localhost:4000/assurance) | How to interpret checks and external assumptions. |
| [Source map](http://localhost:4000/repository) | Relevant files and all eighteen mutation and policy examples. |
| [Glossary](http://localhost:4000/glossary) | Definitions, concrete examples, and further reading. |

Claim profiles use `/atlas/:slug`. Case Lab uses `/claims/:slug` or
`/claims/:slug/:id` for a saved review session. The existing routes remain
available when you follow a direct link.

## Use the command interface

Write a JSON request file, then run this from the repository root:

```sh
uv run --locked python scripts/local_run.py --cwd apps/review_web \
  mix run --no-start scripts/explore.exs -- /absolute/path/to/request.json
```

Read a claim:

```json
{"operation":"read_claim","slug":"po_exposure_retain"}
```

Run a request through the ledger:

```json
{"operation":"step","mode":"ledger","before":{"amount_limit":100,"hold_limit":2,"used_amount":0,"used_holds":0,"entries":[]},"event":{"type":"request","key":11,"amount":100}}
```

To inspect individual conditions, use `explain_claim` with a `slug` and a
`witness` containing complete `before`, `event`, and `output` values. The
command uses the screen's evaluator and source readings in a separate scratch
store. Request files are limited to 64,000 bytes. It opens no HTTP listener
and makes no model request.

## Check changes

From the repository root:

```sh
uv run --locked python scripts/local_run.py mix test test/claim_source_parity_test.exs
uv run --locked python scripts/local_run.py mix test --exclude laws
uv run --locked python scripts/local_run.py --cwd apps/review_web mix test test/hold_ledger_review/claim_lens_test.exs test/hold_ledger_review_web/claim_lens_live_test.exs
uv run --locked python scripts/local_run.py --cwd apps/review_web mix precommit
uv run --locked python scripts/local_run.py --cwd apps/review_web mix docs --warnings-as-errors
uv run --locked python scripts/local_run.py --cwd apps/review_web mix assets.build
python3 -m unittest discover -s apps/review_web/scripts -p 'test_*.py' -v
```

`precommit` runs compilation with warnings treated as errors, formatting,
strict Credo, Dialyzer, and Phoenix tests. Python content checks validate the
authored catalog, glossary, and help data; they do not replace compilation or
runtime interaction tests.

With Phoenix running, use a separate terminal for browser checks:

```sh
cd apps/review_web/test/browser
npm ci
npx playwright install chromium
npm test
```

Supply real compatible `PART3_TEST_BASELINE_ID` and `PART3_TEST_PROPOSAL_ID`
values for the isolated-source comparison case. Lens checks live in
`test/browser/0810_claim_lens.spec.cjs`.

From the browser-test directory, `npm run test:presentation` loads the app's
help JavaScript and content into local browser fixtures without a Phoenix
server. The normal `npm test` suite exercises the rendered LiveView screens.

`npm run test:questions` starts and stops its own controlled Phoenix fixture
on port 4001. It checks question submission and local persistence without
provider calls; it does not measure live answer quality.

## License

Released under the [MIT License](LICENSE).
