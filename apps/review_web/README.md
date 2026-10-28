<p align="center">
  <img src="assets/review_web.svg" alt="Hold Ledger · Verification" width="200" height="200">
</p>

# Hold Ledger · Verification

[![GitHub](https://img.shields.io/badge/GitHub-hold__ledger-181717?logo=github)](https://github.com/nshkrdotcom/hold_ledger)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

Explore payment-hold rules by running concrete cases. Change a request, try a different result and follow the next event. The rule, its proof source and the checks explain what each experiment shows.

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

Choose a rule. Its requirement and changed condition appear beside the relevant proof source. The opening example compares `amount <= remaining` with `amount < remaining`: a request using all available capacity is covered by the first condition and excluded by the second.

Enter an amount or choose **1¢ less / All available / 1¢ more**. The page shows what the code returns and whether the rule covers this input. The opening comparison is labeled **Example change**; attach two source versions to replace it with actual isolated runs.

**Code returned** shows the executed result. **What if it returned…** is an alternative you can edit to challenge the rule. Click a status or **Edit alternative**, then change reserved money, remove an action or release a hold. The adjacent checks update while the editor remains open. The rest of the page stays usable.

An alternative can have inconsistent counters. **Recalculate totals** corrects them only when requested. The full state and JSON editor provides the same bounded values: up to eight entries and integers up to 1,000,000.

The checks distinguish accounting from the selected rule. A balanced account can still release a hold too early. The condition view shows the original observed operands; when a rule checks multiple sets of values, the selector changes which set you inspect without removing any from the result.

## Follow what happens next

**Run another event** opens an inline event form. Try dispatch, timeout, retry, cancellation or confirmation. These steps change the experiment without writing saved history. You can keep going from an unsaved request.

**Continue from this alternative** instead uses the edited result as the starting point for subsequent events. Those steps remain labeled as following an alternative. For example, release a hold early, then request the same capacity again; compare that with the original branch, where the money remains reserved.

Select an earlier step to branch from there. **Reset** discards the experiment. **Save experiment** records its pending commands through the original revision-checked store. Each command saves atomically; if another tab interrupts a multi-step save, the page retains the unsaved suffix and reports the partial result. Reloading discards unsaved work.

**Edit starting state** opens the account fields inline and creates a separate saved session. It never changes the governing payment policy.

## Read the proof and assumptions

The proof shows actual source around the selected step. **Read full proof** expands the declaration. Referenced lemmas open their source alongside the rule; the selected case remains available. These source readings are not saved Lean hypotheses or tactic goal states.

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

After exploring, open **Review notes** to save an observation or attach one to a computed comparison result. These are review records, not policy authorization or formal acceptance. Download a saved session to retain its history, challenges and notes. Source changes prevent stale computations and writes; revision checks prevent another tab from overwriting a newer record.

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
