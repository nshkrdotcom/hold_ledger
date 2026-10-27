# Hold Ledger Claim Workbench — source engine

This directory is a **separate Phoenix Mix application** built against the pure
Hold Ledger checkout. Milestone A replaces the old Review Studio evaluator,
tuple codec, fixed teaching cases and receipt/AI explanation flow. The old
`/review` and receipt routes are **removed**. Until Milestone B implements the
new workbench interface, `/` is a neutral development entrypoint, not an
interactive reviewer. No model, checker or remote processor is called by a
claim probe.

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

Open `http://localhost:4000/` only to check startup. No Milestone A reviewer
UI or AI flow is exposed. The app should start the claim generation without
starting `HoldLedger.Server` or performing journal/remote operations. If a
registered law, predicate, compiler or loaded module changes in development,
stop probing and rebuild/restart before relying on results.

Run the root suite independently from the root checkout, including
`test/claim_source_parity_test.exs`, which compares the AST extraction against
the root Lynx-dependent `HoldLedger.ProofCase.law_declarations/1` in its own
test environment. Phoenix never imports that test-only module at runtime.

Key Phoenix tests: `test/hold_ledger_review/claims_test.exs`,
`test/hold_ledger_review/term_codec_test.exs`,
`test/hold_ledger_review/proof_evidence_test.exs` and route/startup tests.
The first two test modules execute the P01–P08 source-inspection expectations
**only when Mix is run**. Their mere presence is not a passing runtime result.

For a manual no-server challenge to the contract's meaning, use
[`guides/interactive_review.md`](https://github.com/nshkrdotcom/hold_ledger/blob/main/guides/interactive_review.md). Product,
transaction and evidence specifications for the future B/C workbench live in
the separately maintained milestone docset. Nothing here changes root proof
acceptance or human policy authority.
