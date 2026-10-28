<p align="center">
  <img src="assets/review_web.svg" alt="Hold Ledger · Verification" width="200" height="200">
</p>

# Hold Ledger · Verification

[![GitHub](https://img.shields.io/badge/GitHub-hold__ledger-181717?logo=github)](https://github.com/nshkrdotcom/hold_ledger)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

Review a changed guarantee against a concrete case. The main view puts the changed condition beside contract applicability, a hypothetical output and actual execution. One recorded-state timeline keeps the account, entries and events together.

The default admission example changes `amount <= remaining` to `amount < remaining`. At exact fit, the example proposal stops covering the input while the actual checkout still admits it. This is a labeled example proposal, not a modification of governing source. Attach two trusted local snapshots to replace it with an actual source comparison and isolated execution.

This separate Phoenix application sends no payments and exposes no provider controls.

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

## Review a change

**Change & case** shows the condition and a comparison table. Precondition applicability, candidate permission and actual execution answer different questions. A failed precondition does not mean that the implementation rejects the input.

Use **Below / Exact fit / Above** or enter an amount. These are scratch inputs: moving a control does not append an event. **Replay scratch input on both sources** runs an attached source pair without changing the recorded trace. **Append this case to trace** explicitly saves a new branch.

**Request repair**, **Needs policy / evidence decision** and **Considered in scope** record scoped reviewer dispositions. An example action records a local concern; actual evidence actions use the original revision-checked review store. Neither authorizes a policy change, blocks a PR nor grants formal acceptance.

The task tabs keep related work together:

| View | What it shows |
|---|---|
| Clauses | Actual source expressions, explicit AND / OR / NOT groups, operands and helper inspection. |
| Proof | Full proof source alongside a selected source stage, referenced lemmas and available generated artifacts. No invented live tactic states. |
| Premises | External assumptions and a current-entry fencing counterfactual. The key and amount come from the selected case; unsupported contexts remain unavailable. |
| Edit output | Actual and hypothetical results, editable state/effects and deliberate inconsistent totals. |
| Review record | Saved challenges, notes and session export. |

The fencing comparison illustrates terminal confirmation followed by delayed authorization for the selected entry. It runs the original local transition and coverage model, then explicitly substitutes a remote outcome when fencing is disabled. It does not test a real processor or alter the session. Other external assumptions remain documented rather than given fabricated fault animations.

**Find a rejected output** checks six seeded hypothetical output variations against the original selected claim. It reports cases, seed and elapsed time; findings are rechecked. This bounded candidate search is not general fuzzing or a proof of safety when it finds nothing.

All 49 catalog obligations remain readable. Native Lean obligations retain their explicit lack of an executable Elixir counterpart. Pointwise executions, proof-source readings and full formal evidence remain separate.

## Step, adjust and branch

The state machine shows reserved capacity, remembered identities and statuses. Select an earlier step or move the scrubber, then apply an event to branch from that state. Other branches remain selectable. **Adjust starting state** changes limits, counters and entries in a new session.

**Edit hypothetical output** changes the returned state, result and requested effects. Counters stay as entered until you choose **Recalculate totals**. Inconsistent outputs can challenge a law; continuing from one requires a valid state. The optional JSON editor uses the same bounded codec as structured controls: at most eight entries and integers up to 1,000,000.

Continue from the early-release candidate, then request another 100 cents. Compare that admission with the original pending-void branch, where the capacity remains reserved. The hypothetical branch and its descendants stay labeled. This experiment does not claim that the actual implementation releases early.

**Coupled processor model** opens the original Exposure model. Step local request and dispatch, remote authorization, timeout, observation, void delivery and confirmation. Local knowledge and modeled remote records update separately. Terminal fencing in that model depends on processor behavior; it is not established for a real processor by running the model.

## Follow the proof

Select a proof stage to read its actual source and follow a referenced lemma to its declaration. These are source readings, not recorded Lean tactic states or kernel dependency footprints. Pointwise clauses explain this case; the theorem states what is universally claimed.

To produce fresh translation sources and focused Lean elaboration for the three primary worked claims, run from the repository root:

```sh
MIX_ENV=test uv run --locked python scripts/local_run.py \
  mix run apps/review_web/scripts/produce_claim_readings.exs
```

This invokes the original ProofCase assembler and pinned Lynx runner. Generated files and source hashes stay under ignored `tmp/verification/claim-reading`. Refresh evidence on the page to inspect matching artifacts. Focused elaboration does not establish full release acceptance, exports, theorem-specific axiom footprints or six-checker consensus.

Only the original `ProofEvidence` validator determines formal acceptance from a matching required-scope report. See the [verification guide](https://github.com/nshkrdotcom/hold_ledger/blob/main/guides/verification.md) for that gate. Missing and stale evidence remain unavailable.

## Compare source versions

Stage two operator-trusted local Git worktrees:

```sh
python3 apps/review_web/scripts/stage_part3_snapshot.py \
  --source /absolute/path/to/trusted/worktree \
  --destination /absolute/path/to/hold_ledger/tmp/review_studio/snapshots
```

Provision compatible pinned dependencies offline into each snapshot’s ignored `tmp/part3_build` directories before replay. Use **Choose source pair** to select the registered snapshots. The exact identities accompany the comparison. Each version executes in a separate BEAM process through the original source-derived evaluator. Dirty changes and deletions are identified by content, not branch name.

The comparison distinguishes an excluded input, an unwanted output permitted by a contract, and an observed implementation difference. A failed search establishes none of their universal negations. Separate processes prevent module-version mixing; they do not make hostile code safe. Browser actions neither install dependencies nor accept executable uploads.

## Keep a review record

Save a challenge to retain its input, candidate, selected law and source identity. Record a concern separately. Download the session to retain branches, challenges and notes. Concurrent edits use revision checks; stale tabs cannot overwrite newer records. Source drift prevents further execution or writes. Old session formats and former `/workbench`, `/changes` and `/explore` routes are not served.

Notes do not authorize policy changes or establish formal acceptance. Exporting any local content grants no permission to send it to a provider.

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
