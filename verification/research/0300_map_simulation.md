# 0300-06 research: exact ordered-map simulation obligation

This document is an engineering **obligation**, not a Lean proof or registered
claim. It applies exclusively to `HoldLedger.Research.MapLedger`, loaded from
`verification/research/0300_map_ledger.ex` by test and benchmark scripts. This
module is not compiled into the application, called by the runtime, included in
Hex package inputs, or listed in the 49 original formal claim groups.

## Selected domain and relation

- `s` is any five-tuple satisfying the **unchanged independent** `Spec.valid?/1`.
  This includes signed integer keys, positive integer amounts, all seven statuses,
  exact exposure/hold counters, order, and terminal tombstones.
- `e` is **any Elixir term**, not merely a valid Event-schema term. All malformed
  and fallback event behavior is observable.
- `t` is a `MapLedger` struct satisfying `MapLedger.valid?/1` with precisely
  one `cells` entry per integer key in the ordered `order` list, no extra keys,
  equal counters/limits and exact status/amount values.
- `R(s, t)` means `Spec.valid?(s) and MapLedger.valid?(t)` and
  `MapLedger.decode(t) === s`. Strict equality also fixes list order.
- Public helper `Ledger.find(entries, x)` has a broader lookup-key domain than
  events (`1 == 1.0`). Candidate `find/2` matches this domain through ordered
  fallback for nonintegers rather than narrowing original L1.

## Proof statement to discharge in Part B before formal promotion

For all `s, t, e` in this domain, if `R(s,t)` and
`Ledger.step(s,e) = {s2,r,eff}` and
`MapLedger.step(t,e) = {t2,r2,eff2}`, establish
`R(s2,t2) and r2 = r and eff2 = eff`. Show the same conclusion using the
**independent** `Spec.expected_step/2` oracle; the proof cannot call back into
`Ledger` or `Spec` inside the candidate. Cover all event heads, guards and
fallbacks, and both capacity rejections. Explicitly preserve the key bijection,
newest-first insertion, terminal key memory and ordered effects.

Base case: `decode(encode(s)) === s` for each `Spec.valid?(s)`.
Inductive step: the one-step simulation above preserves `R`.
Finite history: induct on a proper finite event list; after each prefix the
candidate state decodes strictly to the Ledger and Spec state. `run/2` discards
all emitted effects on both sides; individual transitions retain effects.

An actual theorem requires a reviewed model/abstraction into Lean at the pinned
Lynx version, a kernel-checked proof, approved claim registration, current-source
exports and all six checkers. **No such new theorem or obligation is registered
in Part A.** Passing deterministic/property tests is not the missing proof.

## Adversarial concrete controls

`test/support/fixtures.ex` contains literal, independent expected tuples/results:
malformed or nonpositive amounts/keys, duplicate/conflict before caps, hold
priority over amount, exact fit, dispatch/stored intent, timeout, restart,
retry, both processor outcomes, voiding/terminal release, tombstone reuse,
arbitrary unrecognized events and mixed ordered states.

`test/hold_ledger_map_equivalence_test.exs` compares literal expectations with
three distinct engines: the existing Ledger, independent Spec, and map
candidate. It also checks malformed candidates fail closed, broad numeric
helper lookup, exact history prefixes, and StreamData property/differential
cases without changing original law generators. These are test assertions, not
an all-domain mathematical proof.

## Benchmark method, not a performance guarantee

Run `MIX_ENV=test mix run scripts/phase4_map_bench.exs` after confirming the
pinned environment. Use `HOLD_LEDGER_BENCH_ITERATIONS` for an explicit bounded
warmup/cost sample. Compare source-list lookup, indexed lookup, insert request,
map-state encoding and decoding at 0/16/256/2048 retained terminal entries.
This microbenchmark is intentionally not a throughput, memory or journal/replay
claim. For production comparison, separately record complete journal replay,
state serialization, runtime process boundaries, allocations, order changes,
effects and startup under representative workloads. A map is not automatically
faster end-to-end; no benchmark results are claimed from the snapshot session.

## Stop / rollback

If any strict list-order, numeric helper or Spec disagreement appears, keep the
candidate unshipped and do not change Ledger. Undo only the owned C1 research
module, tests, fixture/generator additions and benchmark; do not touch
protected Ledger/Spec, original claims, anchors, checker exports or the Phase 3
accepted baseline. Formally promoted claims require separate policy review.
