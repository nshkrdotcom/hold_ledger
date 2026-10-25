defmodule HoldLedger.Laws.L5FreshTest do
  use ExUnit.Case
  use HoldLedger.ProofCase

  alias HoldLedger.{Ledger, Spec}, warn: false

  # L5 (L): fresh positive entry contributes exactly one hold.
  # Witness: test/hold_ledger_witness_test.exs.
  # Proof scope and commands: guides/verification.md.
  laws "l5_fresh" do
    law(l5_fresh(entries, key, amount),
      requires:
        Spec.proper_entries?(entries) and Spec.unique_keys?(entries) and is_integer(key) and
          is_integer(amount) and amount > 0 and not Spec.has_key?(entries, key),
      expects:
        Spec.proper_entries?([{key, amount, :reserved} | entries]) and
          Spec.unique_keys?([{key, amount, :reserved} | entries]) and
          Spec.hold_amount([{key, amount, :reserved} | entries]) ==
            Spec.hold_amount(entries) + amount and
          Spec.hold_count([{key, amount, :reserved} | entries]) == Spec.hold_count(entries) + 1,
      proof: ~LEAN"""
      exact Elixir.HoldLedger.ProofContracts.«l5_fresh/3» entries key amount requires
      """
    )
  end
end
