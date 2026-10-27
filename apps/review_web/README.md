# Hold Ledger Claim Workbench — source engine

This directory is a **separate Phoenix Mix application** built against the pure
Hold Ledger checkout. Milestone A replaces the old Review Studio evaluator,
tuple codec, fixed teaching cases and receipt/AI explanation flow. The old
`/review` and receipt routes are **removed**. The only application workflow
is the **Milestone B source-anchored human workbench**, available at `/` and
`/workbench`; `/workbench/:id` reopens a durable local review. A source-claim
probe makes **no model, formal-checker or remote-processor call**.

The current application has **one** claim evaluator:

- `HoldLedgerReview.Claims.Source` validates all registered DSL and native Lean
  catalog paths against a live checkout inventory, reads trusted Elixir law AST
  and binds the exact source bytes plus relevant dependencies to an independent
  digest. `HoldLedgerReview.Config.source_matches?/1` separately checks the
  compiled pure Ledger/Spec source. Build-time dependency hashes and core BEAM
  identities also prevent a restart with stale compiled code from blessing
  changed evaluator source.
- `HoldLedgerReview.Claims.Compiler` audits supported `requires`/`expects`
  expressions, resolves approved aliases, demands identical reducer-call
  signatures and replaces every occurrence with a hygienic candidate output.
  One generated in-memory module is compiled **once at startup**, not per
  request, user input or model output.
- `HoldLedgerReview.Claims` owns the generation, diagnostics and loaded-code
  identity. Every new probe compares the fresh source and loaded-code
  fingerprints. Drift yields `:source_or_compiled_code_drift`, requires a
  controlled rebuild/restart and never hot-purges an active evaluator.
- `HoldLedgerReview.ClaimProbe` binds actual event arguments and source
  `Spec.lookup` entry equalities, enumerating all eligible bounded entries
  (including entries at keys different from the event key). It compares the
  exact generated actual and substituted source expressions, checks independent
  `Spec.expected_step`, and reports per-binding provenance, completeness and
  the bounded four-label result. A different reducer operation is marked
  `:not_probed`, not silently treated as a green claim.
  Only required positive lookup equalities justify finite entry enumeration;
  an optional equality under `or` cannot certify an exhaustive domain.
- `HoldLedgerReview.TermCodec` is the **only** native event/effect/state/output
  codec. Events/effects use exact `type`/`key`/`amount` JSON with `null` for
  arity-two operations; outputs use exact `after`/`result`/`effects`. Statuses,
  results, integers, list sizes and properties are allowlisted. A shape-valid
  hypothetical after-state may fail `HoldLedger.Spec.valid?/1` and still be
  evaluated. `HoldLedgerReview.Canonical` hashes only validated JSON and uses
  the typed output codec for native values, with no generic tuple fallback.

These modules do **not** assert that a hypothetical passes Lean. The original
`test/laws` declarations and independent `HoldLedger.Spec` remain unchanged.
Native Lean obligations are catalogued but never fabricated as compiled Elixir
contracts. Formal status requires an independently checked source-matching
report; the available `ProofEvidence` parser does not execute a checker.

## Local development

Use the pinned Elixir **1.20.4**, OTP **29.1.2** and repository toolchain. From
the repository root:

```sh
cd apps/review_web
mix deps.get --check-locked
mix compile --warnings-as-errors
mix test --warnings-as-errors
mix precommit
mix phx.server
```

Open `http://localhost:4000/` for the human workbench, or `/workbench` to
list/create durable reviews. Choose P01–P08, explore source and typed graph,
edit raw bounded JSON as a complete what-if witness, and submit a human judgment
or pin. The store re-evaluates **the submitted complete witness**, atomically
persists matching source/probe/answer and maintains independent human and
document revisions. Source/report generation drift makes existing reviews
read-only; rebuild/restart and begin a new review. The app must not start
`HoldLedger.Server`, perform remote operations, or synthesize a proof report. If a
registered law, predicate, compiler or loaded module changes in development,
stop probing and rebuild/restart before relying on results.

Run the root suite independently from the root checkout, including
`test/claim_source_parity_test.exs`, which compares the AST extraction against
the root Lynx-dependent `HoldLedger.ProofCase.law_declarations/1` in its own
test environment. Phoenix never imports that test-only module at runtime.

B workbench modules are `lib/hold_ledger_review/{design_graph,dossier,adversarial,review_store,review_report}.ex`,
`lib/hold_ledger_review_web/live/workbench_live.ex`, and the source and export
controllers. The eight bounded seed JSON fixtures live in `priv/scenarios/`.
Current record shape is specified by the separately managed milestone docset's
`contracts/review.schema.json`, not a backward-compatible migration.

The tests in `test/hold_ledger_review/` exercise graph provenance, pointwise
candidates, the current document shape and store transactions; tests in
`test/hold_ledger_review_web/` exercise the LiveView and source/export routes.
For browser checks, start Phoenix in a separate terminal, then run `npm ci`,
`npx playwright install chromium`, and `npm test` from `test/browser/`. The
committed lockfile was resolved by a real npm installation. The browser tests
create synthetic review files under ignored `tmp/review_studio/reviews/`.

For offline, isolated M1–M10 reducer observation from the code root, run:

```sh
uv run --locked python scripts/harvest_mutants.py --execute
uv run --locked python scripts/local_run.py --cwd apps/review_web mix run scripts/assess_mutant_harvest.exs -- ../../tmp/verification/mutant-harvest.json
```

The harvester forces scratch compilation and records source SHA-256, loaded
BEAM identity, complete outputs and concrete assertion results. The assessor
uses the original A evaluator and records both tested rows and the unexamined
catalog. Native operations outside the review codec stay explicitly unprobeable;
they are not escapes or formal failures. Static manifests never claim observed
outputs. Generated logs and reports stay ignored.

For a manual no-server challenge to the contract's meaning, use
[`guides/interactive_review.md`](https://github.com/nshkrdotcom/hold_ledger/blob/main/guides/interactive_review.md). Product, transaction and evidence specifications for the B workbench and
later configured AI C phase live in the separate milestone docset. Nothing
here changes root proof acceptance or human policy authority.
