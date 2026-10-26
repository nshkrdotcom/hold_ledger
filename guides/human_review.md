# Human review: what to check when an agent changes a Lynx project

The kernel checks proofs. You check what they are about. The agent can write code and proofs; a human approves the claims and assumptions.

Use this guide for each proposed change after reading the [crash course](formal_verification_crash_course.md). Use the [assurance audit](audit.md) for an initial or periodic review of Hold Ledger's full argument. Start with the diff, rather than rereading the proof library.

## Divide the Work

| Human owns | Agent handles | Shared work |
|---|---|---|
| Policy, independently chosen traces, law and Spec approval, required-obligation sign-off | Implementation, helper lemmas, tactics, proof repair and evidence collection | Tests, mutation experiments and failure diagnosis |

The agent may draft a statement or Spec change. It cannot approve its own proposal. Review the claim before asking it to spend time proving it.

## Classify the Diff by Meaning

| Tier | Changes | Review required |
|---|---|---|
| 1: claims and checking boundary | `requires:` / `expects:`, theorem statements, Spec predicates, Lean definitions and model constructors, instances or notation that affect meaning | Human sign-off on the meaning and assumptions |
| 1: coverage and evidence | Required inventory and catalog, axiom allowlist, forbidden-escape scan, runner, CI gate, adapter, toolchain pins, mutation patches and witnesses | Human sign-off on what is checked and accepted |
| 2: implementation | Ledger and runtime code | Normal code review, appropriate tests and required formal checks |
| 3: proof bodies | Tactics and helper-proof bodies with unchanged statements and dependencies | Fresh acceptance; usually no line-by-line tactic review |

In Hold Ledger, Tier 1 includes `spec.ex`, `test/laws/`, Lean `def` / `inductive` / `structure` / `instance` declarations, `verification/obligations.json`, `verification/laws.json`, `scripts/run_laws.py`, `scripts/formal_gate.py`, `test/support/proof_case.ex`, `.github/`, pins and `mutants/`. Inspect Lean imports, options, macros and elaborators too: a `.lean` extension does not make a change proof-only.

A theorem's **body** can usually be skipped after checking its statement and dependencies. A changed theorem statement needs review even when its proof passes. Definitions give the statement meaning; kernel checking does not decide whether that meaning matches policy.

## Triage Each Proposed Change

| Diff touches | Action |
|---|---|
| Tier 1 material | Review the questions below and record human approval of the claim or checking-policy change. |
| Tier 2 code | Review behavior and runtime boundaries; require relevant executable tests and formal evidence. |
| Only Tier 3 bodies | Confirm statements, definitions, imports and checking policy are unchanged; accept the proof work when fresh full acceptance matches the revised source. |
| Documentation | Check that its promises still match the contracts; documentation can change policy expectations too. |

These are review rules, not an automatic approval service. The current CI gate detects proof-relevant paths and requires formal execution; it does not identify semantic tiers or obtain human sign-off. **To build:** a tool that prints statement-level changes across laws, Spec, Lean definitions and inventories. Until then, inspect those diffs directly. Source hashes identify changes; they do not approve them.

For Tier 1 changes, answer six questions:

1. **Did the claim weaken?** Look for a stronger hypothesis, narrower domain, weaker conclusion or new environment assumption. Expand predicates rather than trusting names such as `valid` or `safe`.
2. **Can the hypotheses hold?** Run a concrete witness. Check that excluded boundary cases are intentional; one witness does not establish adequate coverage.
3. **Does it match policy?** Compare it with expected traces you chose before reading the agent's oracle or proof.
4. **Are obligations still required?** Compare against the base revision and requirements, not merely two inventories edited together. Nothing should disappear through selection, status, skipping or timeout handling.
5. **Is Spec independent?** Neither implementation calls the other. If both changed, review each against the independently agreed policy; agreement alone is insufficient.
6. **Are the foundations intact?** Inspect changes to axioms, escape checks, translated definitions, adapters, toolchain and gate behavior.

## Write the Claim Before the Proof

Write a policy sentence, then three to five traces with expected outcomes. Only then read or commission the formal statement. Give it a witness that exercises the precondition. Keep the traces independent of `Spec.expected_step/2`; copying the oracle's answer cannot challenge its policy.

For example: **an issued authorization consumes capacity until trustworthy terminal evidence releases it.** Choose limit `100`, two slots, and distinct keys:

| Trace | Expected outcome |
|---|---|
| Request `100` on an empty ledger | Admit. |
| Dispatch, receive approval, request void, delay confirmation, then request another `100` | Keep the first hold `:voiding`; refuse the new request for insufficient amount. |
| Confirm the void, then request the new `100` | Release once; admit the new request. |
| Repeat confirmation after release | Stale result; no additional release. |
| Dispatch then time out, then request another `100` | Keep the first amount held in `:unknown`; refuse the new request. |

A refuse-everything implementation preserves capacity limits. The first and third traces require positive admission as well as safety. Hold Ledger's PO-A2 captures obligatory admission; preservation alone does not.

## What the Agent Must Report

Ask for a short PR description containing:

- `Claim delta: none` or the exact change to statements, domains and assumptions.
- Tier 1 files touched, with the reason for each change.
- Commands run and results, separating ordinary tests, formal acceptance and external assumptions.
- Unresolved failures, missing evidence or resource limits.

