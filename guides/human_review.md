# Human review: what to check when an agent changes a Lynx project

The kernel checks proofs. You check what they are about. The agent can write code and proofs; a human approves the claims and assumptions.

Use this guide for each proposed change. If you are new to Lynx, read the [crash-course glossary](formal_verification_crash_course.md#terms-you-will-need) first. The [assurance audit](audit.md) covers the deeper system review. Here, start with the diff.

**Verified against source baseline:** `715de80` before the review-policy changes introduced with this revision. Paths and commands were checked during this edit; this is not an independent assurance sign-off.

The main failure mode is pressure to get checks green: weakening a claim can be easier than repairing the implementation or proof. The agent's report helps you navigate; the diff decides the tier.

Here, an **obligation** is a required claim; `obligations.json` lists what must be checked, while the **catalog**, `laws.json`, registers its implementation. `PO-*` labels identify those claims.

## Divide the Work

| Human owns | Agent handles | Shared work |
|---|---|---|
| Policy, independently chosen traces, law and Spec approval, required-obligation sign-off | Implementation, helper lemmas, tactics, proof repair and evidence collection | Tests, mutation experiments and failure diagnosis |

The agent may draft a statement or Spec change; a human must approve its meaning. Settle the claim before commissioning its proof.

## Classify the Diff and Route Review

| Tier | Diff | Action |
|---|---|---|
| 1 | Claims, definitions, theorem signatures, Spec, coverage, foundations or checking machinery | Human approval of meaning, scope and evidence policy |
| 2 | Ledger and runtime implementation | Review behavior and runtime boundaries; rerun committed policy traces for every Ledger change |
| 3 | Only confirmed proof-body changes | Require fresh full acceptance; usually skip line-by-line tactics |
| Documentation | Changed explanations or promises | Compare with the contracts; policy expectations can change here too |

The shared path list is [`verification/review-policy.json`](https://github.com/nshkrdotcom/hold_ledger/blob/main/verification/review-policy.json). It includes all verification files (including `baseline.json`), scripts (`obligations.py`, `verify_laws.exs`, `verify_pins.py`, `toolchains.json`), tooling tests, Spec, tests/proofs, mutants, adapters, CI, agent instructions and exact toolchain/dependency pins. CI reads its formal-selection lists. `scripts/review_policy.py` generates CODEOWNERS from its ownership list; `--check` rejects drift. Ownership is deliberately broader than semantic Tier 1, so proof-only changes still request review.

Until a statement-diff tool exists, use this conservative procedure:

1. Inspect the complete base-to-head diff, including added/deleted files, renames and surrounding declarations. Do not trust a “proof-only” label.
2. A changed Lean line touching `def`, `abbrev`, `instance`, `structure`, `inductive`, `class`, `notation`, `macro`, `syntax`, `elab`, `set_option`, `open`, `import`, `attribute`, `axiom`, `opaque` or `unsafe` makes the change Tier 1. This deliberately overclassifies comments or local definitions when uncertain.
3. Compare every changed theorem/lemma signature in full, including multiline binders, hypotheses, result types and declaration attributes before the proof. A signature change is Tier 1.
4. Only changes confined to bodies after those checks qualify for Tier 3. A body may start with `by` or be a proof expression; do not classify it by indentation alone. Unclear boundaries or changed macros/elaborators (code that interprets proof syntax) require Tier 1 review.

CODEOWNERS requests the configured owner's review; hosting must additionally require code-owner approval, dismiss stale approvals, and require approval of the latest revision. Verify the named owner has repository write access. CI does not configure those settings or authenticate a filled-in approval record. **To build:** automated statement-level diff classification. Source hashes identify changes; they do not approve them.

Use this checklist for Tier 1 review:

1. **Did the claim weaken?** Look for a stronger hypothesis, narrower domain, weaker conclusion or new environment assumption. Expand predicates rather than trusting names such as `valid` or `safe`.
2. **Can the hypotheses hold?** Run a concrete witness—an input satisfying the hypotheses. Check that excluded boundary cases are intentional; one witness does not establish adequate coverage.
3. **Does it match policy?** Compare it with expected traces you chose before reading the agent's oracle or proof.
4. **Are obligations still required?** Compare against the base revision and requirements, not merely two inventories edited together. Nothing should disappear through selection, status, skipping or timeout handling.
5. **Is Spec independent?** The oracle (the independent reference specification) and implementation never call each other. If both changed, review each against the independently agreed policy; agreement alone is insufficient.
6. **Are the foundations intact?** Inspect changes to axioms, escape checks, translated definitions, adapters, toolchain and gate behavior.

## Write the Claim Before the Proof

Write a policy sentence, then three to five traces with expected outcomes. Only then read or commission the formal statement and its witness. Choose the expected outcomes without consulting `Spec.expected_step/2`; those expectations need to be able to challenge the oracle.

For a new policy, choose a safety case, a progress case, exact-fit and last-slot boundaries, then duplicate, failure and restart cases. Commit the traces as ordinary tests with literal expected outcomes so future changes must preserve the human's decisions.

For example: **an issued authorization consumes capacity until trustworthy terminal evidence releases it.** Every row below is independent. State tuples are `{amount_limit, slot_limit, used_amount, used_slots, entries}`. Events run left to right; keys are integers.

| Initial state | Event sequence | Expected outcome |
|---|---|---|
| `{100, 1, 0, 0, []}` | `{:request, 1, 100}` | Admit: exact amount and last slot fit. |
| `{100, 2, 100, 1, [{1, 100, :authorized}]}` | `{:void, 1}`, then `{:request, 2, 100}` without confirmation | First hold stays `:voiding`; new request is `:insufficient_amount`. |
| `{100, 2, 100, 1, [{1, 100, :voiding}]}` | `{:void_confirmed, 1}`, `{:request, 2, 100}` | Release once; admit key 2. |
| `{100, 2, 0, 0, [{1, 100, :voided}]}` | `{:void_confirmed, 1}`, `{:request, 1, 100}` | Confirmation is stale; request is duplicate; counters stay zero. |
| `{100, 2, 100, 1, [{1, 100, :sent}]}` | `{:timeout, 1}`, `{:request, 2, 100}` | First hold becomes `:unknown`; refuse key 2. |
| `{100, 2, 100, 1, [{1, 100, :sent}]}` | `:restart`, `{:request, 2, 100}` | First hold becomes `:unknown`; refuse key 2. |

These examples are committed in `test/human_policy_traces_test.exs`; rerun them with `uv run --locked python scripts/local_run.py mix test test/human_policy_traces_test.exs --exclude laws`.

A refuse-everything implementation preserves capacity limits. The first and third traces require positive admission as well as safety. Hold Ledger's PO-A2 captures obligatory admission; preservation alone does not.

## What the Agent Must Report

Use `.github/pull_request_template.md` for the following report and the human approval record (claim delta, reviewed revision, evidence scope and reviewer). The agent leaves approval to the human. Its report does not establish the tier.

The report contains:

- `Claim delta: none` or the exact change to statements, domains and assumptions.
- Tier 1 files touched, with the reason for each change.
- Commands run and results, separating ordinary tests, formal acceptance and external assumptions.
- Unresolved failures, missing evidence or resource limits.

Require human approval for proposed hypothesis additions, domain restrictions, Spec/model changes, inventory changes, axiom or gate changes, and test skips. The original task does not authorize a weaker guarantee. An already approved policy change can proceed within its stated scope.

Resource increases also need explanation and fresh results. A timeout bump is not inherently a changed mathematical claim, but it can change operational acceptance; it must never turn a timeout into success.

When a proof fails, run the witness and property for the same claim. Replay any counterexample and confirm that the precondition holds while the conclusion fails. The human decides whether policy calls for fixing the code or correcting a proposed claim. With no counterexample, the claim remains unresolved: inspect generator coverage and the proof state. Do not label it true merely because bounded testing passed.

## Common Ways a Green Result Can Mislead

| Symptom | Where to look | How to detect it |
|---|---|---|
| Impossible precondition | `requires`, called predicates | Construct a witness; look for contradictory bounds. |
| Conclusion omits the promised effect or admission | `expects` | Replay a trace that requires progress; “state unchanged” is correct only for specified cases. |
| Hard inputs disappear | New guards or typed encodings | Compare domains with the base revision; PO-B5 (a catalog label for a terminal-preservation obligation) permits lookup queries where `1 == 1.0`. |
| Desired result becomes a caller assumption | Hypotheses of the top-level theorem and its helper lemmas | Follow each assumption to independent evidence; do not assume the conclusion. |
| `valid?` becomes easier to satisfy | Spec or Lean definitions | Check whether it still requires exact totals, uniqueness and intended statuses. |
| Spec changes to match faulty code | Implementation and oracle diffs | Compare both with the human's prior traces. |
| A law and its inventory entry vanish together | Catalog and required inventory | Compare required coverage with the previous revision and policy. |
| Numeric identity is blurred | `==`, `===`, codecs, queried domains | Exercise `1` and `1.0`; decide where exact identity is required. |
| A witness or property becomes weaker or skipped | Tests, tags, generators, filters | Replay the original regression and inspect effective selection. |
| “Supported” is presented as proof | Catalog status and report | Require a matching successful full run. |
| Old exports or cache results are reused | Source/export identities and acceptance mode | Require fresh acceptance on the reviewed source. |
| A direct proof attempt passes but acceptance is incomplete | Runner report and CI jobs | Check full scope, exports, all checker results and allowed axioms. |

## Use Mutations to Challenge the Claims

A mutant is a disposable code copy with a deliberate change. Choose policy-relevant faults yourself; the agent can propose and run them. A surviving known violation suggests missing coverage only after confirming that the mutation ran and all intended checks completed. Some mutations preserve behavior; tool failures and incomplete runs are inconclusive.

In `mutants/02_timeout_release/mutant.patch`, a sent hold of `300` becomes unknown while its counters fall to zero. The required result retains `300` and one slot. The concrete M2 test and PO-B1/timeout address that policy.

Choose the planted violation, confirm the original passes, then have the agent run the isolated mutation experiment. If a known violation survives completed checks, replay it and strengthen or add the missing law or test against the agreed policy. Do not edit the mutant or Spec to make the experiment pass. Keep the reproducer as a regression.

Run the ordinary baseline with `uv run --locked python scripts/local_run.py mix test test/mutations/preflight_test.exs --exclude laws`. The [Testing guide](testing.md#deliberate-mutations) gives the isolated experiment and costs.

## Read “Green” Precisely

| Result | What it establishes |
|---|---|
| Development proof attempt | The selected development check passed; full exported-checker acceptance may not have run. |
| Catalog `supported` | A proof implementation is registered; this is not execution evidence. |
| Full acceptance | The selected obligations passed fresh proofs, exports, six checker configurations and axiom checks for the recorded sources. A subset is not release acceptance. |
| CI green | The jobs required for that change succeeded; documentation-only changes may have no new formal run. |

Match the report to the reviewed revision. In hosting settings, require the stable `formal-gate` check before merge, alongside ordinary checks and the relevant human approval. Workflow code does not configure branch protection or prove that the human reviewed Tier 1 material.

For Tier 2 runtime changes, follow the [server and journal audit](audit.md#server-and-journal-follow-one-confirmation-through-failure): inspect caller authentication; correlation of late worker results with the current attempt; sync-before-transition/effects ordering; crash replay and incomplete-tail handling; and remote retry identity. Require runtime or fault-injection regressions for changed paths. Re-run the committed policy traces whenever Ledger changes.

## Practice on Six Proposed Changes

These are synthetic PR summaries, not existing branches or executable fixtures. Review them without the answers first. For each, identify the changed guarantee, give a distinguishing trace or witness, and state what would be needed to approve it.

**A — Faster retention proof.** An agent adds `status != :voiding` to a capacity-retention law and reports full acceptance.

**B — Faster accounting.** The timeout branch releases counters early. Spec drops the check that counters equal sums over holding entries. The PR reports that Ledger and Spec agree.

**C — Cleaner key types.** A terminal-preservation law adds `is_integer(key)` to its hypotheses. The agent calls it a harmless alignment with the public API and proves the restricted statement.

**D — Remove obsolete verification.** An agent removes a terminal-preservation group from both `obligations.json` and `laws.json`, deletes its proof, and reports that inventory comparison and all remaining checks pass.

**E — Proof-only cleanup.** The PR description says `Claim delta: none`. A Lean diff changes `def valid` or an `instance` used by a theorem, while all theorem signatures and proof results remain unchanged.

**F — Simpler postcondition.** An admission law previously required the expected admitted state and result. It now requires only `Spec.valid?(result_state)`, and its proof passes.

<details>
<summary>Answer key — open after reviewing the proposed changes</summary>

A excludes pending voids, the central retention case. Use the delayed-confirmation trace to expose the lost guarantee. B weakens validity to accommodate premature release; restore the accounting contract and repair behavior unless a human approves different policy. C removes noninteger lookup queries: stored key `1` is found by `1.0` under `==`; public event guards do not define this theorem's domain. D removes required coverage from both inventories; compare with the base revision and policy. E is Tier 1 under the declaration filter: unchanged theorem signatures do not preserve their meaning when a referenced definition or instance changes. F drops positive admission; a refuse-everything implementation could satisfy the new conclusion. Restore the admission claim.

</details>

A reader trial should ask a senior SWE new to FV to identify all six flaws, give distinguishing cases and justify review decisions before opening the answers. **Not yet performed:** the reader trial. Executable seeded PR fixtures remain **to build**.

> **Limits.** A failed tactic or timeout is not a counterexample; mutation attribution needs a checked baseline and reproduced violation. A survivor is informative only after confirming the fault and completed checks. Kernel checking validates proofs against their definitions and assumptions. Compiler/translator correspondence, OS and storage behavior, and real processor guarantees remain part of the trust decision. This workflow does not certify those dependencies or establish that hosting rules are configured. The [assurance audit](audit.md) examines those boundaries; [Verification](verification.md) defines acceptance evidence.
