# Human review: what to check when an agent changes a Lynx project

The kernel checks proofs. You check what they are about: read the statement and its definitions before the tactics. The agent can write code and proofs; a human approves the claims and assumptions.

Use this guide for each proposed change. If you are new to Lynx, read the [crash-course glossary](formal_verification_crash_course.md#terms-you-will-need) first. The [assurance audit](audit.md) covers the deeper system review. Here, start with the diff.

The main failure mode is pressure to get checks green: weakening a claim can be easier than repairing the implementation or proof. The agent's report helps you navigate; the diff decides the tier.

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
| Documentation | Explanations of existing behavior | Check against the contracts; policy changes such as edits to `guides/specification.md` are Tier 1 |

In Hold Ledger, apply Tier 1 review to these meanings and boundaries:

| Files | What to inspect |
|---|---|
| `guides/specification.md`, `AGENTS.md` | Intended policy and the instructions that constrain agent changes |
| `lib/hold_ledger/spec.ex`, `test/laws/*.exs` | Reference behavior, assumptions and conclusions; classify embedded proof changes separately below |
| `test/support/lean/*.lean`, `test/support/proof_case.ex` | Model definitions, theorem signatures, generated predicates and translation wiring |
| `verification/obligations.json`, `verification/laws.json`, `verification/baseline.json` | Required claims, registered groups and historical evidence |
| `scripts/run_laws.py`, `scripts/verify_laws.exs`, `scripts/obligations.py`, `scripts/formal_gate.py`, `.github/workflows/`, `tooling_tests/` | Selection, exports, rejection of incomplete runs and checks on that machinery |
| `scripts/verify_pins.py`, `scripts/toolchains.json`, `lean-toolchain`, `.tool-versions`, `.python-version`, `mix.exs`, `mix.lock`, `pyproject.toml`, `uv.lock` | Compiler, translator, dependencies and checker versions |
| `mutants/`, witnesses and property generators under `test/` | Whether the intended faults and input domains are still exercised |

These are examples to navigate the code, not an exhaustive filename-based classifier. Follow changed helpers too.

To distinguish proof repair from a changed claim:

1. Inspect the base-to-head diff with enough context to identify the enclosing declaration. For example, start with `git diff -U20 BASE HEAD -- test/laws test/support/lean`; open the complete declaration in both revisions when it extends beyond the context. A `-U0` diff is insufficient, and language-dependent function-context detection may miss Lean boundaries.
2. In a law `.exs` file, changed lines outside the `proof: ~LEAN` sigil body require Tier 1 review. Context lines alone are not changes. Inside the sigil, apply the same Lean rules as for a `.lean` file.
3. Classify by the enclosing declaration, not just keywords on the changed line. Any edit inside a `def`, `abbrev`, `instance`, `structure`, `inductive`, `class`, `macro`, `macro_rules`, `syntax`, `elab`, `notation`, `axiom` or `opaque` declaration is Tier 1, including its body. A definition proved with `by` is still a definition.
4. Review changes to surrounding commands as Tier 1 too: `set_option`, `open`, `import`, `attribute`, `unsafe`, `variable`, `universe`, `namespace`, `section`, `end`, `export`, `local`, `scoped`, `deriving`, `initialize`, `run_cmd` and `#eval`. They can change dependencies, binders, interpretation or checking behavior without touching a theorem signature.
5. Tier 3 is limited to changes inside a `theorem`, `lemma` or `example` proof after its `:=` (with or without `by`), or inside an existing law's proof sigil, with statements and dependencies unchanged. Inspect nested declarations and commands using the same rules. Compare complete signatures, including multiline binders and attributes. If you cannot establish the boundaries, use Tier 1 review.

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

The agent's summary orients review; inspect the diff to decide what changed.

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

Match the report to the source revision and claims you reviewed.

For Tier 2 runtime changes, follow the [server and journal audit](audit.md#server-and-journal-follow-one-confirmation-through-failure): inspect caller authentication; correlation of late worker results with the current attempt; sync-before-transition/effects ordering; crash replay and incomplete-tail handling; and remote retry identity. Require runtime or fault-injection regressions for changed paths. Re-run the committed policy traces whenever Ledger changes.

## Practice on Seven Proposed Changes

These are abbreviated teaching diffs, not patches to apply to the working ledger. A diff hunk is one block of nearby changes. `-` removes a line; `+` adds one. For each, identify the tier and explain whether the guarantee changes. If it does, give a distinguishing input. The unchanged proof bodies are omitted.

**A — Broader exposure helper** — `lib/hold_ledger/spec.ex`; the law file is untouched:

```diff
   def exposed_entry?({_, _, _, _, entries}, key, amount) do
     case lookup(entries, key) do
       {:ok, {^key, ^amount, status}} -> status in [:sent, :unknown, :authorized, :voiding]
-      _ -> false
+      _ -> true
     end
   end
```

**B — Faster accounting** — implementation and reference change together:

```diff
--- lib/hold_ledger/ledger.ex
-        {{amount_limit, hold_limit, used_amount, used_holds, set_status(entries, key, :unknown)},
+        {{amount_limit, hold_limit, 0, 0, set_status(entries, key, :unknown)},
--- lib/hold_ledger/spec.ex
-      used_amount == hold_amount(entries) and used_holds == hold_count(entries) and
```

**C — Cleaner key types** — `test/laws/po_b5_voided_test.exs`:

```diff
-      requires: Spec.valid?(s) and Spec.lookup(elem(s, 4), key) == {:ok, {key, amount, :voided}},
+      requires: Spec.valid?(s) and is_integer(key) and Spec.lookup(elem(s, 4), key) == {:ok, {key, amount, :voided}},
```

**D — Remove obsolete verification** — both inventory files lose a group. Here the teaching diff shows only the identity fields; the proposed change deletes the entire corresponding object from each file and deletes its law file:

```diff
--- verification/obligations.json
-      "slug": "po_b5_voided",
-      "law": "po_b5_voided",
--- verification/laws.json
-      "slug": "po_b5_voided",
-      "law": "po_b5_voided",
--- test/laws/po_b5_voided_test.exs
(deleted)
```

**E — Proof-only cleanup** — the summary says `Claim delta: none`. In a hypothetical Lean model, the diff is:

```diff
 def valid (used limit : Int) : Prop :=
-  0 ≤ used ∧ used ≤ limit
+  0 ≤ used
```

All theorem signatures remain unchanged. Does that make it proof-only?

**F — Simpler postcondition** — `test/laws/po_a4_duplicate_test.exs`:

```diff
-      expects: Ledger.request(s, key, amount) == {s, :duplicate, []},
+      expects: Spec.valid?(elem(Ledger.request(s, key, amount), 0)),
```

**G — Shorter proof** — a standalone Lean example; its statement is unchanged:

```diff
 example (a b : Int) (fits : a ≤ b) : ¬ b < a := by
-  have bound : a ≤ b := fits
-  omega
+  omega
```

<details>
<summary>Answer key — open after reviewing the proposed changes</summary>

A weakens a helper used by the retention conclusion. An empty ledger, key `11` and amount `300` now satisfy `exposed_entry?` despite having no matching entry. The law text is unchanged, but the predicate no longer requires the issued identity to remain recorded. This is Tier 1.

B weakens validity to accommodate premature release; restore the accounting contract and repair behavior unless a human approves different policy.

C removes noninteger lookup queries: stored key `1` is found by `1.0` under `==`; public event guards do not define this theorem's domain.

D removes required coverage from both inventories; compare with the base revision and policy.

E weakens the definition by removing the upper bound; `used = 101`, `limit = 100` now satisfies it. Unchanged theorem signatures do not preserve their meaning when a referenced definition changes.

F drops the duplicate result, exact unchanged state and empty effects. A valid state with a rejection result could satisfy the new conclusion. Restore the duplicate contract. B through F also require Tier 1 review.

G is Tier 3: it removes an unnecessary intermediate fact from the proof while preserving the statement and dependencies. The revised proof checks with `omega`. For maintained proof work, require fresh full acceptance on the reviewed source; the tactic lines themselves need no further semantic review.

</details>

> **Limits.** A failed tactic or timeout is not a counterexample; mutation attribution needs a checked baseline and reproduced violation. A survivor is informative only after confirming the fault and completed checks. Kernel checking validates proofs against their definitions and assumptions. Compiler/translator correspondence, OS and storage behavior, and real processor guarantees remain part of the trust decision. This workflow does not certify those dependencies. The [assurance audit](audit.md) examines those boundaries; [Verification](verification.md) defines acceptance evidence.
