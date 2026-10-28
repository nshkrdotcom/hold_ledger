<p align="center">
  <img src="assets/review_web.svg" alt="Hold Ledger Explorer" width="200" height="200">
</p>

# Hold Ledger Explorer

[![GitHub](https://img.shields.io/badge/GitHub-hold__ledger-181717?logo=github)](https://github.com/nshkrdotcom/hold_ledger)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

Step through a payment hold and examine what its laws promise. Change an amount, apply a timeout, or branch from an earlier step. The explorer shows the account state alongside the governing requirement, source definitions, concrete results and available proof evidence.

This is a separate Phoenix application inside the Hold Ledger repository. It executes local models; it does not send payments or contact an AI provider.

## Start the app

Use the repository's pinned Elixir/OTP toolchain. From the repository root:

```sh
uv sync --locked
uv run --locked python scripts/onboard.py --profile runtime --provision
uv run --locked python scripts/local_run.py --cwd apps/review_web mix deps.get --check-locked
uv run --locked python scripts/local_run.py --cwd apps/review_web mix assets.build
uv run --locked python scripts/local_run.py --cwd apps/review_web mix phx.server
```

Open [localhost:4000](http://localhost:4000). Setup details are in [Getting started](https://github.com/nshkrdotcom/hold_ledger/blob/main/guides/getting-started.md).

## Explore one guarantee

Start with an amount limit of **100 cents** and **two hold slots**. Apply a request for 100 cents using identity 11, then dispatch it and apply a timeout. The entry becomes `unknown`, but its amount and slot remain reserved. A second request cannot reuse that capacity.

The four panels follow the selected transition:

| Panel | What to inspect |
|---|---|
| Guarantee | The intended behavior and its governing policy source |
| Source & change | The law, its conditions, the independent reference and implementation |
| Concrete result | The returned result, requested effects and reference output |
| Assumptions & evidence | The claim's limits, external premises and source-matching proof report |

Move the scrubber or select a timeline step to examine an earlier state. Apply a different event there to create a branch. Previous branches remain available. **Adjust starting state** opens limits, counters and entries; saving creates a new trace. Recalculate counters explicitly when needed. An inconsistent starting state cannot execute.

The account display uses integer cents. `100` means one dollar, not one hundred dollars. Up to eight remembered entries and numbers from 0 to 1,000,000 can be represented; request and entry amounts must be positive.

## Challenge an output

Select a local-ledger transition and choose **Try a different outcome**. Edit the output JSON, then check whether the applicable source claims reject it. For example, change the used-amount counter after admission while keeping the reserved entry.

Candidate counters stay as entered. **Recalculate used totals** changes them only when selected. Invalid accounting can still be checked as a hypothetical output, but continuing from that output requires a valid state. Hypothetical branches and their continuations keep that label.

When a claim accepts your candidate, that result covers the tested input and bindings. It has not established that Ledger produces it or that the claim holds universally. An input outside a law's precondition is outside that law's promise; it is not automatically an implementation rejection.

## Separate delivery from observation

Choose **Ledger + modeled processor** when starting a trace. This executes the original `Exposure` model. Local request and dispatch events are separate from remote authorization delivery and local observation.

Try remote approval, local timeout, observation of approval, local void, remote terminal void and observation of confirmation. Capacity remains reserved until the final observation. A later authorization delivery for the same identity cannot resurrect it in this model.

The modeled processor assumes truthful outcomes, persistent identities and permanent terminal fencing. An actual processor's compliance needs external evidence. This view supplies neither an independent exposure oracle nor a pointwise implementation of native Lean obligations. Hold Ledger models authorization holds, not settlement.

## Compare two source versions

Comparison is optional. First select two operator-trusted Git worktrees with compatible pinned dependencies. Stage each from the repository root:

```sh
python3 apps/review_web/scripts/stage_part3_snapshot.py \
  --source /absolute/path/to/trusted/worktree \
  --destination /absolute/path/to/hold_ledger/tmp/review_studio/snapshots
```

The script identifies exact content, including dirty changes and deletions. Provision each snapshot's dependencies offline into its ignored `tmp/part3_build` directories before replay, using the repository's pinned wrapper. No browser action downloads dependencies or accepts executable project uploads.

Enter the two printed snapshot IDs in **Compare source versions**, then replay a selected local-ledger transition. Each version runs in a separate BEAM process through the original evaluator. The page shows source differences, replay progress and the distinctions supported by completed runs. Cancellation, failed execution and missing evidence remain visible.

Separate processes prevent module-version mixing. They do not make hostile source safe to execute. Unsupported evaluator or representation correspondence is refused. Bounded examples cannot establish equivalence.

## Inspect evidence and record reasoning

Source buttons open files of up to 256,000 bytes with their hashes. Claims are evaluated through the original source-derived compiler and `ClaimProbe`; unsupported bindings remain unresolved. Native Lean obligations remain visible in the catalog without invented executable counterparts.

Formal acceptance comes only from the original `ProofEvidence` source-matching report validator. The inspector exposes available translations, dependencies, exports, axiom scope and six checker configurations. Missing artifacts stay missing; a suite export does not establish a theorem-specific axiom footprint. A stored report is not a new proof run.

Record a concern, a scoped consideration or a need for evidence beside the selected step. These records preserve human reasoning separately from computation and formal acceptance. Export the trace to retain its source identity, branches and notes. Another tab cannot overwrite a newer revision. Source drift makes prior traces read-only; rebuild and start a new trace for new source.

Old `/workbench/:id` and `/changes/:id` records have a read-only archive view. Original source/artifact links and review exports remain available where their source checks permit them. The old questionnaires and competing review screens have been removed. No old record is silently migrated.

## Use the same executor from a local command

Create a request file containing:

```json
{
  "operation": "step",
  "mode": "ledger",
  "before": {"amount_limit": 100, "hold_limit": 2, "used_amount": 0, "used_holds": 0, "entries": []},
  "event": {"type": "request", "key": 11, "amount": 100}
}
```

Then run from the repository root:

```sh
uv run --locked python scripts/local_run.py --cwd apps/review_web \
  mix run --no-start scripts/explore.exs -- /absolute/path/to/request.json
```

The command calls the same `Trace.execute/3` used by the screen and prints a JSON receipt with source/evaluator identity. It owns separate scratch stores, opens no HTTP listener and dispatches no provider request. Use the returned `after` state as the next request's `before` to explore a sequence. Coupled execution uses the same codec's typed exposure representation. A source request accepts only an allowlisted path: `{"operation":"source","path":"lib/hold_ledger/ledger.ex"}`.

The new interface exposes no provider controls. Existing optional provider adapters retain their configured model and per-request consent requirements; exporting a trace or repair packet grants no permission to send it.

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

`precommit` runs warnings-as-errors compilation, formatting, strict Credo, Dialyzer and Phoenix tests. With Phoenix running, execute `npm ci`, `npx playwright install chromium` and `npm test` in `test/browser`. Set `PART3_TEST_BASELINE_ID` and `PART3_TEST_PROPOSAL_ID` to real compatible staged snapshots to exercise isolated comparison cases; the browser report identifies any unavailable comparison checks.

Tests and concrete replays are separate from full formal acceptance. The [verification guide](https://github.com/nshkrdotcom/hold_ledger/blob/main/guides/verification.md) defines the original proof/export/checker gate; the [human-review guide](https://github.com/nshkrdotcom/hold_ledger/blob/main/guides/human_review.md) explains how to review changed claims and trusted boundaries.

## License

Released under the [MIT License](LICENSE).
