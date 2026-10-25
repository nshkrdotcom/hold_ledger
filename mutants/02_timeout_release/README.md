# M2 — timeout erroneously releases a reservation

One source-only mutation of `lib/hold_ledger/ledger.ex`. This source is never
loaded into the default reducer. Apply `mutant.patch` in an isolated checkout;
never modify `HoldLedger.Spec` or the law statements.

- Concrete input: `s = {1000, 3, 300, 1, [{11, 300, :sent}]}`, `event = {:timeout, 11}`
- Required unchanged result: `{{1000, 3, 300, 1, [{11, 300, :unknown}]}, :marked_unknown, []}`
- Formal law group: `po_b1_timeout` (`PO-B1/timeout`); baseline must be independently checked
  first or formal mutant attribution is **unavailable**.
- Contract contradiction: Unknown retains its own 300 cents and one hold after a timeout.

`uv run --locked python scripts/run_mutants.py --execute` performs the baseline ordinary witness,
patches an isolated temporary copy, runs this witness and the ordinary suite,
then runs the unmodified targeted Lynx group uncached and checks exports if any.
A law compilation/tactic error is *not* itself a formal counterexample.

The local execution corrected the original runner mapping: PO-B2 preserves
status/identity and does not assert unchanged counters. PO-B1/timeout states
that accounting obligation directly; no law contract was changed.
