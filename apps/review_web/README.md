<p align="center">
  <img src="assets/review_web.svg" alt="Hold Ledger · Verification" width="200" height="200">
</p>

# Hold Ledger · Verification

[![GitHub](https://img.shields.io/badge/GitHub-hold__ledger-181717?logo=github)](https://github.com/nshkrdotcom/hold_ledger)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

Move a request across a capacity boundary, follow the clause that changes, and play through the assumptions behind a proof. The visual laboratory connects account diagrams, executable conditions, an illustrated proof player and a local/remote exposure sandbox.

The default case compares a pending void with a deliberate early release. Both outputs have consistent accounting; the retention law rejects the early release. The account and clause views use actual local execution. Proof-storyboard frames and assumption failures are labeled illustrations, with original source and checking evidence available in the inspector.

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

## Explore the visual laboratory

| Instrument | Interaction |
|---|---|
| Account diagram | Compare before/after capacity, occupied slots and remembered hold identities. Switch between the actual and hypothetical output. |
| Expression tree | Follow source-derived checks and concrete operands. Hover, focus or pin a clause to highlight its capacity, identity or status in the account. |
| Proof player | Step or play through given facts, a goal and the source tactic. These frames reconstruct a proof reading; they are not captured Lean Infoview states. |
| Assumption sandbox | Disable fencing or durability and scrub the local/remote sequence. Uncovered remote exposure appears separately from local capacity. |

Choose `po_a2` and use the amount dial or **Below / Exact fit / Above**. The real evaluator updates its eligibility operands immediately. At 101 against 100, the precondition fails and no postcondition promise is evaluated. **Add to trace** preserves a preview as a new branch; moving the dial alone writes nothing.

In the fault sandbox, disable **Terminal fencing**, then jump to delayed delivery. Local capacity remains zero while the hypothetical processor resurrects 100 cents of remote exposure. Restore fencing to compare with the original Exposure model. Disabling **Durable local record** illustrates an orphaned remote authorization after local recovery loses its identity. These experiments neither mutate the actual session nor change governing models or policy.

**Find a rejected output** tries a small seeded set of hypothetical output variations against the selected real claim, off the LiveView request path. Its result includes cases tested, elapsed time and seed. A result is rechecked before display; cancellation and context changes cannot promote a late result. This is bounded single-source candidate discovery, not general fuzzing, two-version divergence, a universal proof or a promise that every run finds a problem.

The main account/clause path is executable. The proof player is a source-guided illustration. The fault sandbox uses the original model for the conforming prefix and explicit counterfactual state projections for assumption failures. Formal acceptance still comes only from the original report validator.

Open **Inspect source, edit state & review evidence** for full contracts, every tested binding, helper definitions, actual Lean declarations, generated sources and formal status. All 49 catalog obligations are readable; native Lean obligations retain their explicit lack of an executable Elixir counterpart. The admission, timeout-validity and retention readings have illustrated proof sequences. Other obligations keep their actual source without invented storyboards.

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
