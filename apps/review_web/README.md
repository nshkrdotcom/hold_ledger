<p align="center">
  <img src="assets/review_web.svg" alt="Hold Ledger · Verification" width="200" height="200">
</p>

# Hold Ledger · Verification

[![GitHub](https://img.shields.io/badge/GitHub-hold__ledger-181717?logo=github)](https://github.com/nshkrdotcom/hold_ledger)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

Explore payment-hold rules by running concrete cases. The compact rule header keeps a requirement summary, its exact source, and **Read full claim** together without making long expressions precede the input. Run a request, change an alternative output, and read its differences beside their fields. The experiment and checks occupy two natural-scrolling lanes; selected condition and Lean source excerpts share the reasoning lane. The editor does not block other controls.

The Phoenix app uses the original Ledger, independent Spec and claim evaluator. It sends no payments.

## Run locally

From the repository root, use the pinned tools:

```sh
uv sync --locked
uv run --locked python scripts/onboard.py --profile runtime --provision
uv run --locked python scripts/local_run.py --cwd apps/review_web mix deps.get --check-locked
uv run --locked python scripts/local_run.py --cwd apps/review_web mix assets.build
uv run --locked python scripts/local_run.py --cwd apps/review_web mix phx.server
```

Open [localhost:4000](http://localhost:4000). All amounts are integer cents: `100` means one dollar.

## Explore the Claim Lens

Open [Claim Lens: exact-fit admission](http://localhost:4000/lens/po_a2) or
[Claim Lens: retention](http://localhost:4000/lens/po_exposure_retain).
Use the **Case Lab / Claim Lens / Compare versions** links to switch between
concrete executions, semantic-gap experiments, and the existing trusted local
source-comparison workflow. **Compare versions** opens the Case Lab's snapshot
chooser; it is not a new diff engine or an automatic proof run.

The header's **Claim Lens · 2 examples** link always opens a working example.
It keeps the current claim when that claim has a guided example, otherwise it
opens exact-fit admission. A notice at the top of Lens explains the demo scope
and links directly to both examples. The full claim catalog remains in Case Lab.

Claim Lens is a *separate*, compact LiveView for reading a formal obligation
against an independently stated requirement. Choose a fixed real-world-inspired
witness, select a curated hypothetical precondition edit, and compare:

- the hand-reviewed expectation from `guides/specification.md`, including its
  source location;
- the **unchanged, source-bound** Elixir law's pointwise response to an
  unexecuted candidate result;
- a transparently modeled *hypothetical* precondition with the existing
  promise. The UI never rewrites the law or claims the hypothetical was proved.

**Review first is now the default** at `/lens/:slug` and
`/lens/:slug?mode=challenge`. It withholds curated verdicts, coverage rows,
worked explanations and observed source-path hints until the reviewer selects
an initial classification and presses **Confirm classification and reveal
feedback**. Six broad category families plus a proof-only no-change control
are available; uncertainty is valid. The policy, claim excerpt, case input,
computed output and clearly unexecuted alternative are visible before reveal.
The reviewer may expand the evidence library to read source without receiving
an automated verdict. **Explore freely** at `/lens/:slug?mode=explore`
shows comparison results immediately for learning and QA.

The optional four-part argument form asks for a policy anchor, a contract
provision, a discriminating witness and the limitation or external assumption,
plus a narrative. After confirmation the UI can copy a **local provisional
Markdown argument** to the clipboard. This draft is never scored, persisted,
submitted to a model, or turned into a verified repair packet. Changing the
witness, hypothesis, study or mode, selecting **Try again**, or reloading
clears the attempt. The challenge is practice, not a blinded study; prior
exposure to Explore may have disclosed the answer.

After feedback the **contrast studio** offers three explicitly authored guide
exercises: P02 (missing void effect), P05 (premature release despite effect),
and P08 (legitimate immediate release of a never-dispatched reservation).
These are illustrative comparisons from the guide and scenario JSON, not
freshly executed cases, and no answers appear until feedback is enabled.
An **external-premise reading checklist** helps reviewers name processor
fencing, truthful decline and journal durability without pretending a checked
box proves any of them. A collapsible evidence library separates reviewed
Lean text and source-matched reports from pointwise and hypothetical displays.

After feedback, the three-witness coverage strip shows authored versus
hypothetical input applicability together. “Doesn't apply” means the claim says
nothing about that input; exclusion alone does not establish a policy defect.
The worked challenge includes exact before/event, computed and curated candidate
values. Mutation paths remain references; the page does not execute those patches.
Selecting a semantic hypothetical accents its existing reviewed source clause.

Exact-fit admission demonstrates how adding `amount < remaining` to
`po_a2`'s precondition excludes the 100¢ boundary even though the original
claim rejects a mistaken `:insufficient_amount` output there. Retention shows
that removing `not Spec.release_evidence?(event, key)` from
`po_exposure_retain` would demand retention even after a legitimate terminal
confirmation. The latter is a counterexample to the *hypothetical assertion*,
not a flaw in the original ledger. A **proof-body-only control** avoids
teaching reviewers to flag harmless edits merely because a proof changed.

Select a clause to see its reviewed, digest-validated Elixir ↔ Lean **source
reading** relationship, matching observed condition path when available, and
related Lean source excerpts. The panel distinctly labels live pointwise
checks, Lean text, focused elaboration, and the actual full-gate provenance.
It does **not** manufacture interactive tactic states, kernel dependencies,
formal acceptance for edited claims, or independent policy approvals. The
human-classification and explanation fields are ephemeral LiveView drafts:
**they are not persisted, sent to a model, or added to review notes**. The named mutant
patch and test paths are review references, not tests run by the browser.

The studies are fixed illustrations, not a general editor or proof checker.
Both pages remain read-only with respect to Ledger, Spec, law sources, snapshots
and formal reports.

## Try a case

Choose a rule. The header presents a source-linked requirement summary. **Read full claim** expands the actual `requires` and `expects`, or names a native Lean-only declaration. For exact-fit admission, an explicitly labeled **illustrative example** compares `amount <= remaining` with `amount < remaining`: a request using all available capacity is covered by the first and excluded by the second. Standalone law review has no fabricated source change; real baseline/proposal comparisons show their own full source-change list.

Enter an amount or choose **1¢ less / All available / 1¢ more**. The page shows what the code returns and whether the rule covers this input. The opening comparison is labeled **Example change**; attach two source versions to replace it with actual isolated runs.

**Code returned** is the computed Ledger result. **What if it returned…** is an editable, *unexecuted* alternative. Neutral change tokens sit beside the alternative's reserved money, slot count, limits, result, and unambiguously matched entry/effect fields. **Full differences** expands the complete structured audit list (including order, additions, deletions and ambiguous occurrence correspondence), with its changed-field count kept separate from other rows. An original entry absent from the candidate appears only as a noninteractive, explicitly labeled ghost; it is not in the candidate totals or passed to later events. Repeated identities/effects are never silently paired or re-keyed. Edit **Result** and **Reserved (¢)** directly on the alternative card, select a status, or use **More edits** for detailed changes to money and effects. Markers and checks update without saving, recalculating counters, or invoking another evaluator.

An alternative can have inconsistent counters. **Recalculate totals** corrects them only when requested. The full state and JSON editor provides the same bounded values: up to eight entries and integers up to 1,000,000.

**Checks for this case** distinguishes a changed alternative the rule still accepts (prominent amber), one the rule rejects (calm green), an unchanged output, and cases whose checks are unavailable. The matrix separately reports whether the rule applies, what the rule accepts, and whether each account balances. False preconditions are **not applicable**, and missing, unsupported or failed observations are **unavailable**, not false. Acceptance of a hypothetical alternative is not by itself a policy violation. A balanced account can still release a hold too early. Multi-binding checks retain their aggregate result when you select one binding to inspect. An invalid edit removes the current successful alternative check instead of showing an old verdict.

## Follow what happens next

**Run another event** opens an inline event form. Try dispatch, timeout, retry, cancellation or confirmation. These steps change the experiment without writing saved history. You can keep going from an unsaved request.

**Continue from this alternative** branches from the edited result without replacing the code path. The case timeline shows the shared history and both recorded branches, with a result and reserved-money meter on every applicable step. **Run on both paths** applies one follow-on event to both branch tips; their actual computed outcomes remain side by side. For example, release a hold early and request the same capacity again. The original branch rejects an over-capacity request while the alternative can admit it. These are concrete modeled results, not an automatic safety or policy judgment.

Select an earlier step to branch from there. **Reset** discards the experiment. **Save to timeline** records its pending commands through the original revision-checked store. Each command saves atomically; if another tab interrupts a multi-step save, the page retains the unsaved suffix and reports the partial result. Reloading discards unsaved work.

**Edit starting state** opens the account fields inline and creates a separate saved session. It never changes the governing payment policy.

The output cards keep reserved money, result, entries and actions in view. **Output fields** reveals the complete scalar fields; changed limits open those details automatically. The compact check table keeps applicability, output satisfaction and accounting separate.

## Read the proof and assumptions

Conditions first show short, source-reviewed groups with exact observed true/false/unavailable/not-evaluated counts. Positive-amount boundaries and starting-state invariants are not lumped into a generic green guard badge. Satisfied unchanged checks may be folded, while false, unavailable, skipped and compared-source changes retain explicit attention. **Complete observed expression tree** reveals the original structural paths, mixed operators, helper definitions and operands without replacing the primary view. Claims lacking reviewed grouping receive an honest generic outline. The complete proof remains in the reasoning region, after the condition view.

**Why this check has that result** shows the observed clauses for one selected binding and one output basis without inventing a second evaluator. Selecting a linked clause shows one local Lean passage, its declaration location, line, relation and context; multiple reviewed passages have explicit selectors. Selecting a proof-reading step reveals its matching condition in reverse. These many-to-many source-reading aids are validated against exact reviewed digests, original structural AST paths and unique Lean anchors; stale, absent or ambiguous mappings are unavailable, never guessed. A proof passage is not automatically an isolated proof of its associated boolean. All 49 catalog claims retain the generic/full-source reading path. Keyboard and touch use the same controls; selection survives compatible input edits but not a changed event/basis/binding/source.

**Proof** in the evidence dock opens the complete Lean source, including every registered declaration for a native Lean rule. **Read full proof** provides the same expansion; selecting a reviewed proof step returns to its excerpt. **Conditions** opens the actual source assumptions and promise alongside any evaluated conditions. Helper laws without an event probe show their source directly and mark evaluation unavailable. Lemma references open source alongside the case. Neither linked passages nor the displayed proof lines represent Lean goal states, kernel dependencies, translation correctness or formal acceptance.

**Assumptions** opens the processor model. Select a hold and compare a processor that remembers cancellation with one that later resurrects an authorization. The model does not establish how a real processor behaves. **Open coupled processor case**, in the event tools, separates local knowledge from remote authorization, delivery and terminal confirmation.

All 49 catalog obligations remain readable. Native Lean statements without an executable Elixir counterpart say so.

**Verification files** contains generated sources, matching reports, checker details and unavailable artifacts. To generate focused translation and Lean elaboration for the three primary worked claims, run from the repository root:

```sh
MIX_ENV=test uv run --locked python scripts/local_run.py \
  mix run apps/review_web/scripts/produce_claim_readings.exs
```

This uses the original ProofCase assembler and pinned Lynx runner. Generated artifacts remain under ignored `tmp/verification/claim-reading`. Focused elaboration is separate from full formal acceptance. Only the original `ProofEvidence` validator accepts a matching required-scope report; see the [verification guide](https://github.com/nshkrdotcom/hold_ledger/blob/main/guides/verification.md). Missing evidence stays missing.

## Compare two source versions

Stage operator-trusted local Git worktrees:

```sh
python3 apps/review_web/scripts/stage_part3_snapshot.py \
  --source /absolute/path/to/trusted/worktree \
  --destination /absolute/path/to/hold_ledger/tmp/review_studio/snapshots
```

Provision compatible pinned dependencies offline under each snapshot's ignored `tmp/part3_build` directories. **Compare versions** selects their registered content identities. **Run on both versions** executes the active input in separate BEAM processes using the original evaluator. Neither a branch name nor a historical receipt substitutes for matching source.

Read three results separately: an input excluded by a rule, an alternative output permitted by a rule, and an actual execution difference. No example found does not establish equivalence or safety. Separate processes prevent module mixing; they do not sandbox hostile code. The browser does not install project dependencies or accept executable uploads.

## Keep review notes

**Flag this case** follows the check matrix, condition evidence, and Lean source reading. Use **Flag concern**, **Open question**, or **Mark reviewed**, and optionally **Add context** for a freeform note. A single **How to read this workspace** disclosure near the rule header explains the limits of checks and proof-reading links. The target names the rule/event and saved or unsaved context; these session actions reuse the original revision-checked notes without saving pending experiment events. Unsaved exploration receives an experiment-context digest. When a real source comparison has selected stored evidence, disposition controls instead explicitly name that **stored comparison finding**, not the active scratch case. They use the original human-revision CAS. **Review notes** retains history and challenges; conflicted writes remain refused.

When a selected real comparison has matching evidence and the original packet validator accepts it, **Download local repair packet** (JSON or Markdown) is available beside the result. Without such evidence, the page explains why no packet is available; it does not fabricate evidence, auto-run a comparison or auto-save. Export a saved session from **Review notes** to retain its history. Source drift still prevents stale computations and exports. An observation or exported packet is not policy authorization or formal acceptance.

A local export grants no permission to send source or review content to a model. Questions are sent only through the separate, explicitly consented question control described below.

## Ask about the case

Type a question in the top bar and press **Ask Codex** or Enter. This sends it immediately, including the case and source indicated beside the button. **Shares case + source** lets you inspect the packet locally before sending. **Context** shows the exact application prompt and source material: the selected case and output basis, governing policy, core Ledger/Spec, runtime and processor documentation, and the active law and Lean declaration. Long Lean passages are labeled excerpts; the model receives the displayed lines, while the full proof remains available in the source viewer. Private review notes are not included. The source packet has a fixed size limit; an oversized or stale packet is refused.

On smaller screens, open **Ask**, type your question and press **Send to Codex**. Each explicit submit authorizes only that question and its displayed case/source scope; there is no preparation step or consent checkbox. This feature uses the existing Inference/ASM completion-only adapter with Codex, `gpt-6.1-terra`, medium reasoning. It has no editing or shell tools. Authentication and model access must already work in the operator's existing Codex setup; no fallback provider is used.

An answer appears as a single-line preview in the same bar. Open it to read the explanation and source links. The floating panel does not move or disable the case; Escape and the Close button dismiss it. Explanations are generated answers, not formal evidence or recorded human conclusions. An answer to an older case is labeled accordingly. The response metadata, when supplied by the adapter, records what it reports; a requested model setting alone is not evidence that a provider ran it.

**History** recalls local questions without a provider call. Search within this session or all questions, open an earlier answer, copy/export that question, or explicitly ask a follow-up using its historical case. **Ask using current case** starts from the present workspace instead. Typing, opening context, recalling history and reloading never send a question. Inspecting, answering, recalling and exporting never save pending events or alter review notes.

Application prompts, selected context, visible answers, errors and request lifecycle events are written to ignored `tmp/review_studio/questions/<trace-id>/events.jsonl`, with owner-only permissions. Logs can contain source and question text; credentials and private provider reasoning are excluded. A log-write failure prevents dispatch, and a response-save failure is shown explicitly. Cancel, timeout and restart do not trigger automatic resends. **Clear history…** deletes only question logs after confirmation and refuses while a question is running.

The controlled question browser suite starts and stops its own explicit local fixture on port 4001:

```sh
cd apps/review_web/test/browser
npm run test:questions
```

It exercises actual UI, Inference request construction and local persistence with a controlled completion adapter. It makes no provider calls and does not measure live model quality. The ordinary `npm test` suite still requires the normal Phoenix server and real compatible snapshot IDs.

## Use the same operations from a command

Write a bounded JSON request file, then run:

```sh
uv run --locked python scripts/local_run.py --cwd apps/review_web \
  mix run --no-start scripts/explore.exs -- /absolute/path/to/request.json
```

Supported requests include:

```json
{"operation":"read_claim","slug":"po_exposure_retain"}
```

```json
{"operation":"step","mode":"ledger","before":{"amount_limit":100,"hold_limit":2,"used_amount":0,"used_holds":0,"entries":[]},"event":{"type":"request","key":11,"amount":100}}
```

For clause observations, send `{"operation":"explain_claim","slug":"po_a2","witness":{"before":...,"event":...,"output":...}}` with complete typed values. The command calls the same source-bound reading and original evaluator operations as the screen, exposing `condition_outlines` per observed binding and phase as well as original nodes and paths. Unsupported groupings remain generic and missing links unresolved. No HTTP listener is opened.

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

`precommit` completes warnings-as-errors compilation, formatting, strict Credo, Dialyzer and Phoenix tests. With Phoenix running, execute `npm ci`, `npx playwright install chromium` and `npm test` in `test/browser`. The Claim Lens browser checks are in
`test/browser/0810_claim_lens.spec.cjs`. Supply real compatible `PART3_TEST_BASELINE_ID` and `PART3_TEST_PROPOSAL_ID` values to run the isolated-source browser case.

## License

Released under the [MIT License](LICENSE).
