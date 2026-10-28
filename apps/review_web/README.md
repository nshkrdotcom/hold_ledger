<p align="center">
  <img src="assets/review_web.svg" alt="Hold Ledger Claim Workbench" width="200" height="200">
</p>

# Hold Ledger Claim Workbench — source engine

[![GitHub](https://img.shields.io/badge/GitHub-hold__ledger-181717?logo=github)](https://github.com/nshkrdotcom/hold_ledger)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

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

## Milestone C: optional configured-model collaboration

Milestone C adds one **opt-in** Inference path to the existing workbench; it does
not change the provider/model, add an alternative evaluator, resurrect the
Explainer routes or authorize model-written judgments. It reuses
`Inference.Client.new!/1`, `Inference.capabilities/1`, JSON-Schema
`Inference.Request.from_messages/2`, and `Inference.complete/2` with the
configured ASM/Codex adapter. Without declared JSON-Schema support, requests
fail closed. Failures never block human review or source-based what-if checking.

- `AI` is the configured provider boundary, `AIPacket` creates bounded
  source-linked packets, and `AIProtocol` validates exact schemas plus packet
  IDs/citations, independent pointwise predictions and typed challenge witnesses.
  Canonical contracts remain byte-identical to the docset. The configured
  provider receives a strict wire schema using disjoint `anyOf` event branches
  and locally enforced array uniqueness; every response still passes the full
  canonical schema and semantic checks. Permitted card targets are explicit.
  Source excerpts prioritize policy, complete reducer/oracle and law text before
  large proof files, within the same 64 KiB source budget. Source, prompt and
  report freshness are checked again immediately before dispatch.
  Discovery sends *source-only* graph snippets and unlabeled synthetic probes;
  the hidden rubric, fixture case names, expected matrix, mutant labels and
  human answers are not included. Verified noncontiguous source excerpts are
  marked; source/digest drift refuses a packet. Follow-up sends the latest
  **recorded** human answer, computed evidence and prior model question **only
  on the explicit follow-up opt-in**.
- `AIJobs` starts one pending request per review via the single-writer
  `ReviewStore`, then runs the provider call in `Task.Supervisor` independently
  of the LiveView. A completed result is validated again at the commit boundary.
  A stale human revision/source is discarded; restart interrupts pending work;
  there is no implicit resend. `completion_digest` retains exact-retry
  idempotency. All model questions remain `ai_proposed` suggestions until
  explicitly accepted by a person; the human answer CAS and conclusion remain
  separate.
- The UI requires a fresh checkbox opt-in for **each** request. Source/graph
  evidence is used for discovery; challenge additionally sends the current
  draft; follow-up additionally sends reviewer choice/reason and computed
  examples. The AI history is durable, reveals computed contradictions before
  model readings, links suggestions to sources, and lets the user try a typed
  challenge as an **unsaved** draft.

Controlled ExUnit tests live in
`test/hold_ledger_review/{ai_protocol,ai_jobs}_test.exs`, with a test-only
`test/support/controlled_adapter.ex`; UI no-consent checks live in the LiveView
and Playwright suites. These controlled tests are not live provider evidence.

### Configured-model quality benchmark (requires deliberate data-sharing consent)

The actual evaluation must run **locally with the configured provider and
credentials**. From the repository root, after the required QC/toolchain setup,
with explicit authorization to transmit selected source and synthetic draft
content to that provider:

```sh
uv run --locked python scripts/local_run.py --cwd apps/review_web mix run scripts/benchmark_discovery.exs -- --allow-external-source-data
```

Run the benchmark and browser exercise sequentially: each Mix runtime owns a
single writer, and startup recovery interrupts pending jobs in its configured
review directory. Concurrent runtimes sharing that directory are unsupported.

Without that flag the benchmark **refuses without sending**. It runs source-only
discovery and one typed challenge on each of three policy situations, writing a
real-provider result to ignored `tmp/review_studio/benchmarks/` only if the
invocation runs. Errors remain errors, not substituted controlled fixtures. Bounded original
provider responses (including rejected proposals) remain in the ignored report
for review. Challenge novelty excludes all supplied synthetic witnesses;
source-node citations resolve to exact files alongside excerpt citations.
The scorer counts distinct before/event/output challenges, excluding supplied
examples and changes limited to optional follow-on events. Challenge requests
show the same opaque, unlabeled synthetic examples so the model can seek a
new transition boundary without receiving computed labels or the rubric.
The model never receives `priv/benchmark/rubric.json` or the scorer.

Run the separate private offline scorer against the **actual generated path**:

```sh
python3 apps/review_web/scripts/score_discovery.py tmp/review_studio/benchmarks/discovery-<actual-digest>.json
python3 -m unittest discover -s apps/review_web/scripts -p 'test_score_discovery.py' -v
```

The scorer's six criteria and source-link checks yield only provisional lexical
previews unless the reviewer supplies a complete `--adjudication` JSON mapping
`R1`–`R6` to `label`, `rationale` and `source_evidence`. Only semantic review
of actual source-linked model statements can establish discovery quality;
benchmark success does not establish formal verification or a human conclusion.
A development target is 4/6 properly surfaced, zero unchallenged false proof
status claims, and one genuinely novel valid challenge. Preserve the actual
run log, latency, redundancies, prediction conflicts, challenge novelty and
human-adjudication record as **local C QC**, not as a fabricated first-half pass.

## Versioned change-review workspace

`/changes` is a separate, optional baseline-versus-proposal review route. The
existing `/workbench`, strict codec, source-derived rule evaluator, human review
CAS and formal acceptance workflow remain in place. This route reviews two
**content-addressed, operator-staged local source trees** with policy anchors
from the baseline source. Neither a branch label nor a source excerpt is an
execution or proof identity.

Prepare two trusted local Git worktrees (including an uncommitted proposal if
necessary), each based on the same pinned dependencies and compatible evaluator
and toolchain sources. From the repository root, stage each source tree using:

```sh
python3 apps/review_web/scripts/stage_part3_snapshot.py \
  --source /absolute/path/to/selected/local/worktree \
  --destination /absolute/path/to/hold_ledger/tmp/review_studio/snapshots
```

Open `/changes`, select the printed 64-character snapshot IDs, and create a
package. A package freezes both source manifests, derived differences and the
baseline specification-policy anchor. If the source changes, stage a **new**
identity; the old findings cannot silently move to the new tree. The app allows
only locally selected trusted snapshots. It refuses arbitrary uploaded code.

Use the structured event/state/entry/effect editor or the advanced JSON importer
(the same `TermCodec` validates both). Proposed totals are editable separately:
only an explicit **Recalculate used totals** action changes them automatically.
A starting ledger must be valid to pin/replay; a structurally representable
wrong proposed output is useful and allowed. Pin, isolated replay, a scoped
human finding, a model-question acceptance and conclusion are separate actions.
An expert view exposes results directly; the learning view records when the
reviewer chose to reveal results.

Replay starts two **separate local BEAM processes** through
`apps/review_web/scripts/part3_worker.py` and the pinned `scripts/local_run.py`.
Each selected source compiles into its own isolated build directory. The worker
uses the **existing** `Adversarial`, `ClaimProbe`, `Claims`, `Ledger`, `Spec` and
`TermCodec` modules rather than a new evaluator. The wrapper uses no shell,
network fetch or browser-controlled command arguments. Local dependencies must
be provisioned explicitly and offline beforehand. The supervision boundary
provides resource/time/cancellation handling but **is not a sandbox** for
malicious executable projects; only operator-trusted worktrees may be staged.
An unchanged source and an identified successful replay may be reused only
under their exact package/input/dependency/codec/evaluator identities.

The separate formal attempt uses the existing required-scope `run_laws.py` gate
and retains source-matching checked-report status. Pointwise examples and
syntactic differences do not constitute general contract implications or proof
acceptance. Source, proof inventory, translations and checked artifacts are
shown with their own provenance and missing state. The model adviser is
optional, uses the pre-existing Inference ASM/Codex configuration, and sends
nothing without an explicit new checkbox consent per request. No model owns a
human answer or conclusion.

Part 3 tests are in `test/hold_ledger_review/part3_test.exs`,
`test/browser/part3.spec.cjs` and `scripts/test_part3_tools.py`. On a local
machine provisioned through the root pinned wrapper, run the standard Phoenix
and root gates plus the focused tests; the ZIP handoff's Part 3 docset has the
full safety/verification matrix and local steps. Unrecognized prior record
schemas are refused rather than migrated or silently given new meanings.
