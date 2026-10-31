<p align="center">
  <img src="assets/review_web.svg" alt="Hold Ledger · Verification" width="200" height="200">
</p>

# Hold Ledger · Verification

[![GitHub](https://img.shields.io/badge/GitHub-hold__ledger-181717?logo=github)](https://github.com/nshkrdotcom/hold_ledger)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

A payment processor may approve a hold before its reply is lost. What should
the ledger do with the reserved amount? Follow a 100¢ example, try another
answer, and inspect the claims and proof evidence behind the required behavior.

Hold Ledger Review Web is a local learning and review app for
[Hold Ledger](https://github.com/nshkrdotcom/hold_ledger). It connects ordinary
Elixir functions to formal verification: precise statements and checked proofs
about modeled behavior. [Lynx](https://github.com/josevalim/lynx) translates
supported Elixir code and laws into Lean; Lean checks the supplied proofs of
those statements. The app helps you read that connection without requiring
prior Lean knowledge.

The central review question is whether the statement requires the behavior you
need. A ledger that refuses every request can keep its totals consistent.
An admission claim must also require eligible requests to succeed. Throughout
the app, concrete case checks, source readings, proof reports and human review
answer separate questions.

The examples model authorization holds for one account. Amounts are integer
cents: `100` means $1.00. Capture, settlement and authorization expiry are
outside the event model. The examples contact no payment processor.

## Contents

- [Run locally](#run-locally)
- [Choose a learning path](#choose-a-learning-path)
- [Follow the payment walkthrough](#follow-the-payment-walkthrough)
- [Connect a requirement to a proof](#connect-a-requirement-to-a-proof)
- [Investigate a case in Case Lab](#investigate-a-case-in-case-lab)
- [Continue, save and export a case](#continue-save-and-export-a-case)
- [Practice reviewing a claim](#practice-reviewing-a-claim)
- [Explore deliberate bugs](#explore-deliberate-bugs)
- [Read verification evidence](#read-verification-evidence)
- [Compare source versions](#compare-source-versions)
- [Ask an assistant](#ask-an-assistant)
- [Use help and the glossary](#use-help-and-the-glossary)
- [Configuration and local records](#configuration-and-local-records)
- [Find pages and authored content](#find-pages-and-authored-content)
- [Use the command interface](#use-the-command-interface)
- [Check changes](#check-changes)
- [Troubleshooting](#troubleshooting)

## Run locally

This app is a separate Phoenix project at `apps/review_web`, with a local path
dependency on the repository root. Run the commands below from that root.

Follow [Getting started](https://github.com/nshkrdotcom/hold_ledger/blob/main/guides/getting-started.md) for the pinned
Elixir/OTP pair, Python and `uv`. The app's CI uses Elixir 1.20.4 and OTP 29.1.2.
Onboarding checks the installed Elixir/OTP and provisions the pinned local proof
tools; Python and `uv` support repository tooling rather than the application
runtime.

```sh
uv sync --locked
uv run --locked python scripts/onboard.py --profile runtime --provision
uv run --locked python scripts/local_run.py --cwd apps/review_web mix deps.get --check-locked
uv run --locked python scripts/local_run.py --cwd apps/review_web mix assets.setup
uv run --locked python scripts/local_run.py --cwd apps/review_web mix assets.build
uv run --locked python scripts/local_run.py --cwd apps/review_web mix phx.server
```

Open [localhost:4000](http://localhost:4000) and choose **Learn**. The
**Payment walkthrough** begins with an empty account, a 100¢ limit and two hold
slots. Development configuration binds the app to localhost. This prototype
is intended for local use; it has no supported hosted-release setup.

## Choose a learning path

The primary navigation is **Overview**, **Learn**, **Case Lab** and
**Claim Atlas**. Learn groups the Payment walkthrough, System guide, Payment
requirements, Elixir to Lean and Read a claim. Reference groups the reading
and source material. Contextual links keep the selected claim nearby.

| What you want to do | Start here | What to inspect next |
|---|---|---|
| Understand why a missing reply keeps capacity reserved | [Payment walkthrough](http://localhost:4000/start) | Open its selected moment in Case Lab. |
| Connect familiar Elixir to a formal statement | [Elixir to Lean](http://localhost:4000/translation) | Read PO-A2's input conditions, required result and available Lean source. |
| Find a property or example | [Claim Atlas](http://localhost:4000/atlas) | Open the claim profile, then its case or proof source. |
| Test what a claim permits | [Case Lab](http://localhost:4000/lab) | Compare Code returned with a What-if output. |
| Judge whether a changed claim still covers a requirement | [Claim Lens](http://localhost:4000/lens/po_a2) | Choose a conclusion before revealing the worked explanation. |
| Review source and evidence directly | [Reading map](http://localhost:4000/how-it-fits) | Follow the policy, source and matching verification report. |

A useful first journey is the Payment walkthrough, Elixir to Lean, the exact-fit
case in Case Lab, then Claim Lens. The
[formal verification crash course](https://github.com/nshkrdotcom/hold_ledger/blob/main/guides/formal_verification_crash_course.md)
provides a longer lesson, starting with a small law before a ledger proof.
You can read it before installing the proof tools.

## Follow the payment walkthrough

A hold reserves an amount for possible later capture. A new request needs both
an available amount and a free hold slot. The walkthrough uses the current
ledger transitions, so each displayed state, result and requested effect belongs
to the same computed case.

| Moment | Ledger behavior | Amount held | Free slots |
|---|---|---|---|
| Empty account | All 100¢ and both slots are available. | 0¢ | 2 |
| Request 11 asks for 100¢ | Admit the exact fit and reserve it locally. | 100¢ | 1 |
| Dispatch | Record the hold as sent and request authorization. | 100¢ | 1 |
| Timeout | Record that the remote outcome is unknown. | 100¢ | 1 |
| Request 12 asks for 100¢ | Refuse it because no amount is available. | 100¢ | 1 |

The first authorization may already have been approved. A timeout tells the
ledger that the reply is missing; it supplies no trusted decline or cancellation
confirmation. Keeping the hold counted prevents the second request from reusing
capacity the first authorization may still need.

The timeout illustration presents possible processor outcomes alongside the
ledger's knowledge. Choosing a possibility changes the explanation while the
computed ledger state stays the same. It helps explain uncertainty; it is not
a live processor observation.

Select a moment to compare the account before and after its event. **Open this
moment in Case Lab** creates a local review session containing that history.
You can continue with another event or inspect a What-if output. Source values,
background reading and a self-check are available alongside the story.

## Connect a requirement to a proof

The Elixir-to-Lean lesson follows exact-fit admission, PO-A2. An empty account
has 100¢ available and a free slot; a fresh request asks for all 100¢. The payment
policy requires admission.

| Piece | Its job in this example |
|---|---|
| Payment requirement | Establish that an eligible exact fit must be admitted. |
| `Ledger` | Compute the next state, result and requested outside work. |
| Independent `Spec` | Define eligibility and expected behavior separately from `Ledger`. |
| Elixir law | Use `requires` to select covered inputs and `expects` to require the exact admitted output. |
| Lynx translation | Produce Lean definitions and statements from supported compiled Elixir and laws. |
| Lean proof | Establish the supplied statement under its assumptions. |
| Verification report | Record the source, scope and checks accepted by a particular run. |

Follow the called predicates as well as the visible law. PO-A2 uses
`Spec.request_eligible?`; its amount comparison includes equality. Replacing
`<=` with `<` in that eligibility condition would leave exact fit uncovered,
even if the narrower statement had a valid proof.

The lesson's concept selector focuses on input conditions, required results or
the proof while keeping the actual source panels available. Each panel identifies
its source. Generated material appears when it matches the reviewed source;
missing or stale material is labeled unavailable.

The Claim Atlas currently registers **49 claim groups**: **35 Elixir law groups**
and **14 groups stated directly in Lean**. A group may contain several theorem
declarations. The eight families provide curated navigation. Requirement links
help you find related groups; they establish neither complete policy coverage
nor Lean proof dependencies. Registration itself reports no checker result.

The [Reading map](http://localhost:4000/how-it-fits) connects the six payment
requirements, implementation, independent reference, claims and verification
evidence. Use it as a reading path, then inspect the actual statements.

## Investigate a case in Case Lab

Choose a claim and read its payment requirement before changing the input.
**Guided** keeps the requirement, input, outputs and case result together.
**Inspector** opens detailed conditions and proof material alongside the case
on wider screens. Switching views keeps your What-if output, history and
unsaved events. **Proof** and **Conditions** are available from either view.

**Read the claim** opens the registered `requires` and `expects` expressions
or the native Lean declaration. For admission, enter an amount or use
**1¢ less**, **All available** and **1¢ more** to inspect the boundary.

### Compare the code result with a What-if output

**Code returned** is the ledger's computed output. **What-if output** is a
hypothetical next state, result and effects that you supply for inspection.
It is never run as code. Checking it asks whether the selected claim permits
that answer for the same input.

You can edit the result, held amount, hold status and requested effects.
An effect describes outside work, such as asking the processor to cancel a
hold. Delivery and completion require evidence beyond that effect description.

Read input coverage, output acceptance and account consistency together:

| Case result | What to inspect |
|---|---|
| Claim accepts the What-if output | Compare it with the payment requirement. Acceptance can help reveal a gap; it does not by itself establish one. |
| Claim rejects the What-if output | Open Conditions to find which required part fails. |
| Input is outside the claim's conditions | Find the excluding condition, then check whether the policy still requires behavior for this input. |
| No case check is available | Read the claim source to inspect its scope. |
| The case could not be checked | Read the reported problem before drawing a conclusion. |

A *binding* is one combination of values assigned to the claim's variables.
Expand a condition to see those values. The output selector lets you inspect
the code result or your What-if output using the same input. Some claims need
several bindings; inspecting one leaves the overall check's scope unchanged.

The editor preserves the counters you enter, including inconsistent totals.
Choose **Recalculate totals** when you want them recomputed from the entries.
The JSON editor accepts up to eight entries and integers up to 1,000,000.
**Full differences** includes additions, removals, ordering changes and ambiguous
matches. An invalid edit clears the previous successful check.

### Continue along two paths

Use **Run another event** for dispatch, timeout, retry, cancellation or
confirmation. You can branch from the What-if state to inspect what the ledger
would compute next from that supplied state. The earlier history is shared:
one path continues from the code result, the other from your hypothetical state.

**Run on both paths** applies the same next event to both. For example, propose
releasing an authorized hold as soon as cancellation is requested, then try
another request on each path. The alternative path can reuse capacity while
the original authorization may still need it. Both paths use the selected
implementation; comparing source versions is a separate task.

## Continue, save and export a case

Events stay temporary until you choose **Save to timeline**. **Reset** returns
to the saved timeline; reloading discards unsaved work. **Edit starting state**
creates a separate saved session rather than replacing the current history.

Each save checks the session revision for changes from another tab. Commands
save individually. If a conflict interrupts a sequence, the page identifies
what saved and keeps the remaining steps unsaved.

Use **Flag concern**, **Open question** or **Mark reviewed** to save a review
note, with optional context. A note identifies the claim and case, or the
selected finding in stored comparison evidence. Notes use their own revision
checks and leave pending events unsaved.

**Review notes** opens the history and session export. **Download local repair
packet** appears when a selected source comparison has matching evidence
accepted by the packet validator. Relevant source changes block stale
computations and exports. A saved note records your judgment; formal acceptance
still comes from verification evidence, and prose-review status is separate.

## Practice reviewing a claim

Claim Lens has two studies:
[Admit a request that fits exactly](http://localhost:4000/lens/po_a2) and
[Keep an issued hold until its own release evidence](http://localhost:4000/lens/po_exposure_retain).
Each connects a policy passage, actual claim, concrete input and modeled change
to the statement. A proof-body-only example helps distinguish a changed argument
from a changed promise.

In **Review first**, inspect the requirement, change and case, then choose a
conclusion. **Keep my answer and show the explanation** reveals the worked
reasoning and coverage comparison. Insufficient evidence is a valid conclusion.
**Explore freely**, at `/lens/:slug?mode=explore`, shows the explanation as you
try the example. **See the worked explanation** opens that mode without recording
an answer.

**Optional · add your reasoning and source notes** lets you connect the policy,
claim, example and remaining assumption. After confirmation, copy the argument
as Markdown. Your classification and reasoning stay on the current page;
they are neither saved as review notes nor sent to an assistant. Changing the
input, proposed claim change, study or mode clears the attempt. **Try again**
and reloading also start a new attempt.

Further comparisons cover a missing cancellation effect (P02), premature
release (P05) and correct cancellation before dispatch (P08). These are fixed
review-guide exercises. Claim Lens models statement changes; it does not edit
source or check a revised Lean proof.

## Explore deliberate bugs

[Deliberate bugs](http://localhost:4000/examples) presents M1–M10 with a concrete
input, expected behavior, changed source and target claim. The patches are
kept outside the default implementation. For example,
[M7](http://localhost:4000/examples?example=M7) omits the requested cancellation
while retaining the hold and correct counters. PO-B3 checks requested effects.

The page reads committed examples. Use the [testing guide](https://github.com/nshkrdotcom/hold_ledger/blob/main/guides/testing.md)
when you need fresh mutation execution evidence.

Claim profiles also link to eight payment-policy exercises, P01–P08. P08 is
correct cancellation before dispatch, so an unfamiliar output need not be a
bug. The [Repository map](http://localhost:4000/repository) lists all eighteen
examples with their inputs, expected or hypothetical outputs and source paths.

## Read verification evidence

In Case Lab, **Conditions** explains the selected case and **Proof** opens its
related Lean source. A reviewed clause can link to a corresponding Lean passage;
**Read full proof** opens the complete text. These connections depend on the
reviewed source bytes. Missing, stale or ambiguous links are marked unavailable.

| Evidence | What you can conclude |
|---|---|
| Registered claim group | The group belongs to the catalog. |
| Case check | The claim treats this concrete input and output as reported. |
| Source reading | There is a reviewed connection between the displayed Elixir and Lean text. |
| Focused elaboration | Lean elaborated the selected generated declarations for the recorded source. |
| Accepted full verification report | The required checks passed for the recorded source bytes and full required claim scope. |

A checked theorem establishes its stated conclusion under its assumptions.
Review must still connect the statement to the policy and the translated model
to the source. Full acceptance requires all six checker configurations and the
permitted-axiom audit. The [verification guide](https://github.com/nshkrdotcom/hold_ledger/blob/main/guides/verification.md)
describes scope and `ProofEvidence` validation. A count, source excerpt or
selected-scope result cannot stand in for that full report.

Profile explanations are labeled **Editorial draft** because owner review of
the prose is not recorded. That status is independent of registration, case
checks, proof reports and your saved review notes.

### Inspect the processor assumptions

**Open coupled processor case** shows the ledger's knowledge alongside modeled
processor state. Issuing authorization, delivering a processor decision and
recording it locally are separate steps. Approval keeps the hold active;
that hold's trusted decline or void confirmation can release it.

**Assumptions** varies supported processor behavior, including whether
cancellation stays final. The [processor](https://github.com/nshkrdotcom/hold_ledger/blob/main/guides/processors.md) and
[runtime](https://github.com/nshkrdotcom/hold_ledger/blob/main/guides/runtime.md) guides explain what a real service and durable
storage must provide. A modeled assumption is a requirement for that boundary,
not evidence that a deployed service meets it.

### Produce focused source readings

**Verification files** contains generated source and matching reports. From
the repository root, produce focused readings for the three primary worked
claims with:

```sh
MIX_ENV=test uv run --locked python scripts/local_run.py \
  mix run apps/review_web/scripts/produce_claim_readings.exs
```

Outputs go to ignored `tmp/verification/claim-reading`. These focused readings
help inspect selected declarations. Full acceptance needs a matching report
for the complete required scope.

## Compare source versions

Use trusted local Git worktrees. From the repository root, stage each snapshot:

```sh
python3 apps/review_web/scripts/stage_part3_snapshot.py \
  --source /absolute/path/to/trusted/worktree \
  --destination /absolute/path/to/hold_ledger/tmp/review_studio/snapshots
```

Provision compatible pinned dependencies offline in each snapshot's ignored
`tmp/part3_build` directories. Under **Compare source versions**, select the
staged snapshots. **Run on both versions** evaluates the active input in separate
BEAM processes. The opening **Example change** is a built-in illustration.

Compare each claim's covered inputs and permitted outputs, then compare the
implementation results. A stored difference supplies a concrete policy-review
case. Finding no difference in the tried cases leaves equivalence unproved.

Process isolation prevents module mixing; it does not sandbox hostile source.
The browser neither installs dependencies nor accepts executable uploads.

## Ask an assistant

Type a header question and choose **Ask an assistant**, or press Enter, to
submit it with the displayed case and source. On smaller screens,
**Ask an assistant** opens the question panel; **Send question** submits it.
Local learning links let you continue reading without a model request.

Before submitting, inspect **Shares case + source** or **Context**. The preview
shows the prompt and context: selected input and output, policy, Ledger and
Spec source, runtime and processor guides, and active claim and Lean excerpts.
Private review notes are excluded. The app refuses oversized or stale context.
Each submission authorizes that question and its displayed context.

The configured provider is **Codex**, using existing Codex authentication.
`QuestionContext` requests `gpt-6.1-terra` with medium reasoning. The model has
no editing or shell tools, and the app uses no fallback provider. Answers appear
beside the case with source links and response details. They are generated
explanations; use evidence panels to inspect proof results.

**History** searches local questions and reopens saved answers without calling
the provider. Copy or export a question, submit a follow-up with its historical
case, or select **Ask using current case**. Typing, inspecting context, reopening
history and reloading send no request. Question actions preserve pending events
and review notes.

Prompts, source context, answers, errors and request events are stored in
ignored `tmp/review_studio/questions/<trace-id>/events.jsonl` with owner-only
permissions. Logs exclude credentials and private provider reasoning. A request
must be logged before it is sent. If an answer cannot be saved, the page reports
the failure. Cancellation, timeout and restart never resend automatically.
**Clear history…** asks for confirmation and refuses deletion while a question
is running.

## Use help and the glossary

**Help** opens guidance for the current page. **Help with controls** lists its
actions; select one to read what it does without running it. Term help combines
a definition, repository example, reason it matters, limits and further reading.
These controls work with touch, mouse and keyboard.

**Extra explanations** shows or hides inline hints independently of
Guided/Inspector. Press `?` outside a text field to open page help. Escape closes
help and returns focus to its control.

The [Glossary](http://localhost:4000/glossary) covers payment, proof and review
terms. Search technical names such as *candidate*, *pointwise*, *binding* or
*fencing* to find their interface explanations. Public term IDs and aliases
keep source references and contextual help connected as labels become clearer.

## Configuration and local records

| Setting or record | Location and behavior |
|---|---|
| Ledger checkout | `HOLD_LEDGER_REVIEW_ROOT`; defaults to the containing repository. Startup checks the checkout and compiled Ledger/Spec identity. |
| HTTP port | `PORT`, default `4000`; the development endpoint binds to `127.0.0.1`. |
| Inference client | `config/config.exs` uses the ASM adapter with the Codex provider and SDK lane. Question model and reasoning settings are in `QuestionContext`. |
| Review sessions and notes | Stored beneath ignored `tmp/review_studio/reviews` in the selected checkout. Session saves and note saves have separate revision checks. |
| Source-comparison packages | Stored beneath ignored `tmp/review_studio/packages`; snapshots are staged under `tmp/review_studio/snapshots`. |
| Assistant history | Owner-only event logs beneath `tmp/review_studio/questions`; clearing this history leaves notes and timelines intact. |
| Focused Lean readings | Generated under ignored `tmp/verification/claim-reading`. |
| Unsaved Lab edits | Temporary until Save to timeline; Reset returns to saved history and reload discards pending work. |
| Claim Lens answers | Transient page state, with Markdown copy after confirmation. |

Keep local records and generated material out of commits. Exports carry the
case or review data identified by their controls; they are records for review,
not proof certificates. When relevant source changes, rebuild and restart the
app before new source-bound computations.

## Find pages and authored content

Routes stay available for direct links:

| Page | Route | What it contains |
|---|---|---|
| Overview | `/` | The payment problem and starting points. |
| Payment walkthrough | `/start` | The computed missing-reply history. |
| System guide | `/system` | Components and seven ledger states. |
| Payment requirements | `/guarantees` | Six required payment behaviors. |
| Elixir to Lean | `/translation` | Exact-fit source, law and available generated material. |
| Claim Atlas | `/atlas` | Registered groups in eight curated families. |
| Claim profile | `/atlas/:slug` | An individual group's explanation and source links. |
| Case Lab | `/lab` | Inputs, code results, What-if outputs and case checks. |
| Claim case | `/claims/:slug` | Case Lab with that claim selected. |
| Saved case | `/claims/:slug/:id` | A saved review session. |
| Claim Lens | `/lens/:slug` | Two supported Claim Lens practice studies. |
| Reading map | `/how-it-fits` | Policy, implementation, claims and evidence relationships. |
| Deliberate bugs | `/examples` | Ten committed source faults and their examples. |
| Read a claim | `/proofs` | Input conditions and required results. |
| Evidence and assumptions | `/assurance` | Evidence types and external requirements. |
| Repository map | `/repository` | Relevant source and all eighteen examples. |
| Glossary | `/glossary` | Definitions, aliases, examples and reading links. |

### Where the content lives

| Source | What to edit or inspect |
|---|---|
| `priv/education_claims.json` | Group titles, cases, expected behavior, related examples, limits and source provenance. |
| `priv/education_examples.json` | M1–M10 and P01–P08 descriptions with unchanged source and fixture links. |
| `priv/education_glossary.json` | Term definitions, stable IDs, aliases, examples, limits and further reading. |
| `priv/education_help.json` | Page guides, control explanations and explicit reasons for self-explanatory controls. |
| `lib/hold_ledger_review_web/education.ex` | Catalog-backed navigation, requirements, families, state descriptions and content lookup. |
| `lib/hold_ledger_review_web/learning.ex` | Computed walkthrough, mutation readings and translation source material. |
| `lib/hold_ledger_review_web/live/education_live.ex` | Learning-page presentation, navigation and inline teaching copy. |
| `lib/hold_ledger_review_web/components/learning_components.ex` | Chapters, claim relationships, processor possibilities and source-reading controls. |
| `assets/css/app.css` | CSS entry point. Shared layouts load before the theme and page styles. |
| `assets/css/interface.css` | Shared colors, navigation, educational pages and responsive layouts. |
| `assets/css/case_workbench.css` and `claim_lens.css` | Scoped layouts for the two review tools. |
| `lib/hold_ledger_review_web/review_copy.ex` | Shared case-result and evidence labels. |
| `lib/hold_ledger_review/claims.ex` and `claims/` | Registered source and compiled case evaluator. |
| `lib/hold_ledger_review/claim_probe.ex` | Supported concrete case checks. |
| `lib/hold_ledger_review/proof_reading.ex` and `proof_evidence.ex` | Source readings, source identity and verification-report interpretation. |
| `lib/hold_ledger_review/review_workspace.ex` | Case history, saved work and review operations. |
| `lib/hold_ledger_review/questions.ex` and `question_context.ex` | Question lifecycle and displayed model context. |
| `scripts/` and `test/` | CLI, content checks, Phoenix tests and browser tests. |

For a copy change, preserve term IDs, selectors, source references and claim
mappings. Keep labels consistent across the screen, help and this guide.
Keep the CSS import order explicit: `review_base.css` retains the existing tool
layouts, followed by `interface.css`, `case_workbench.css` and `claim_lens.css`.
An explanation interprets existing policy; changing the policy or formal
statement requires the review described in [Human review](https://github.com/nshkrdotcom/hold_ledger/blob/main/guides/human_review.md).

## Use the command interface

Write a JSON request file. From the repository root, run:

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

For individual conditions, use `explain_claim` with a `slug` and a `witness`
containing complete `before`, `event` and `output` values. The command uses
the screen's evaluator and source readings with a separate scratch store.
Request files are limited to 64,000 bytes. It opens no HTTP listener and sends
no model request.

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

`precommit` compiles with warnings treated as errors, checks formatting, runs
strict Credo and Dialyzer, and runs Phoenix tests. Python content checks validate
the authored catalog, glossary and help data. Compilation and runtime interaction
need their corresponding checks.

With Phoenix running, use a separate terminal:

```sh
cd apps/review_web/test/browser
npm ci
npx playwright install chromium
npm test
```

Supply real compatible `PART3_TEST_BASELINE_ID` and `PART3_TEST_PROPOSAL_ID`
values for isolated-source comparison. Claim Lens checks are in
`test/browser/0810_claim_lens.spec.cjs`.

From the browser-test directory, `npm run test:presentation` loads the app's
help JavaScript and content into local fixtures without Phoenix. The normal
`npm test` suite exercises rendered LiveView screens.

`npm run test:questions` manages its own Phoenix fixture on port 4001. It checks
question submission and local persistence without provider calls; live answer
quality is outside that check.

Ordinary tests, formal verification and external assumptions have different
evidence requirements. Follow the [verification guide](https://github.com/nshkrdotcom/hold_ledger/blob/main/guides/verification.md)
for a fresh formal run; the web checks above are not full proof acceptance.

## Troubleshooting

| What you see | What to do |
|---|---|
| The payment example is unavailable | Read its source or execution problem, resolve it, then choose Reload example. Policy and claim pages remain available. |
| Source no longer matches the loaded evaluator | Recompile and restart against the intended checkout. Refreshing the page alone cannot update compiled code. |
| Generated Lean or a proof connection is unavailable | Check source identity and available verification files. Produce focused readings using the command above when appropriate; inspect their recorded scope. |
| Another tab changed a session | Read which commands saved, inspect the current timeline and keep track of remaining unsaved work before retrying. |
| An edited output no longer has a result | Correct the edit and check it again. The earlier successful check was cleared so it cannot describe different values. |
| A source comparison cannot run | Check that both trusted snapshots have compatible pinned dependencies provisioned offline. |
| An assistant request fails | Inspect the displayed error and local history. Check existing Codex authentication and the displayed context before submitting a new request. No automatic resend occurs. |
| A case check is outside the claim's scope | Read the excluding input condition and compare it with policy. A different input or claim may answer the question. |

## License

Released under the [MIT License](LICENSE).
