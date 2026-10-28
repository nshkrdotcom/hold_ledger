<p align="center">
  <img src="assets/review_web.svg" alt="Hold Ledger · Verification" width="200" height="200">
</p>

# Hold Ledger · Verification

[![GitHub](https://img.shields.io/badge/GitHub-hold__ledger-181717?logo=github)](https://github.com/nshkrdotcom/hold_ledger)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

Inspect a law by changing a concrete case, testing an unwanted output, and following the statement into its Lean proof. The page opens on a pending void: the real Ledger retains 100 cents; a hypothetical early release retains zero. Both states have consistent accounting. The retention law rejects the early release.

This separate Phoenix application executes the repository’s local models. It sends no payments and exposes no provider controls.

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

## Read the case and the claim together

| Panel | What you can inspect |
|---|---|
| Concrete contrast | Ledger’s output beside an editable hypothetical output; validity and the selected law evaluated separately |
| Contract deconstructor | Actual `requires` and `expects`, bound variables, operands, true/false clauses and supported helper definitions |
| Lean theorem & proof | Actual theorem signatures, inline law proofs, source-anchored reading steps and referenced lemmas |
| Scope & assumptions | Governing policy, omissions, available checking evidence and links to deployment premises |

Choose `po_b1_void` to see why validity alone allows the early release. Choose `po_exposure_retain` to inspect the missing guarantee. A valid state has consistent counters and well-formed entries; that alone does not establish whether releasing a particular hold was permitted.

The law selector includes all 49 catalog obligations. Some laws have native Lean statements without an executable Elixir counterpart. Some proofs appear inline in the law file rather than as a same-named shared theorem. The page shows those differences; missing generated signatures remain missing. Reviewed explanations are available for admission, timeout validity, void validity and exposure retention. Other claims retain their actual source material.

For `po_a2`, request 99, 100 and 101 cents against a 100-cent limit. The deconstructor exposes the actual `amount <= amount_limit - used_amount` operands. At 101 the precondition is false: that law promises nothing for that input. The implementation’s rejection is shown separately. No browser control rewrites governing source or policy.

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

Provision compatible pinned dependencies offline into each snapshot’s ignored `tmp/part3_build` directories before replay. Enter the exact printed IDs under **Compare two locally staged source versions**. Each version executes in a separate BEAM process through the original source-derived evaluator. Dirty changes and deletions are identified by content, not branch name.

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
