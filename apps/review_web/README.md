<p align="center">
  <img src="assets/review_web.svg" alt="Hold Ledger Claim Workbench" width="200" height="200">
</p>

# Hold Ledger Claim Workbench

[![GitHub](https://img.shields.io/badge/GitHub-hold__ledger-181717?logo=github)](https://github.com/nshkrdotcom/hold_ledger)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

Hold Ledger can prove that its code satisfies a law. But does the law capture the behavior people wanted? The Claim Workbench helps you answer that question by putting the source, requirements, concrete examples, and your review notes side by side.

This is a **separate Phoenix Mix application** in `apps/review_web`, running against your Hold Ledger checkout. You can test what a law rules out, record your judgment, or compare an existing version with a proposed change. The optional AI assistant suggests questions but cannot answer on your behalf. Claim probes run locally, without calls to a model, formal checker, or payment processor.

This app replaces the old Review Studio evaluator, tuple codec, fixed teaching cases, and receipt/AI explanation flow. The `/review` and receipt routes are gone; checks now use source-derived claims and one typed codec.

## Run it locally

Use the repository's pinned toolchain: **Elixir 1.20.4** and **Erlang/OTP 29.1.2**. Set up the root checkout as described in [Getting started](https://github.com/nshkrdotcom/hold_ledger/blob/main/guides/getting-started.md), then run the Phoenix app from the repository root:

```sh
cd apps/review_web
mix deps.get --check-locked
mix compile --warnings-as-errors
mix test --warnings-as-errors
mix precommit
mix phx.server
```

Open <http://localhost:4000/>. In development, Phoenix listens on loopback. This prototype is for local work, not hosted deployment. If the ledger is in another checkout, point `HOLD_LEDGER_REVIEW_ROOT` at that checkout before starting the app. Its ledger source must match the code the app was compiled against.

The main routes are:

| Route | Purpose |
| --- | --- |
| `/` or `/workbench` | Start or list human reviews |
| `/workbench/:id` | Reopen a saved review |
| `/changes` | Create a change review from staged local snapshots |
| `/changes/:id` | Reopen a saved change package |

Reviews are stored locally. You can inspect source-linked evidence and export a review without starting `HoldLedger.Server` or sending payments.

## Review a claim

At `/workbench`, choose one of eight bounded examples, P01–P08. Each pairs a starting ledger state and an event with a proposed output. Follow the source links and typed design graph, then edit that output to ask: *Would the law reject this behavior?*

Suppose the processor has authorized a hold and the ledger receives a void request. Releasing capacity right away may leave the counters consistent, but it lets another request use capacity before the void is confirmed. Change the proposed output to see which laws reject that behavior. The workbench makes no claim that the altered output happened in a real run.

The editor takes a **complete proposed output** with `after`, `result`, and `effects` fields. Events and effects use `type`, `key`, and `amount` (`null` for operations without an amount). The codec checks exact fields, types, statuses, integer values, and list sizes. A proposed after-state can be well formed yet fail `HoldLedger.Spec.valid?/1`; that is often exactly the behavior you want to challenge. An invalid JSON draft, by contrast, cannot be submitted as an answer.

When you submit a judgment, the server checks the **exact witness you submitted**, not an earlier valid draft. It saves the matching source identity, probe, and answer together and tracks human-answer revisions separately from document revisions. Pinning a witness, accepting a question, and recording a conclusion are separate actions.

You can use the workbench without an AI provider. Model suggestions are kept separate from your recorded choices, and computed contradictions appear before any model interpretation.

## How the claim check works

The workbench reads Elixir law declarations from your checkout. It does not maintain another set of rules. At startup, it compiles one evaluator. Each probe checks the proposed output against the source expressions and the independent `HoldLedger.Spec.expected_step` oracle.

The main pieces are:

- **`HoldLedgerReview.Claims.Source`** checks the registered DSL and native Lean catalog against the checkout inventory, extracts trusted law AST, and hashes the exact source and dependencies. `HoldLedgerReview.Config` separately checks the compiled `Ledger` and `Spec` source and build identity.
- **`HoldLedgerReview.Claims.Compiler`** audits supported `requires` and `expects` forms, resolves approved aliases, checks reducer-call signatures, and substitutes the hypothetical output for every matching call. The resulting module is compiled once at startup, never from a browser request or model response.
- **`HoldLedgerReview.Claims`** owns evaluator generation, diagnostics, and loaded-code identity. Each probe compares the current source and loaded modules with their recorded fingerprints.
- **`HoldLedgerReview.ClaimProbe`** binds event arguments and required `Spec.lookup` equalities to actual entries. It checks all eligible entries in the bounded state, even when the entry key differs from the event key. Results report binding provenance, domain completeness, and one of four bounded outcomes. Claims involving another reducer operation are marked `:not_probed`.
- **`HoldLedgerReview.TermCodec`** defines the native JSON representation; **`HoldLedgerReview.Canonical`** hashes validated JSON and uses the typed codec when converting native outputs. There is no generic tuple fallback.

Only required positive `Spec.lookup` equalities justify enumerating a complete bounded set of entries. A lookup in an optional `or` branch cannot do that. The probe reports the gap rather than calling a partial check complete.

If a law, predicate, compiler dependency, or loaded module changes, new probes return `:source_or_compiled_code_drift`. Rebuild and restart before probing again. Reviews tied to the old source or report generation become read-only; start a new review for the changed source. The running evaluator is never hot-purged.

### What the evidence means

A pointwise check tells you whether one candidate output satisfies a source claim for one bounded input. It does not prove that the law holds generally. Native Lean obligations are listed in the catalog but are never compiled into invented Elixir contracts. `ProofEvidence` reads existing checked reports; it does not run a formal checker.

Formal status requires an independently checked report for the same source. That report establishes the stated theorem, not the policy behind it. The original `test/laws` definitions and the independent `HoldLedger.Spec` remain the reference points for this workbench.

For a manual exercise that questions the contract without starting the web app, read [Interactive review](https://github.com/nshkrdotcom/hold_ledger/blob/main/guides/interactive_review.md). For the boundaries of the root proof pipeline, see [Verification](https://github.com/nshkrdotcom/hold_ledger/blob/main/guides/verification.md).

## Ask a model for another question (optional)

AI requests use the configured [Inference](https://hex.pm/packages/inference) client and ASM/Codex adapter. The evaluator stays the same, and only a person can submit a human judgment. If the provider does not declare JSON-Schema support, the request fails closed; a provider error never blocks a manual review.

You must opt in **separately for every request**. Discovery sends bounded source-linked excerpts and unlabeled synthetic probes. It excludes human answers, hidden scoring criteria, fixture names, expected matrices, and mutant labels. A challenge can include the current draft. An answer-aware follow-up can include the latest recorded choice, the reason for it, computed evidence, and the previous question—but only when you opt in to that particular follow-up.

`HoldLedgerReview.AIPacket` builds the source-bound packet, while `AIProtocol` checks the reply against the canonical schemas, allowable source IDs, pointwise predictions, and typed witnesses. The provider sees a strict wire schema with disjoint `anyOf` event branches. Local checks enforce array uniqueness, permitted card targets, and the canonical response contract. Packets have a **64 KiB source budget**, prioritizing policy, full reducer/oracle definitions, and laws over large proof files. The app checks source, prompt, and report freshness before dispatch. Excerpts from nonadjacent source regions are marked, and source/digest drift stops dispatch.

`AIJobs` permits one pending request per review through the single-writer `ReviewStore`. It runs the provider call under a `Task.Supervisor`, outside LiveView. It validates the reply again before saving it. A changed human revision or stale source discards the result. A restart interrupts pending work without resending it; `completion_digest` handles exact retries. Suggested cards remain `ai_proposed` until you accept them. An offered challenge opens as an **unsaved draft**. Your answers and final conclusion remain yours.

### Evaluate the configured provider

Controlled ExUnit and browser tests cover the protocol and consent controls. They do not measure a live provider. To run the local benchmark against the configured provider, authorize transmitting selected source and synthetic drafts, then run this from the repository root:

```sh
uv run --locked python scripts/local_run.py --cwd apps/review_web mix run scripts/benchmark_discovery.exs -- --allow-external-source-data
```

Without `--allow-external-source-data`, the benchmark refuses to send. With consent, it runs source-only discovery and typed challenges for three policy situations. It saves real provider output, including rejected proposals, in ignored `tmp/review_studio/benchmarks/`. Errors are not replaced with fixtures. The model never sees the private rubric or scorer. The scorer counts distinct state/event/output challenges and excludes supplied examples and changes limited to optional follow-on events.

Score the file actually created by that run:

```sh
python3 apps/review_web/scripts/score_discovery.py tmp/review_studio/benchmarks/discovery-<actual-digest>.json
python3 -m unittest discover -s apps/review_web/scripts -p 'test_score_discovery.py' -v
```

The private scorer can preview lexical matches. To judge actual discovery quality, a reviewer must supply an `--adjudication` JSON mapping `R1`–`R6` to `label`, `rationale`, and `source_evidence`. The local quality target is **4/6 correctly surfaced**, no unchallenged false proof-status claims, and at least one genuinely new valid challenge. Keep the real run log, latency, repetitions, disagreements, and adjudication record; do not treat a benchmark score as proof acceptance or a human conclusion.

Run the benchmark and browser checks **sequentially** if they share a review directory. Each Mix runtime owns a single writer, and startup recovery interrupts pending jobs. Concurrent runtimes against the same review directory are unsupported.

## Compare a baseline with a proposal

At `/changes`, you can compare how the claims behave before and after a code change. The workspace reads two **local source trees that you stage yourself**. Each snapshot has a content-based identity, so a branch name alone will not do. A review package keeps the baseline policy anchors alongside the source differences.

Prepare two trusted local Git worktrees, with the same pinned dependencies and compatible toolchain/evaluator sources. The proposal may contain uncommitted changes. Stage each tree separately from the repository root:

```sh
python3 apps/review_web/scripts/stage_part3_snapshot.py \
  --source /absolute/path/to/selected/local/worktree \
  --destination /absolute/path/to/hold_ledger/tmp/review_studio/snapshots
```

Open `/changes`, enter the two printed 64-character snapshot IDs, and create a package. It freezes the source manifests, differences, and baseline specification-policy anchor. If either tree changes, stage it again and create a new identity. The app accepts locally selected trusted snapshots, not arbitrary uploaded projects.

### Explore the change

Use the structured editor for states, events, entries, and effects, or import the same data as JSON; both paths use `TermCodec`. Proposed accounting totals remain independently editable. They change automatically only when you select **Recalculate used totals**. The starting ledger must be valid before a witness can be pinned or replayed, but the proposed output may deliberately be wrong.

You can pin a witness, replay the two versions, record a scoped human finding, accept a model question, or write a conclusion. Those are separate actions. The learning view records when you choose to reveal results; the expert view shows them directly.

Replay starts **two local BEAM processes**, one per source tree, using `apps/review_web/scripts/part3_worker.py` and the pinned `scripts/local_run.py`. Each source tree compiles in its own isolated build directory. Both processes use the existing `Adversarial`, `ClaimProbe`, `Claims`, `Ledger`, `Spec`, and `TermCodec` modules; there is no change-review-only evaluator. The runner avoids shell commands, network fetches, and browser-supplied command arguments. Provision local dependencies offline before replay.

**Isolation is not a security sandbox.** Time limits, cancellation, and separate build directories do not make a malicious project safe to execute. Stage only worktrees you trust. A successful replay can be reused only when its package, input, dependencies, codec, and evaluator identities are unchanged.

For changed supported laws, helpers, and inventories, change-directed search can propose up to **48 distinct synthetic challenges**. It varies amounts, statuses, keys, effects, frame fields, accounting totals, and two-event consequences. Selecting a suggestion changes the draft only. **Run bounded isolated search** actually replays the selected pair; cancellation or failure stops the run. Unsupported domains, native-only bindings, and general solver results remain unresolved. A bounded search cannot prove the two versions equivalent or safe.

### Inspect proof evidence

The separate formal attempt uses the existing `run_laws.py` required-scope gate. A pointwise witness, source diff, or accepted snapshot does not establish a general theorem or formal acceptance. The proof pane keeps the source, proof inventory, translations, checked artifacts, and missing evidence distinct.

You can also import an offline or CI-produced artifact index from `tmp/verification/part3-*/`. A closed version-1 index records its snapshot, source-manifest digest, required scope, producer, optional report digest, and each artifact's path, hash, size, kind, and law slug. Use the explicit intake form or `Part3Store.ingest_artifacts/2` after copying the exact files into the selected snapshot. The app retains new indexes, recognizes identical repeats, and flags missing or changed bytes. It lets you inspect translations, dependency records, exports, and checker diagnostics when they exist.

Artifact intake is not a fresh proof run. The original `ProofEvidence` machinery alone determines formal acceptance from matching checked reports. Revalidating an old report, importing an artifact, and running a checker are different operations.

Change review can also request an answer-aware model follow-up based on one recorded human finding and an accepted model question. It sends only their attributed context and linked evidence after new consent. Source-only discovery still excludes human answers. Pending context becomes stale when a relevant answer or source changes; model suggestions cannot alter findings or confer policy or proof approval. Existing `/workbench` review and human-answer compare-and-swap (CAS) rules continue to apply.

For fully offline snapshots, provision the locked dependency sources into `tmp/part3_build/deps`, set the corresponding `MIX_BUILD_PATH`, `MIX_DEPS_PATH`, and `PYTHONPYCACHEPREFIX=<snapshot>/tmp/part3_build/pycache`, and run the pinned wrapper with `uv run --offline --locked`. Keep Python caches out of source directories: unexpected source files fail manifest checks. Unknown older review formats are refused, not silently migrated.

## Check your changes

The Phoenix tests cover the app; the root tests cover the law declarations it reads. Run both when changing the source evaluator or the laws. In particular, the root `test/claim_source_parity_test.exs` compares AST extraction against `HoldLedger.ProofCase.law_declarations/1` in the root's Lynx-dependent test environment. Phoenix does not import that test-only module at runtime.

The tests are grouped by what they exercise:

- `test/hold_ledger_review/` — graph provenance, candidate outputs, codecs, record revisions, AI protocol/jobs, and change-review behavior.
- `test/hold_ledger_review_web/` — LiveView, source inspection, export routes, and opt-in behavior.
- `test/browser/` — browser interactions, submission races, and consent regressions.
- `test/hold_ledger_review/part3_test.exs`, `test/browser/part3.spec.cjs`, and `scripts/test_part3_tools.py` — change-review coverage.

To run the browser suite, start Phoenix in one terminal. In another:

```sh
cd apps/review_web/test/browser
npm ci
npx playwright install chromium
npm test
```

The Playwright tests write synthetic review records under ignored `tmp/review_studio/reviews/`; they do not contact a provider, run the formal checker, or execute mutants. The controlled AI tests use `test/support/controlled_adapter.ex`, not live provider output.

For offline M1–M10 mutation observations, run these commands at the repository root:

```sh
uv run --locked python scripts/harvest_mutants.py --execute
uv run --locked python scripts/local_run.py --cwd apps/review_web mix run scripts/assess_mutant_harvest.exs -- ../../tmp/verification/mutant-harvest.json
```

The harvester compiles in scratch space, then records source SHA-256 hashes, loaded BEAM identities, complete outputs, and assertion results. The assessor uses the original source evaluator and records what was tested alongside what remains outside the catalog. Operations the native codec cannot represent stay marked unprobeable—not as proof failures or unexpected successes. Static manifests describe expectations, not observed runs. Generated logs and reports remain ignored.

The core and web code live in `lib/hold_ledger_review/` and `lib/hold_ledger_review_web/`. `design_graph.ex`, `dossier.ex`, `adversarial.ex`, `review_store.ex`, and `review_report.ex` support human review. `live/workbench_live.ex` provides the review UI; `live/part3_live.ex` provides the change workspace. The bounded seed cases live in `priv/scenarios/`.

Review records and their schema are maintained with the separate milestone contracts (including `contracts/review.schema.json`); they are not promised a backward-compatible migration path. The separate Part 3 docset contains its verification matrix and local quality-control steps. None of the workbench's results change the root project's proof-acceptance rules or transfer policy authority away from the reviewer.
