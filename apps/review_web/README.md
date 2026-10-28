<p align="center">
  <img src="assets/review_web.svg" alt="Hold Ledger · Verification" width="200" height="200">
</p>

# Hold Ledger · Verification

[![GitHub](https://img.shields.io/badge/GitHub-hold__ledger-181717?logo=github)](https://github.com/nshkrdotcom/hold_ledger)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

Explore a law while keeping its concrete case and proof context visible. The workspace places the contract and operands on the left, the active transition and candidate output in the center, and the verdict and evidence inspector on the right. A compact timeline records branches above them.

The default admission example changes `amount <= remaining` to `amount < remaining`. At exact fit, the illustrated proposal stops covering the input while the checkout still admits it. Attach two trusted local snapshots to replace that illustration with an actual source comparison and isolated replay.

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

## Explore one connected case

The three columns remain together on desktop and stack on narrow screens:

| Instrument | What it does |
|---|---|
| Contract and clauses | Shows the changed condition, original claim expressions, bound values and AND / OR / NOT structure. Helper inspection stays within the workspace. |
| Active transition | Shows the starting account, event controls and actual versus hypothetical output. Boundary controls change the active case. |
| Verdict and evidence | Keeps state validity and the selected law beside the candidate. The inspector opens proof source, premises or notes without replacing the case. |

Use **Below / Exact fit / Above** or enter an amount. A **transient branch** appears on the timeline, and the account, outputs, clause evaluation and replay use that same input. This writes no history. **Append this case to trace** keeps it; **Discard** restores the recorded case. Selecting a recorded event leaves the transient branch.

Precondition applicability, candidate permission and actual execution answer different questions. A failed precondition does not mean that the implementation rejects the input. For real two-source replay, **Choose local source pair** selects registered trusted snapshots. The replay action explains this prerequisite inline.

Mutation chips change the candidate immediately: remove effects, zero counters, change the first identity or propose premature release. Click a candidate status to cycle its bounded statuses. The adjacent verdict updates on change. Counters stay as entered until **Recalculate totals**; changing an entry never silently repairs its accounting. **Structured / JSON editor** provides complete typed editing when a chip is insufficient.

**Try six output variations** checks a seeded, bounded set of candidates against the original selected claim. Its candidate and verdict update in place; cases, seed, elapsed time and cancellation remain visible. This is neither general fuzzing nor proof of safety when no variation is rejected.

Quick lifecycle buttons append the next event from the displayed actual output. If an input is transient, appending first preserves that input as a recorded branch. **Continue hypothetical branch** instead preserves the candidate and its descendants as hypothetical. The custom event builder remains available for other keys, amounts, declines, restarts and coupled-model events.

The **Premises** inspector selects an authorized or voiding entry from the active result. Its fencing experiment uses that key and amount, then contrasts terminal confirmation with a deliberately resurrected remote authorization. It does not test a real bank or change the session. When the active result has no suitable entry, a button opens a separate pending-void worked case.

The **Proof** inspector displays actual source and exact source anchors. Registered lemma and generated-artifact buttons open matching source inline; raw source downloads remain available. Captured Lean hypotheses and goal states are explicitly unavailable. Source readings and individual executions do not establish universal formal acceptance.

All 49 catalog obligations remain readable. Native Lean obligations retain their explicit lack of an executable Elixir counterpart. Example concerns are stored as scoped local notes; actual evidence dispositions use the original revision-checked review store. Neither authorizes policy, blocks a PR nor grants formal acceptance.

## Step, adjust and branch

The state machine shows reserved capacity, remembered identities and statuses. Select an earlier event on the timeline, then append an event to branch from that state. Other branches remain selectable. **Adjust starting state** changes limits, counters and entries in a new session.

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
