# M1 — terminal reuse / duplicate key

One source-only mutation of `lib/hold_ledger/ledger.ex`. This source is never
loaded into the default reducer. Apply `mutant.patch` in an isolated checkout;
never modify `HoldLedger.Spec` or the law statements.

- Concrete input: `s = {1000, 3, 0, 0, [{11, 300, :voided}]}`, `event = {:request, 11, 300}`
- Required unchanged result: `{s, :duplicate, []}`
- Formal law group: `po_a4_duplicate` (`PO-A4`); baseline must be independently checked
  first or formal mutant attribution is **unavailable**.
- Contract contradiction: A released key remains permanently remembered. A revived key would violate uniqueness.

`uv run --locked python scripts/run_mutants.py --execute` performs the baseline ordinary witness,
patches an isolated temporary copy, runs this witness and the ordinary suite,
then runs the unmodified targeted Lynx group uncached and checks exports if any.
A law compilation/tactic error is *not* itself a formal counterexample.
