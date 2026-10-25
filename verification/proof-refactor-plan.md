# Shared proof library and completion of all 29 laws

## Objective and constraints

Refactor the repeated Lean arguments into reusable, kernel-checked theory, then complete PO-B5/declined, PO-B5/voided and PO-C3 without narrowing input domains, weakening conclusions, adding admissions, changing runtime behavior, or making Ledger depend on Spec. Keep the exact existing law declarations. Commit reviewable increments, push the final result, and only then launch a detached full run with persistent records. No subagents are authorized.

## Critical assessment of the supplied review and plan

The domain is well suited to demonstrating a small functional core with meaningful accounting, identity, uncertainty and recovery boundaries. Repeated local induction proofs and repeated whole-step proofs are a substantial maintenance problem. Sharing them before finishing the remaining laws is the intended order.

The supplied assessment also contains claims that must not become requirements or documentation:

- Translating Core Erlang does not prove translator, compiler or BEAM correctness. An intent-generation law does not assume delivery to prove its pure conclusion; operational payment guarantees require separate assumptions.
- Expiry is not universally three to seven days. Adding explicit time events need not make the reducer impure. This project deliberately excludes expiry and multiple owners; it is not a verified payment integration.
- Structural independence reduces common implementation errors; it does not itself prevent vacuous preconditions or incorrect specifications. Concrete witnesses help establish satisfiability, while mutation experiments test specific detection behavior.
- B5 is a one-event theorem with an existing terminal lookup, not a quantified history theorem. Terminal absorption can then be lifted by induction. Calling it the uniquely most important theorem is an assessment, not a technical fact.
- C1 and C2 already cover validity across histories. Their existence means that not every history invariant is currently missing.
- C3 needs a terminal-preservation argument, but it need not literally import the B5 law: proving an equivalent general lemma is sufficient. The stated dependency is logical, not a constraint on theorem names.
- C3 additionally requires `Ledger.run(s, events) == Spec.expected_run(s, events)`. Its proof needs one-step agreement with the independent oracle, successful structured step results, valid successor states, compositional identity and terminal preservation, and authorization evidence. Merely citing B4/B5/B6 is insufficient.
- B5's key and amount arguments are not explicitly constrained to integers. Its source uses Erlang loose equality. A proof must preserve that original domain, including numerically equivalent integer/float terms, rather than silently assume structural equality or add integer guards.
- Lean default and paranoid are configurations of one checker, alongside other implementations. Kernel agreement does not verify the modeled semantics against the runtime.
- A strict toolchain improves reproducibility but does not guarantee deterministic byte-for-byte exports. Historical proof sizes and timings describe a particular baseline.
- A 1,500/1,800/2,000-line result, halved verification time, 180 MB exports, specific heartbeat reductions, and elimination of checker stack failures are hypotheses, not measured outcomes. Exports repeat imported dependencies, so source deduplication alone may barely reduce them.
- Tactic-only sharing reduces source duplication but still repeats elaboration. Reusable theorem declarations are the target; proof and checker performance must be measured separately.
- On this pinned Lynx version, `prelude` loads before translated definitions and explicitly cannot refer to them. Directly importing a concrete Ledger lemma library there is circular. `Lynx.Case` also does not automatically expose another group's checked theorem for later groups. Citing an `ensures` function alone would cite a predicate, not a proof.
- A status replacement preserves terminals only under appropriate eligibility or different-key hypotheses. Replacing a terminal entry's own status arbitrarily is not a preservation theorem.
- A trace base case also needs reflexivity of executable Spec predicates; `rfl` alone need not discharge the complete C3 conjunction.
- Missing proofs do not imply concrete defects. No proof failure or timeout will be described as a counterexample without an executable witness.

## Implementation approach

