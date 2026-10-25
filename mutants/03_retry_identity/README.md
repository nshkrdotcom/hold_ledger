# M3 — retry changes authorization identity

One source-only mutation of `lib/hold_ledger/ledger.ex`. This source is never
loaded into the default reducer. Apply `mutant.patch` in an isolated checkout;
never modify `HoldLedger.Spec` or the law statements.

- Concrete input: `s = {1000, 3, 300, 1, [{11, 300, :unknown}]}`, `event = {:retry, 11}`
- Required unchanged result: `{{1000, 3, 300, 1, [{11, 300, :sent}]}, :retried, [{:authorize, 11, 300}]}`
- Formal law group: `po_b3` (`PO-B3`); baseline must be independently checked
  first or formal mutant attribution is **unavailable**.
- Contract contradiction: A retry must reuse key 11 and the stored original amount 300.

`uv run --locked python scripts/run_mutants.py --execute` performs the baseline ordinary witness,
patches an isolated temporary copy, runs this witness and the ordinary suite,
then runs the unmodified targeted Lynx group uncached and checks exports if any.
A law compilation/tactic error is *not* itself a formal counterexample.