The agent should flag proposed hypothesis additions, domain restrictions, Spec/model changes, inventory changes, axiom or gate changes, and test skips before treating them as an accepted repair. Approval of the original task does not imply approval of a weaker guarantee. An already approved policy change can proceed within its stated scope.

Resource increases also need explanation and fresh results. A timeout bump is not inherently a changed mathematical claim, but it can change operational acceptance; it must never turn a timeout into success.

When a proof fails, run the witness and property for the same claim. Replay any counterexample and confirm that the precondition holds while the conclusion fails. The human decides whether policy calls for fixing the code or correcting a proposed claim. With no counterexample, the claim remains unresolved: inspect generator coverage and the proof state. Do not label it true merely because bounded testing passed.

## Common Ways a Green Result Can Mislead

| Symptom | Where to look | How to detect it |
|---|---|---|
| Impossible precondition | `requires`, called predicates | Construct a witness; look for contradictory bounds. |
| Conclusion omits the promised effect or admission | `expects` | Replay a trace that requires progress; “state unchanged” is correct only for specified cases. |
| Hard inputs disappear | New guards or typed encodings | Compare domains with the base revision; PO-B5 deliberately permits loose numeric lookup queries. |
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

Hold Ledger's `mutants/02_timeout_release/mutant.patch` plants a specific fault:

1. Begin with `{1000, 3, 300, 1, [{11, 300, :sent}]}` and apply `{:timeout, 11}`.
2. The agreed result retains `300` and one slot, changing only `:sent` to `:unknown`.
3. The patch instead reduces both counters to zero while leaving the unknown entry. `Spec.valid?/1` must reject that state.
4. The concrete M2 test detects the contradiction. The targeted group is PO-B1/timeout. Attribute a formal failure only after checking the original baseline and reproducing the violation; a failed tactic alone is insufficient.

Run the ordinary baseline with `uv run --locked python scripts/local_run.py mix test test/mutations/preflight_test.exs --exclude laws`. The [Testing guide](testing.md#deliberate-mutations) gives the isolated native experiment and its costs. Keep mutation work out of the live reducer and never edit Spec to accommodate a planted fault.

## Read “Green” Precisely

| Result | What it establishes |
|---|---|
| Development proof attempt | The selected development check passed; full exported-checker acceptance may not have run. |
| Catalog `supported` | A proof implementation is registered; this is not execution evidence. |
| Full acceptance | The selected obligations passed fresh proofs, exports, six checker configurations and axiom checks for the recorded sources. A subset is not release acceptance. |
| CI green | The jobs required for that change succeeded; documentation-only changes may have no new formal run. |

Inspect the actual report and reviewed revision. In hosting settings, require the stable `formal-gate` check before merge, alongside ordinary checks and the relevant human approval. Workflow code does not configure branch protection or prove that the human reviewed Tier 1 material.

Also ask whether the change relies on runtime behavior absent from the pure model. Authentication, worker correlation, journal sync and recovery paths need runtime or fault-injection evidence. A pure replay equality is not a proof that a disk write survived a crash.

## Practice on Four Proposed Changes

These are synthetic PR summaries, not existing branches or executable fixtures. Review them without the answers first. For each, identify the changed guarantee, give a distinguishing trace or witness, and state what would be needed to approve it.

**A — Easier admission proof.** An agent adds `amount > 0 and amount <= 0` to an admission law's precondition and reports full acceptance.

**B — Faster accounting.** The timeout branch releases counters early. Spec drops the check that counters equal sums over holding entries. The PR reports that Ledger and Spec agree.

**C — Cleaner key types.** A terminal-preservation law adds `is_integer(key)` to its hypotheses. The agent calls it a harmless alignment with the public API and proves the restricted statement.

**D — Remove obsolete verification.** An agent removes a terminal-preservation group from both `obligations.json` and `laws.json`, deletes its proof, and reports that inventory comparison and all remaining checks pass.

**Answer key.** A is vacuous: no positive integer is at most zero. Require a satisfiable domain that retains the intended cases. B changes both behavior and the definition of validity; a sent `300` becoming unknown with zero counters violates the original policy. Restore the accounting requirement and repair the implementation unless the human explicitly chooses a different policy. C removes noninteger queries from the theorem even though public event guards do not define the lookup-law domain: with stored key `1`, lookup by `1.0` matches under loose equality. Preserve that case or obtain explicit approval to change the guarantee. D can evade a comparison of two revised inventories; restore the required claim or obtain policy approval for its removal. Green results cannot supply that approval.

To validate this guide with readers, give a senior SWE unfamiliar with FV the crash course and these proposed changes. Ask them to identify all four flaws and justify their decisions before showing the answers. **Not yet performed:** that reader trial. Runnable seeded PR fixtures and automated statement-diff classification remain **to build**.

## Review Card

Classify the diff: claims/checking boundary → human sign-off; implementation → code review and relevant gates; unchanged-statement proof bodies → fresh full acceptance; documentation → verify promises.

Before sign-off: claim unchanged or explicitly approved; meaningful witness; independently chosen policy traces; required coverage retained; Spec independent; foundations and gates intact. Record the approved claim delta, source revision, evidence scope and unresolved assumptions. If any item is unresolved, state it rather than treating proof success as approval.

> **Limits.** Kernel checking validates proofs against their definitions and assumptions. Compiler/translator correspondence, OS and storage behavior, and real processor guarantees remain part of the trust decision. This workflow does not certify those dependencies or establish that hosting rules are configured. The [assurance audit](audit.md) examines those boundaries; [Verification](verification.md) defines acceptance evidence.