Use repository-owned test tooling around the pinned Lynx translation/runner APIs. Assemble translated pure modules first, insert ordinary Lean support modules that import those definitions, and make law proof modules import the support theorems. Keep the dependency pin unchanged and do not patch vendored dependencies. Verify the adapter's dependency ordering, missing-theorem failure behavior, source-change invalidation, and inclusion of shared sources in escape scans and provenance.

Cold acceptance must actually check shared theory and law proofs; no stale build or warm proof cache may count as new acceptance. Preserve exported proof-object checks and axiom audits. Decide whether batching provides safe within-run reuse after testing the runner interface; do not promise speedups before measurement.

## Work sequence and progress

- [x] Cancel the superseded background run and mark its status cancelled.
- [x] Discard the abandoned, uncommitted B5 experiment; retain committed source unchanged.
- [x] Inspect the actual law contracts and pinned Lynx prelude/translation ordering.
- [x] Record this critique, constraints, implementation approach and review gates.
- [x] Establish the post-translation shared-module adapter and prove a small law through it; add failure-path tests before adopting it.
- [x] Extract common shape, lookup, accounting, structure and preservation lemmas, with explicit dependencies and narrow module responsibilities.
- [x] Refactor existing supported laws to cite shared theorems, especially S, C1, C2 and B3; preserve all requires/expects declarations exactly.
- [x] Run targeted uncached proofs during migration; record actual scope and results here. Commit the verified refactor in reviewable increments.
- [x] Prove general single-step terminal preservation; discharge both B5 laws with their original loose-equality domains.
- [x] Prove one-step Ledger/Spec agreement and the compositional lemmas needed for C3, then prove C3 by finite-list induction.
- [x] Update the catalog, fail-closed selection logic and tests to require all 29; remove unfinished/optional claims only when justified by completed proofs.
- [x] Run appropriate formatting, strict Credo, Dialyzer, ordinary/property/runtime tests, tooling tests, and docs/package checks. Report these separately from formal proof attempts.
- [x] Update user guides and README with accurate coverage, proof boundaries and commands; retain historical baseline provenance.
- [x] Review diffs for unchanged law domains, no admissions, complete proof/source auditing, and no generated artifacts tracked.
Final shipping procedure: commit and push the reviewed source, then invoke `scripts/background_laws.py` for the all-29 cold proof/export/six-checker run. Its launch receipt and subsequent progress are persisted in `tmp/verification/background-*/launcher.json` and `status.json`; these runtime records intentionally remain outside Git. Full independent acceptance remains pending until the persisted run succeeds; launching is not a pass.

## Current results and decisions

The original 26-group detached run was cancelled at the user's request. Its partial results are not a complete verification result. No application or specification behavior changes are planned. Work is proceeding in the existing checkout so the final pushed branch and detached verification use the same source; there is no other active local proof run.

### Shared-library implementation checkpoint

The first L1 pilot checked successfully through the adapter. Shared contract predicates are generated directly from each existing law’s AST, and final law proofs must typecheck against their original translated predicates. Empty/skipped/missing theorem results are rejected. Tooling scans all shared Lean sources for proof escapes and records their hashes.

The larger pilot exposed duplicate auto-generated `induct_unfolding` declarations when independently compiled sibling modules used functional induction on the same translated function. A single imported Induction module now materializes that support once. Source extraction also exposed helper closures over local facts; those remain local rather than acquiring hidden assumptions. General accounting helpers explicitly use the shared holding-status model. These migration failures were tooling/proof-engineering failures, not concrete ledger counterexamples.

The library currently contains about 3,300 Lean lines, before the remaining three proofs. This is a source measurement only. The batch runner assembles shared theory once per cold request, preserving kernel checks, so reuse does not depend on warm caches. The original 26-group batch is being checked before further proof development.

The refactored PO-S passed a cold native proof run. L1 also passed proof export, all six checker configurations, and its axiom audit through the new adapter. All 29 requires/expects declarations were compared against the committed source and remain identical. Ordinary checks currently pass: 100 tests plus 22 properties, 14 tooling tests, strict Credo, and Dialyzer with zero errors/skipped warnings. A fresh 26-group native regression batch is running while B5 is developed on the checked shared core.

