<p align="center">
  <img src="assets/review_web.svg" alt="Hold Ledger · Verification" width="200" height="200">
</p>

# Hold Ledger · Verification

[![GitHub](https://img.shields.io/badge/GitHub-hold__ledger-181717?logo=github)](https://github.com/nshkrdotcom/hold_ledger)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

A payment processor can authorize a request even when its reply never arrives.
The ledger must keep counting that hold until it has the evidence needed to
release it. This Phoenix app lets you follow a 100¢ example, inspect the code,
and question the claims used to verify it.

A ledger can refuse every request and still keep its totals consistent. Its
claims must also require the behavior you need, such as admitting a request
that fits. Start with the missing-reply walkthrough, then review a claim
change that excludes an exact-fit request.

The app explores a local model of one account. **Case Lab** lets you try inputs
and propose different outputs. **Claim Lens** offers two guided reviews. You
can start without knowing Lean; the policy and source are available as you go.

## Run locally

Use the Elixir/OTP versions listed in [Getting started](https://github.com/nshkrdotcom/hold_ledger/blob/main/guides/getting-started.md).
That guide also covers Python and `uv`.
Onboarding checks your existing Elixir/OTP installation and provisions the
pinned local proof tools. From the repository root:

```sh
uv sync --locked
uv run --locked python scripts/onboard.py --profile runtime --provision
uv run --locked python scripts/local_run.py --cwd apps/review_web mix deps.get --check-locked
uv run --locked python scripts/local_run.py --cwd apps/review_web mix assets.build
uv run --locked python scripts/local_run.py --cwd apps/review_web mix phx.server
```

Open [localhost:4000](http://localhost:4000) and choose **Follow a payment hold**.
Amounts are integer cents: `100` means $1.00.

## Follow a hold through a missing reply

Open the [payment walkthrough](http://localhost:4000/start). An authorization
hold reserves an amount for possible later capture. This example starts with
an empty account, a 100¢ limit and two hold slots.

Before advancing through the four steps, consider whether a timeout should
make the 100¢ available again.

| Event | What the walkthrough shows |
|---|---|
| Request 11 asks for 100¢ | The ledger admits it and reserves 100¢ and one slot. |
| The request is dispatched | The ledger requests authorization and records the hold as sent. |
| The reply never arrives | The ledger marks the outcome unknown and keeps the capacity held. |
| Request 12 asks for another 100¢ | The ledger refuses it: one slot is free, but no amount is available. |

The processor may have approved the first authorization before its reply was
lost. A timeout alone gives the ledger no evidence to release the hold. That
is why the second request must not reuse the same capacity.

The walkthrough includes optional background reading and a short self-check.
You can continue without opening them. The result above illustrates the model;
the walkthrough does not contact a payment processor.

## Review a changed claim

Open [Admit a request that fits exactly](http://localhost:4000/lens/po_a2). An account has
100¢ available and a free hold slot. A new request asks for all 100¢.

1. Read the policy and the claim's `requires` and `expects` clauses.
2. Compare the original claim with the **Proposed claim change**. Does each
   cover the exact-fit input?
3. Inspect **Code returned** and **Proposed output · not run**.
4. Choose a classification, then select **Confirm classification and reveal
   feedback**. You can say you are unsure.

Then try 99¢ and 101¢. Notice how a changed precondition can leave out an
important case while still covering others. You are reviewing the claim's
promise; proof tactics can wait.

## Find your way around

| What you want to do | Open |
|---|---|
| Follow a hold through a missing reply | [Payment walkthrough](http://localhost:4000/start) |
| Explore the components and hold states | [System](http://localhost:4000/system) |
| Read the six payment requirements | [Requirements](http://localhost:4000/guarantees) |
| Find a claim, its scenario, and source | [Claim catalog](http://localhost:4000/atlas) |
| Read the inputs and outputs a claim promises | [Reading claims](http://localhost:4000/proofs) |
| Understand reports and external assumptions | [Evidence](http://localhost:4000/assurance) |
| Locate the relevant files | [Source map](http://localhost:4000/repository) |
| Look up an unfamiliar term | [Glossary](http://localhost:4000/glossary) |
| Run a case or compare source versions | [Case Lab](http://localhost:4000/lab) |
| Practice a review | [Claim Lens](http://localhost:4000/lens/po_a2) |

The catalog groups its 49 claims into eight reading families. It includes
35 Elixir laws translated through Lynx and 14 claims written directly in Lean.
Each profile starts with a concrete situation, the required result, what could
go wrong, and the claim's scope.

When a claim is selected, **For this claim** links to **Read claim** and
**Case Lab**. **Guided practice** appears for the two supported Lens studies.
These links help you move between views of the same claim. Profiles live at
`/atlas/:slug`; Lab cases use `/claims/:slug` and `/claims/:slug/:id`.

Related examples have names as well as IDs. **M1–M10** are deliberate source
faults kept outside the default implementation. **P01–P08** are payment-policy
exercises; P08 demonstrates correct cancellation before dispatch. Profiles show
their related examples, and the [source map](http://localhost:4000/repository)
lists all eighteen. Read what should happen and what the example changes, then
open **Input and source details** for the concrete input and source. Those
examples describe expected or proposed outputs, not new executions.

Optional reading appears beside the concept it explains: authorization holds
in the walkthrough, retries on System, notation on Reading claims, and proof
checking on Evidence. Each suggests what to read and what to skip, with an
optional self-check. The [glossary](http://localhost:4000/glossary) explains
attempt, poison, obligation, oracle, fold and issued with repository examples.

## Explore a case in Case Lab

Choose a claim and read its requirement summary. **Read full claim** opens the
actual `requires` and `expects`, or the native Lean declaration. Enter an
amount or use **1¢ less / All available / 1¢ more** to explore a boundary.

**Code returned** shows the computed Ledger result. **Proposed output · not
run** lets you ask whether the claim would accept a different answer. Edit the
result, reserved amount, hold status, or requested effects. A requested effect
describes outside work, such as sending a cancellation request.

The check table separates input coverage, output acceptance and account
consistency. Expand a condition to see the values used in its comparison.

| Result | How to read it |
|---|---|
| Claim would accept this output. Intended? | Compare the proposed output with the policy. Acceptance alone does not establish a defect. |
| Claim rejects this output | The proposed output fails the claim for this input. |
| Claim says nothing about this input | The starting condition is false. Inspect why the input is excluded; this result does not establish that the output meets the policy. |
| No check wired up for this event | Read the source; this event has no supported probe. |
| Check unavailable | An observation is missing or failed. |

You can deliberately leave totals inconsistent. **Recalculate totals** changes
them only when requested. The JSON editor accepts up to eight entries and
integers up to 1,000,000. **Full differences** includes additions, removals,
ordering changes, and ambiguous matches. Invalid edits clear the previous
successful check.

Use **Run another event** to try dispatch, timeout, retry, cancellation, or
confirmation. Branch from a proposed output to explore what would follow from
it. Both paths share the earlier history: one starts with the code's result,
and the other with your proposed output. Later events compute a continuation
from each starting state.

**Run on both paths** applies the same event at the end of each path. Compare
the result and reserved amount. For example, propose releasing an authorized
hold when cancellation is only requested, then try another request on both
paths. The alternative can reuse capacity that the earlier hold still needs.

## Practice with Claim Lens

Lens has two studies: [Admit a request that fits exactly](http://localhost:4000/lens/po_a2)
and [Keep an issued hold until its own release evidence](http://localhost:4000/lens/po_exposure_retain).
Each pairs a policy passage with an actual claim, a concrete input, and a
modeled change to the claim. A proof-body-only example helps you distinguish
a changed argument from a changed promise.

**Review first** is the default. You can read the source before deciding;
worked verdicts, coverage comparisons, and explanations appear after you
confirm your classification. **Explore freely**, at
`/lens/:slug?mode=explore`, shows that feedback immediately.

An optional argument form asks you to connect the policy, claim, example, and
remaining assumption. After confirmation, you can copy it as Markdown. Your
classification and argument stay in the current page: they are not saved to
review notes or sent to a model. Choosing another input, proposed claim change,
study or mode clears the attempt. **Try again** and reloading do the same.

After feedback, three further comparisons cover a missing void effect (P02),
premature release (P05), and cancellation before dispatch (P08). These worked
examples come from the review guide. Lens models fixed claim changes; it does
not edit source or check a revised proof.

## Save a case or a review note

Lab events remain temporary until you choose **Save to timeline**, which keeps
them in the current review session. **Reset** returns to the saved timeline;
reloading also discards unsaved work. **Edit starting state** creates a separate
saved session.

Saving checks the session revision to catch changes from another tab. Commands
save individually. If a conflict interrupts a multi-step save, the page reports
what was saved and keeps the remaining steps unsaved.

Use **Flag concern**, **Open question**, or **Mark reviewed** to record a
review note, with optional context. The target identifies the claim and case;
when stored comparison evidence is selected, it identifies that finding.
Notes have their own revision checks and do not save pending events.

Open **Review notes** to read the history or export a session. **Download
local repair packet** appears when a selected source comparison has matching
evidence accepted by the packet validator. The app blocks stale computations
and exports after source changes. A saved note records your review; it does not
change the editorial status of a claim explanation or establish formal
acceptance.

## Read the source and evidence

Claim profiles label their explanations **Editorial draft**, with the note:
“Sources are linked below. Owner review of this explanation is not recorded
here.” The label describes the prose. Catalog registration, computed cases,
proof reports and saved review notes each describe different evidence.

In Lab, start with the conditions that explain the selected result. Expand
the expression tree for helper definitions, operands and individual bindings.
Selecting a reviewed clause opens the related Lean passage; **Read full proof**
opens the complete source. Links are checked against the reviewed source bytes.
A missing, stale or ambiguous link is marked unavailable.

| What you are looking at | What it establishes |
|---|---|
| Registered claim | The claim belongs to the catalog. |
| Single-case check | The claim's response to this particular input and output. |
| Source reading | A reviewed connection between Elixir and Lean text. |
| Focused elaboration | Lean elaborated the selected generated declarations for the recorded sources. |
| Accepted full verification report | The required checks passed for the source bytes and claim scope recorded in the report. |

Lean's kernel checks a formal proof against its formal statement. The
translation from Elixir and the statement's connection to the payment policy
still need review. The [Evidence page](http://localhost:4000/assurance) links
to Lean's validation guide and explains the remaining assumptions.

**Open coupled processor case** shows local knowledge alongside the modeled
processor state. The model separates issuing a request, delivering a processor
decision, and recording that decision locally. An approval keeps a hold active;
a trusted decline or void confirmation can release it. **Assumptions** lets you
change modeled processor behavior, including whether cancellation stays final.
The linked processor and runtime guides explain what a real service and durable
storage must provide.

**Verification files** contains generated sources and matching reports. To
produce focused readings for the three primary worked claims, run from the
repository root:

```sh
MIX_ENV=test uv run --locked python scripts/local_run.py \
  mix run apps/review_web/scripts/produce_claim_readings.exs
```

Output goes to ignored `tmp/verification/claim-reading`. Full acceptance uses
the matching required-scope report and `ProofEvidence` validation described in
the [verification guide](https://github.com/nshkrdotcom/hold_ledger/blob/main/guides/verification.md).

## Compare two source versions

From the repository root, stage each trusted local Git worktree:

```sh
python3 apps/review_web/scripts/stage_part3_snapshot.py \
  --source /absolute/path/to/trusted/worktree \
  --destination /absolute/path/to/hold_ledger/tmp/review_studio/snapshots
```

Provision compatible pinned dependencies offline in each snapshot's ignored
`tmp/part3_build` directories. In Lab, choose the staged snapshots under
**Compare versions**. **Run on both versions** evaluates the active input in
separate BEAM processes. The opening **Example change** is a built-in
illustration.

Compare what each claim covers, what outputs it permits, and what the code
returns. A stored difference is a case to inspect against the policy. Finding
no difference in the tried cases does not establish equivalence. Use trusted
source: process isolation prevents module mixing but does not sandbox hostile
code. The browser neither installs dependencies nor accepts executable uploads.

## Ask Codex about a case

Type a question and press **Ask Codex** or Enter to send it immediately with
the displayed case and source. On smaller screens, open **Ask** and press
**Send to Codex**. Each submission authorizes that question and its displayed
context.

Before sending, use **Shares case + source** and **Context** to inspect the
prompt and context that will be sent. The context includes the selected input
and output, policy, Ledger and Spec source, runtime and processor guides, and
active claim and Lean excerpts. Private review notes are excluded. The app
refuses oversized or stale context.

Questions use your existing Codex authentication and request
`gpt-6.1-terra` with medium reasoning. The app gives the model no editing or
shell tools and uses no fallback provider. Answers appear beside the case,
with source links and response details. They are generated explanations;
the evidence panels remain the place to check proof results.

**History** searches local questions and reopens answers without a provider
call. You can copy or export a question, submit a follow-up with its historical
case, or choose **Ask using current case**. Typing, inspecting context, recalling
history, and reloading send nothing. Question actions do not save pending
events or change review notes.

Prompts, source context, answers, errors, and request events are stored in
ignored `tmp/review_studio/questions/<trace-id>/events.jsonl`, with owner-only
permissions. Logs exclude credentials and private provider reasoning. If a
request cannot be logged, it is not sent. If an answer cannot be saved, the
page reports the failure. Cancel, timeout and restart do not resend
automatically. **Clear history…** confirms before deleting question logs.
Deletion is refused while a question is running.

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

For clause observations, use `explain_claim` with a `slug` and a `witness`
containing complete `before`, `event`, and `output` values. The command uses
the same evaluator and source readings as the screen, in its own scratch
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
strict Credo, Dialyzer, and Phoenix tests.

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

For help interactions, run `npm run test:presentation` from the browser-test
directory. It loads the app's help JavaScript and glossary into local browser
fixtures. These checks need no Phoenix server; the normal `npm test` suite
exercises the rendered LiveView screens.

From the browser-test directory, `npm run test:questions` starts and stops its
own controlled Phoenix fixture on port 4001. It checks question submission and
local persistence without provider calls; it does not measure live answer
quality.

## License

Released under the [MIT License](LICENSE).
