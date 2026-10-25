# M5 — rejects every otherwise eligible request

One source-only mutation of `lib/hold_ledger/ledger.ex`. This source is never
loaded into the default reducer. Apply `mutant.patch` in an isolated checkout;
never modify `HoldLedger.Spec` or the law statements.

- Concrete input: `s = {1000, 3, 0, 0, []}`, `event = {:request, 22, 100}`
- Required unchanged result: `{{1000, 3, 100, 1, [{22, 100, :reserved}]}, :admitted, []}`
- Formal law group: `po_a2` (`PO-A2`); baseline must be independently checked
  first or formal mutant attribution is **unavailable**.
- Contract contradiction: Rejecting all valid admissions can be safe but violates required positive completeness.

`uv run --locked python scripts/run_mutants.py --execute` performs the baseline ordinary witness,
patches an isolated temporary copy, runs this witness and the ordinary suite,
then runs the unmodified targeted Lynx group uncached and checks exports if any.
A law compilation/tactic error is *not* itself a formal counterexample.
