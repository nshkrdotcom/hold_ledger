# M6 — ack treated as authorization result

One source-only mutation of `lib/hold_ledger/ledger.ex`. This source is never
loaded into the default reducer. Apply `mutant.patch` in an isolated checkout;
never modify `HoldLedger.Spec` or the law statements.

- Concrete input: `s = {1000, 3, 300, 1, [{11, 300, :sent}]}`, `event = {:transport_ack, 11}`
- Required unchanged result: `{s, :stale, []}`
- Formal law group: `po_b4` (`PO-B4`); baseline must be independently checked
  first or formal mutant attribution is **unavailable**.
- Contract contradiction: Transport delivery acknowledgment is not processor approval.

`uv run --locked python scripts/run_mutants.py --execute` performs the baseline ordinary witness,
patches an isolated temporary copy, runs this witness and the ordinary suite,
then runs the unmodified targeted Lynx group uncached and checks exports if any.
A law compilation/tactic error is *not* itself a formal counterexample.
