<p align="center">
  <img src="assets/review_web.svg" alt="Hold Ledger · Verification" width="200" height="200">
</p>

# Hold Ledger · Verification

[![GitHub](https://img.shields.io/badge/GitHub-hold__ledger-181717?logo=github)](https://github.com/nshkrdotcom/hold_ledger)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

Explore payment-hold rules by running concrete cases. Read the requirement and its selected formal claim first, then change a request or its alternative output. The two-lane workspace puts checks beside the case, above the related clause and Lean source readings. The page scrolls normally; the editor does not block other controls.

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

## Try a case

Choose a rule. The requirement and source expressions appear first. For exact-fit admission, an explicitly labeled **example** compares `amount <= remaining` with `amount < remaining`: a request using all available capacity is covered by the first and excluded by the second. This is not a recorded baseline/proposal replay.

Enter an amount or choose **1¢ less / All available / 1¢ more**. The page shows what the code returns and whether the rule covers this input. The opening comparison is labeled **Example change**; attach two source versions to replace it with actual isolated runs.

**Code returned** is the computed Ledger result. **What if it returned…** is an editable, *unexecuted* alternative. The adjacent difference list identifies changes to limits, reserved totals, slot counts, result, entry identities/amounts/statuses, effects and list order. Duplicate identities remain distinct occurrences; ambiguous matches are never guessed. Select a status or **Edit alternative**, change money or effects, and see differences and checks update without saving, recalculating counters, or invoking another evaluator.

An alternative can have inconsistent counters. **Recalculate totals** corrects them only when requested. The full state and JSON editor provides the same bounded values: up to eight entries and integers up to 1,000,000.

**Checks for this case** explicitly separate whether the rule applies, whether it accepts the executed result, whether it accepts the alternative, and whether each account balances. False preconditions are **not applicable**, and missing, unsupported or failed observations are **unavailable**, not false. Acceptance of a hypothetical alternative is not by itself a policy violation. A balanced account can still release a hold too early. Multi-binding checks retain their aggregate result when you select one binding to inspect. An invalid edit removes the current successful alternative check instead of showing an old verdict.

## Follow what happens next

**Run another event** opens an inline event form. Try dispatch, timeout, retry, cancellation or confirmation. These steps change the experiment without writing saved history. You can keep going from an unsaved request.

**Continue from this alternative** instead uses the edited result as the starting point for subsequent events. Those steps remain labeled as following an alternative. For example, release a hold early, then request the same capacity again; compare that with the original branch, where the money remains reserved.

Select an earlier step to branch from there. **Reset** discards the experiment. **Save experiment** records its pending commands through the original revision-checked store. Each command saves atomically; if another tab interrupts a multi-step save, the page retains the unsaved suffix and reports the partial result. Reloading discards unsaved work.

**Edit starting state** opens the account fields inline and creates a separate saved session. It never changes the governing payment policy.

## Read the proof and assumptions

**Why this check has that result** shows the observed clauses for the selected binding, with explicit true/false/not-evaluated values. In admission, timeout validity and exposure retention, reviewed links let you select a clause and highlight related Lean reading passages, or select a proof-reading step to highlight its related clauses. These many-to-many readings are validated against exact reviewed source digests, structural AST clauses and unique Lean anchors; stale, absent or ambiguous links are unavailable, not guessed. Other claims and unsupported links remain visible and unlinked. Keyboard and touch use the same buttons.

**Read full proof** expands the actual Lean declaration. Lemma references open source alongside the case. Neither linked passages nor the displayed proof lines represent Lean goal states, kernel dependencies, translation correctness or formal acceptance.

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

**Add observation** is beside the active checks. Its compact inline form reuses the original revision-checked note command, without saving pending experiment events. An observation during unsaved exploration includes its experiment-context digest. Review disposition options are available nearby, while **Review notes** retains full saved history and challenges. Conflicted writes remain refused by the original CAS boundary.

When a selected real comparison has matching evidence and the original packet validator accepts it, **Download local repair packet** (JSON or Markdown) is available beside the result. Without such evidence, the page explains why no packet is available; it does not fabricate evidence, auto-run a comparison or auto-save. Download a saved session from **Review notes** to retain its history. Source drift still prevents stale computations and exports. An observation or exported packet is not policy authorization or formal acceptance.

A local export grants no permission to send source or review content to a model. This interface makes no provider calls.

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

For clause observations, send `{"operation":"explain_claim","slug":"po_a2","witness":{"before":...,"event":...,"output":...}}` with complete typed values. The command calls the same reading and evaluator operations as the screen, returns source identity, and opens no HTTP listener. Unsupported bindings remain unresolved.

## Check changes

From the repository root:

```sh
uv run --locked python scripts/local_run.py mix test test/claim_source_parity_test.exs
uv run --locked python scripts/local_run.py mix test --exclude laws
uv run --locked python scripts/local_run.py --cwd apps/review_web mix precommit
uv run --locked python scripts/local_run.py --cwd apps/review_web mix docs --warnings-as-errors
uv run --locked python scripts/local_run.py --cwd apps/review_web mix assets.build
python3 -m unittest discover -s apps/review_web/scripts -p 'test_*.py' -v
```

`precommit` completes warnings-as-errors compilation, formatting, strict Credo, Dialyzer and Phoenix tests. With Phoenix running, execute `npm ci`, `npx playwright install chromium` and `npm test` in `test/browser`. Supply real compatible `PART3_TEST_BASELINE_ID` and `PART3_TEST_PROPOSAL_ID` values to run the isolated-source browser case.

## License

Released under the [MIT License](LICENSE).