The migrated 26-group set passed a single cold native Lean batch in 564.757 seconds. This is proof-only evidence, not a six-checker acceptance of the whole suite. The tested L1 pilot separately passed all six configurations and the axiom audit. Shared proof source is approximately 3,300 lines before terminal/history completion; no claimed export-size or peak-memory reduction has been established.

Both PO-B5/declined and PO-B5/voided now pass cold native Lean checks through one shared terminal-lookup theorem. Their original loose numeric equality domains are retained. Independent full-suite acceptance will be established by the final detached run, not inferred from these proof-only checks.

The terminal proofs were committed as `798a323`. C3 development now includes an explicit oracle-normalization theorem: the independent Spec transition is compared with the reducer output after recomputing counters; successor validity then proves that normalization changes nothing. This keeps agreement separate from preservation and avoids changing either executable implementation.

The list-composition helpers passed native checking: lookup extraction from identity predicates, transitive identity preservation, and the terminal-entry predicate assembled from pointwise preservation. Development retries now support dependency/source-keyed caches, with a test proving that shared-source edits invalidate downstream keys. Acceptance commands remove the development-cache environment variable and reject any cached native module result.

PO-C3 passed native checking with the final shared Oracle, HistoryRelations and History modules. Its finite-list induction composes successor validity, exact Ledger/Spec transition agreement, identity composition, pointwise terminal lookup preservation, and approval evidence. The subsequent fresh C3 cold run passed; the final all-29 exported/six-checker run remains scheduled after the push. All 29 law declarations retain their original domains and conclusions.

### Completion review in progress

All 29 law statements remain byte-for-byte identical in their requires/expects regions to the pre-refactor source. The new total is 3,939 nonblank Lean lines across shared source and embedded blocks, compared with 9,276 embedded nonblank Lean lines before the refactor (including the unfinished attempts): 57.5% less source, rather than the supplied plan’s unsupported 80% forecast.

Current ordinary validation passes: 101 tests and 22 properties; 16 tooling tests; format, compile with warnings as errors, strict Credo, and Dialyzer (zero errors/skipped warnings). Docs, Hex package inclusion, local guide links, demo, pinned-tool checks and six static mutation patch anchors pass. Native mutation experiments were not run and no mutation-detection claim is added. C3’s final cold native check passed; the all-29 six-checker acceptance run will launch after push.

### Proof completion

The final PO-C3 cold native run passed with `LYNX_CACHE=0` and the development cache removed by the runner (`tmp/proof-work/c3-cold.json`). All three previously outstanding laws are now complete. The refactored 26-group cold batch and both B5 cold checks passed separately; the combined all-29 export/six-checker run remains deliberately scheduled after push. No proof admissions, custom axioms, narrowed hypotheses, weakened conclusions, runtime/spec changes or disabled checks were introduced. All 29 groups are required by supported selection.

The completion changes also replace stale exclusions in README, verification/crash-course/troubleshooting guides, demo output, changelog, catalog and agent instructions. Historical baseline data is retained and explicitly historical. Development cache use is labeled and rejected by acceptance validation; it does not substitute for the cold results above.

### Final acceptance result

The source was committed and pushed as `08c25a4`. The subsequent detached cold
full run completed successfully on 2026-10-25: all 29 groups, all six checker
configurations, and the permitted-axiom audit passed. The run is preserved in
`tmp/verification/background-20261025T082451459426Z/`. Native proof/export took
620.549 seconds and checker execution 65.162 seconds. The export is 100,962,008
bytes, SHA-256
`54b6389b5bd5aac60edf1f78dace8ba005d89abe46294d09d87f71c5092e63df`.
No Nanoda retry was needed. This completes the planned machine acceptance; it
does not constitute independent human review of policies or proof tooling.
