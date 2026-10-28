<p align="center">
  <img src="assets/review_web.svg" alt="Hold Ledger · Verification" width="200" height="200">
</p>

# Hold Ledger · Verification

[![GitHub](https://img.shields.io/badge/GitHub-hold__ledger-181717?logo=github)](https://github.com/nshkrdotcom/hold_ledger)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

Review a guarantee through a concrete ledger case. The page shows the requirement and changed condition first, then the input, executed output and a drafted alternative. Source coverage and candidate checks appear beside the case. Proof source, clause observations and external assumptions follow below.

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

## Explore a case

Choose a law in the top bar. Read its policy source and changed condition, then adjust the active input with **Below / Exact fit / Above** or an amount. The outputs and clause observations update without changing saved history. **Save case** records that input; **Discard** restores the selected recorded case.

The findings distinguish two comparisons:

| Comparison | Question |
|---|---|
| Source coverage | Does each source version's claim cover this input? What did its isolated execution return? |
| Executed checkout / drafted outcome | Does this checkout's claim permit the deliberately drafted output? |

The default source comparison is a labeled illustration. Attach a trusted local source pair for actual isolated executions. A precondition excluding an input does not tell you that the implementation rejects it. A contract accepting a drafted output does not tell you that the implementation produces it.

**Change drafted output…** opens the secondary tools. Remove an effect, zero counters, change an identity, or use the complete state / JSON editor. The drawer header reports the current candidate check. Counters stay as entered until **Recalculate totals**. **Try six output variations** records its seed, case count and elapsed time; it is a bounded experiment, not a general solver. Escape closes the drawer and returns focus to its opener.

## Record and step through history

Select a saved event on the timeline to inspect its starting account and resulting state. **Record event…** opens a custom event form. Recording is refused while an unsaved scratch case is active: save or discard it first. The action never silently saves a prefix. Selecting an earlier saved state and recording from it creates a branch; the other branch remains selectable.

**Record hypothetical branch**, in the draft tools, continues from a deliberately drafted output. That branch and its descendants stay labeled hypothetical. For example, continue from premature release and request another 100 cents, then compare the admission with the actual pending-void branch where capacity remains reserved. This does not claim the actual implementation releases early.

**Edit starting state** edits limits, counters and remembered entries in a separate session. Structured and JSON editing share the original bounded codec: at most eight entries and integers up to 1,000,000. Inconsistent candidate totals are allowed as a challenge; continuing from a candidate requires a valid state.

## Inspect clauses and assumptions

**Clause evidence** shows exact claim expressions and observed operand values. Select a binding when a law ranges over several entries; every binding remains part of the overall case result. A helper's **Definition** opens its evaluated body. No expression is re-evaluated by the presentation layer.

The terminal-fencing experiment selects an eligible entry and compares confirmation with a deliberately resurrected modeled authorization. It changes no trace and tests no real bank. **Coupled processor model** opens the original Exposure model, separating local knowledge from modeled remote records across dispatch, timeout, observation and confirmation.

## Follow the proof

**Proof source and dependencies** and **External assumptions** open independently. Reading a lemma or registered artifact adds its source below the proof rather than replacing it. Proof stages navigate actual source anchors; captured Lean hypotheses and goal states remain unavailable.

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

Provision compatible pinned dependencies offline into each snapshot’s ignored `tmp/part3_build` directories before replay. Use **Choose local source pair** to select the registered snapshots. The exact identities accompany the comparison. Each version executes in a separate BEAM process through the original source-derived evaluator. Dirty changes and deletions are identified by content, not branch name.

The comparison distinguishes an excluded input, an unwanted output permitted by a contract, and an observed implementation difference. A failed search establishes none of their universal negations. Separate processes prevent module-version mixing; they do not make hostile code safe. Browser actions neither install dependencies nor accept executable uploads.

## Keep a review record

The top bar records scoped concerns against the selected stored comparison witness. With no pair, it records an explicitly labeled example concern. Full evidence and notes remain under **Review history and notes**. These actions do not authorize policy, merge a PR or grant formal acceptance. All 49 catalog obligations remain readable; native Lean obligations explicitly lack an executable Elixir counterpart.

Save a challenge to retain its input, candidate, selected law and source identity. Record a concern separately. Download the session to retain branches, challenges and notes. Concurrent edits use revision checks; stale tabs cannot overwrite newer records. Source drift prevents further execution or writes.

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
