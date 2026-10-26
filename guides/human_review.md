# Human review of agent changes

An agent tells you it repaired a proof and everything is green. What should you look at first? **The claim, not the tactics.** Lean checks that a proof establishes the statement it was given; it cannot decide whether that statement still protects a payment authorization after a lost reply.

Use this guide to review one proposed change. The [crash-course glossary](formal_verification_crash_course.md#glossary) explains Lean and Lynx terms; the [agentic walkthrough](agentic_verification.md) shows the work that leads to a review. For a whole-system inspection of models and foundations, use the advanced [assurance audit](audit.md).

A useful short rule is:

- **Proceed under agreed policy.** Agents can repair code, add tests and prove an unchanged claim. Check the submitted evidence and diff.
- **Review changes to meaning.** A different precondition, postcondition, called predicate, theorem signature, model, inventory, import or trusted foundation can change what a green result means.
- **Ask for a decision when authority is missing.** Conflicting requirements, a new release rule, a changed processor assumption or a proposed risk tradeoff need an authorized policy decision. The agent should present evidence and alternatives, not quietly choose one.

The author need not be human. The important question is whether approved requirements and reliable evidence already cover the change, or whether someone still has to decide the policy.

## What to delegate and what to decide

| Work | Agent contribution | Where review matters |
|---|---|---|
| Identify requirements | Gather written policy, prior traces, interfaces and disputed cases; propose interpretations | Decide which source or new policy governs when sources conflict |
| Draft claims | Generate `requires`, `expects`, Lean statements and plain-English readings | Check input domains, promised outcomes, dependencies and omissions |
| Challenge claims | Generate valid cases, wrong outputs for valid inputs, invalid inputs when relevant, mutations and counterexamples | Check that expected outcomes have an independent justification; investigate conflicts |
| Prove and test | Implement, prove, run focused checks and inspect failures | Distinguish established results from unresolved checks and changed assumptions |
| Summarize evidence | Compare old/new contracts, name trusted dependencies, report exact source and commands | Judge consequential changes and risk that remains after the checks |

Agents can carry out implementation and proof work within agreed requirements. Review changes to those requirements separately from proof repairs. The table describes **responsibilities**, not a requirement for a person to type every theorem.

## Classify the diff

| Tier | Diff | Action |
|---|---|---|
| 1 | Claims, definitions, theorem signatures, Spec, coverage, foundations or checking machinery | Review meaning, scope and assumptions. Escalate a policy or trust-boundary decision; use gathered evidence to assess changes already authorized. |
| 2 | Ledger and runtime implementation | Review affected behavior and boundaries; rerun committed policy traces for every Ledger change. |
| 3 | Only confirmed proof-body changes | Require fresh full acceptance on the reviewed source; a semantic review of unchanged statements need not be repeated for a tactic edit. |
| Documentation | Explanations of existing behavior | Check against source; an edit changing the policy in `guides/specification.md` is Tier 1. |

In Hold Ledger, apply Tier 1 review to these meanings and boundaries:

| Files | What to inspect |
|---|---|
| `guides/specification.md`, `AGENTS.md` | Intended policy and the instructions that constrain agent changes |
| `lib/hold_ledger/spec.ex`, `test/laws/*.exs` | Reference behavior, assumptions and conclusions; classify embedded proof changes separately below |
| `test/support/lean/*.lean`, `test/support/proof_case.ex` | Model definitions, theorem signatures, generated predicates and translation wiring |
| `verification/obligations.json`, `verification/laws.json`, `verification/baseline.json` | Required claims, registered groups and historical evidence |
| `scripts/`, `.github/`, `tooling_tests/` and toolchain/dependency pins | Whether incomplete checks can pass, and whether reports identify the intended source and tool versions |
| `mutants/`, witnesses and property generators under `test/` | Whether the intended faults and input domains are still exercised |

These are examples to navigate the code, not an exhaustive filename-based classifier. Follow changed helpers too.

To distinguish proof repair from a changed claim:

1. View enough diff context to identify the enclosing declaration. Start with `git diff -U20 BASE HEAD -- test/laws test/support/lean`; open the full declaration in both revisions if necessary. A context-free diff can hide that the changed line belongs to a definition.
2. In a law `.exs` file, changes outside the `proof: ~LEAN` sigil need Tier 1 review, except for the resource-only edits described below. Inside the sigil, apply the same rules as for a `.lean` file.
3. Review anything that can change meaning or dependencies as Tier 1: definition bodies, types, instances, theorem signatures, imports, options and syntax extensions. Surrounding commands matter too: a `variable` declaration can alter later theorem binders. These are review triggers, not proof that the claim changed.
4. Tier 3 requires changes confined to an existing theorem, lemma or example proof, or a law's proof sigil, with statements and dependencies unchanged. Check nested declarations too. A `def` body remains Tier 1 even after `:=` or `by`. If you cannot establish the boundaries, use Tier 1 review.

A text-based diff classifier can help **triage**, but it cannot certify Tier 3. It may miss a changed declaration outside the hunk, imported theorem, instance, elaborator or altered meaning inside a helper. Use automated labels to locate suspected Tier 1 boundaries and ambiguous cases, then review the enclosing declarations before accepting the classification.

Use this checklist for Tier 1 review:

1. **Did the claim weaken?** Look for a stronger hypothesis, narrower domain, weaker conclusion or new environment assumption. Expand predicates rather than trusting names such as `valid` or `safe`.
2. **Can the hypotheses hold?** Run a concrete witness—an input satisfying the hypotheses. Check that excluded boundary cases are intentional; one witness does not establish adequate coverage.
3. **Does it match policy?** Compare with traces whose expected outcomes come from policy, rather than the implementation or oracle.
4. **Are obligations still required?** Compare against the base revision and requirements, not merely two inventories edited together. Nothing should disappear through selection, status, skipping or timeout handling.
5. **Is Spec independent?** The oracle (the independent reference specification) and implementation never call each other. If both changed, review each against the independently agreed policy; agreement alone is insufficient.
6. **Are the foundations intact?** Inspect changes to axioms, escape checks, translated definitions, adapters, toolchain and gate behavior.

## Establish expected behavior before proof work

Start with a policy sentence and a handful of traces. The agent can propose cases and alternate interpretations. Cite the policy clause or requirement decision behind each expected outcome, rather than deriving it from `Spec.expected_step/2` or the implementation. If the policy leaves a case open, resolve it before recording the expectation as an ordinary test.

For a new policy, cover a safety case, a case where something must succeed, a boundary, and relevant retry, failure or restart sequences. The state tuple is `{amount_limit, hold_limit, used_amount, used_holds, entries}`; keys are integers.

**Policy:** an issued authorization consumes capacity until trustworthy terminal evidence releases it.

| Initial state | Event sequence | Expected outcome |
|---|---|---|
| `{100, 1, 0, 0, []}` | `{:request, 1, 100}` | Admit: exact amount and last slot fit. |
| `{100, 2, 100, 1, [{1, 100, :authorized}]}` | `{:void, 1}`, then `{:request, 2, 100}` without confirmation | First hold stays `:voiding`; new request is `:insufficient_amount`. |
| `{100, 2, 100, 1, [{1, 100, :voiding}]}` | `{:void_confirmed, 1}`, `{:request, 2, 100}` | Release once; admit key 2. |
| `{100, 2, 0, 0, [{1, 100, :voided}]}` | `{:void_confirmed, 1}`, `{:request, 1, 100}` | Confirmation is stale; request is duplicate; counters stay zero. |
| `{100, 2, 100, 1, [{1, 100, :sent}]}` | `{:timeout, 1}`, `{:request, 2, 100}` | First hold becomes `:unknown`; refuse key 2. |
| `{100, 2, 100, 1, [{1, 100, :sent}]}` | `:restart`, `{:request, 2, 100}` | First hold becomes `:unknown`; refuse key 2. |

These examples are recorded in `test/human_policy_traces_test.exs`. Run them with:

```sh
uv run --locked python scripts/local_run.py mix test test/human_policy_traces_test.exs --exclude laws
```

A refuse-everything implementation preserves capacity limits. The first and third traces require admission as well as safety; PO-A2 covers eligible requests. Also check whether a contract permits wrong outputs for a valid input. The [worked contract challenge](agentic_verification.md#3-try-to-break-the-contract) shows how to do that.

## What to inspect in the agent report

Start with **did the meaning of any claim change?** Use the report to locate affected statements, definitions and assumptions, then check the diff. Inspect the commands, results and source identity behind a claimed pass, and distinguish ordinary tests from formal acceptance. Unresolved failures should remain visible.

Ask for the following in the change summary. This is a reporting format, not a substitute for checking the changed files:

```text
Policy: <requirement source and the required before/after behavior>
Claim delta: <old/new requires, expects, called definitions, or "none">
Review tier: <Tier 1/2/3, reasons, and any ambiguous declarations>
Changed files: <paths, including dependencies and tools>
Challenge evidence: <valid witness, forbidden output, boundary/temporal trace>
Ordinary checks: <exact commands, results, log or report paths>
Formal evidence: <law group, proof/full stage, status, source hashes>
Trusted assumptions: <processor, compiler/translator, journal, etc.>
Unresolved: <failed check, timeout, missing policy, or known limitation>
```

For example, a report that says `Claim delta: none` while `Spec.valid?/1` has lost its upper-bound check is not a harmless proof repair. The changed definition weakens every conclusion that relies on that predicate. Compare [exercise E](#practice-on-seven-proposed-changes) with its answer key to practice spotting this.

Inspect any proposed weakening against the requested behavior. If it requires a policy change or a new trusted assumption, resolve that decision before accepting the revised proof.

When a proof fails, run the witness and property for the same claim. If there is a counterexample, replay it and confirm the precondition holds while the conclusion fails. If there is not, inspect the goal, generator coverage and reference. Neither a test pass nor a failed proof attempt settles the disputed claim.

An edit confined to a literal heartbeat or timeout budget changes the resources available, not the claim. Review its cost and fresh results without reopening the meaning of an unchanged statement. This exception requires unchanged selection, translation and timeout-failure handling. Cutoffs, preludes, termination suffixes and other options still need Tier 1 review; a timeout must never be reported as success.

## Common ways a green result can mislead

| Symptom | Where to look | How to detect it |
|---|---|---|
| Impossible precondition | `requires`, called predicates | Construct a witness; look for contradictory bounds. |
| Conclusion omits the promised effect or admission | `expects` | Replay a trace that requires progress; “state unchanged” is correct only for specified cases. |
| Hard inputs disappear | New guards or typed encodings | Compare domains with the base revision; PO-B5 (a catalog label for a terminal-preservation obligation) permits lookup queries where `1 == 1.0`. |
| Desired result becomes a caller assumption | Hypotheses of the top-level theorem and its helper lemmas | Follow each assumption to independent evidence; do not assume the conclusion. |
| `valid?` becomes easier to satisfy | Spec or Lean definitions | Check whether it still requires exact totals, uniqueness and intended statuses. |
| Spec changes to match faulty code | Implementation and oracle diffs | Compare both with the policy traces. |
| A law and its inventory entry vanish together | Catalog and required inventory | Compare required coverage with the previous revision and policy. |
| Numeric identity is blurred | `==`, `===`, codecs, queried domains | Exercise `1` and `1.0`; decide where exact identity is required. |
| A witness or property becomes weaker or skipped | Tests, tags, generators, filters | Replay the original regression and inspect effective selection. |

## Use mutations to challenge claims

A mutant is a disposable copy of code with a deliberate change. Agents can propose likely policy violations, run experiments, inspect reports and minimize counterexamples. Reviewers should check the planted change against the intended behavior before deciding what a survivor means.

In `mutants/02_timeout_release/mutant.patch`, a sent hold of `300` becomes unknown while its counters fall to zero. The required result retains `300` and one slot. The M2 witness and PO-B1/timeout address this policy. Another mutant, `mutants/10_premature_void_release/`, releases capacity before terminal void confirmation. These mutations challenge different claims.

A useful sequence is: establish that the correct-source baseline passes; verify that the planted change actually violates a requirement; run the isolated ordinary and relevant formal checks; confirm that those checks completed; then interpret the result. A known violation that survives *completed* checks suggests a coverage gap. An equivalent mutant, incomplete run, proof timeout or tactic failure does not demonstrate a gap or detection on its own. Do not change Spec or the law to accommodate the mutant.

The ordinary baseline command is:

```sh
uv run --locked python scripts/local_run.py mix test test/mutations/preflight_test.exs --exclude laws
```

The [Testing guide](testing.md#deliberate-mutations) describes the optional isolated experiment and its cost.

## Read “green” precisely

| Result | What it establishes |
|---|---|
| Development proof attempt | The selected development check completed, not necessarily full exported-checker acceptance. |
| Catalog `supported` | A proof implementation is registered; this is not execution evidence. |
| Full acceptance | Every required obligation passed fresh proof/export checks, all six checker configurations and axiom checks for the reviewed source. A subset is partial acceptance. |
| CI green | The required jobs succeeded. The `formal-gate` job always runs, but the full `formal` job is conditional; see below. |

With a readable base-to-head diff, README/guides-only edits do not trigger the full formal job. `scripts/formal_gate.py` selects it for paths such as `lib/`, laws and `mix.exs`; an explicit request or unavailable diff also requires it.

Match fresh exports and report source hashes to the reviewed declarations. A cached development pass or a catalog label does not establish full acceptance. Keep pure proof checks, ordinary tests, runtime fault tests and processor assumptions separate.

For Tier 2 runtime changes, follow the [server and journal audit](audit.md#server-and-journal-follow-one-confirmation-through-failure): caller authentication; late worker correlation; sync-before-transition/effects ordering; crash replay and incomplete-tail handling; and remote retry identity. Require runtime or fault-injection regressions for changed paths. Rerun the committed policy traces whenever Ledger changes.

## When a decision can be delegated

Consider three changes involving a pending void:

| Situation | What the agent can do | What needs a decision |
|---|---|---|
| A refactor releases capacity on a void timeout | Cite the existing retention policy, reproduce the violation and repair the code | No new policy choice: the required behavior is already specified |
| A feature request says “release capacity after 24 hours” | Show the conflict with retention until trusted confirmation; construct a trace where the processor still holds the authorization | A person must resolve the conflicting requirements and the resulting exposure risk |
| An agent proposes classifying future timeout repairs automatically | Evaluate it on previously reviewed changes, including hidden predicate edits and misleading “proof-only” summaries | Decide which cases the evidence supports delegating and which still need review |

For the first row, start with `s = {100, 2, 100, 1, [{1, 100, :voiding}]}`. Applying `{:timeout, 1}` must return `{s, :stale, []}`. Releasing capacity would contradict that trace.

For the classification example, justify each expected classification with the diff and the requirement it affects. A replayable violation, such as a mutant failing a policy trace, can support that judgment. An agent can replay the check; agreeing with another generated label is not enough.

### Evaluate delegation rather than counting fewer interruptions

Before letting an agent classify more changes without review, test whether it catches the decisions that matter. Start with independently justified labels for known diffs, including a policy citation and a distinguishing trace where one exists. Use the seven exercises below for practice, **not** as a held-out evaluation set after the agent has seen the answers.

Resolve disputed labels before scoring a run. For a separate evaluation set whose answers the agent has not seen, record at least: actual tier, whether policy/assumptions changed, expected escalation, evidence for that label, agent label and justification, and whether the agent asked for help. Review the cases where the agent missed a consequential semantic change and where it unnecessarily blocked an ordinary repair. A conservative `uncertain / escalate` classification is preferable to a confident but false Tier 3 label; track that uncertainty separately rather than pretending it is a correct autonomous decision.

For each evaluation run, look at:

| Measure | Why it matters |
|---|---|
| Missed semantic or trust-boundary changes | The dangerous failure: the agent treats a changed requirement as proof-only work |
| Correctly resolved established-policy repairs | Whether useful work continues without unnecessary policy decisions |
| Unnecessary escalations | Cost of caution; worth measuring, not optimizing in isolation |
| Evidence quality and honest unresolved results | Whether the agent distinguishes a demonstrated counterexample, a failed tactic and full acceptance |

Delegation can grow one reviewed decision class at a time; success on timeout repairs does not authorize new processor assumptions or a changed capacity-release policy.

## Practice on seven proposed changes

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

E weakens the definition by removing the upper bound; `used = 101`, `limit = 100` now satisfies it. Theorems that conclude `valid` no longer promise `used ≤ limit`; theorems that assume it must now cover a larger domain. Unchanged theorem signatures do not preserve their meaning when a referenced definition changes.

F drops the duplicate result, exact unchanged state and empty effects. A valid state with a rejection result could satisfy the new conclusion. Restore the duplicate contract. B through F also require Tier 1 review.

G is Tier 3: it removes an unnecessary intermediate fact from the proof while preserving the statement and dependencies. The revised proof checks with `omega`. For maintained proof work, require fresh full acceptance on the reviewed source; the tactic lines themselves need no further semantic review.

</details>

The [assurance audit](audit.md) examines compiler, runtime and processor trust boundaries; [Verification](verification.md) defines acceptance evidence.
