defmodule HoldLedger.Laws.PoA4ConflictTest do
  use ExUnit.Case
  use HoldLedger.ProofCase

  alias HoldLedger.{Ledger, Spec}

  # PO-A4 (P0): seen key different positive amount conflicts across all statuses.
  # Witness: test/hold_ledger_witness_test.exs.
  # Proof scope and commands: guides/verification.md.
  laws "po_a4_conflict" do
    law(po_a4_conflict(s, key, amount, original, status),
      requires:
        Spec.valid?(s) and is_integer(key) and is_integer(amount) and amount > 0 and
          amount != original and Spec.lookup(elem(s, 4), key) == {:ok, {key, original, status}},
      expects: Ledger.request(s, key, amount) == {s, :conflict, []},
      proof: ~LEAN"""
      exact Elixir.HoldLedger.ProofContracts.«po_a4_conflict/5» s key amount original status requires
      """
    )
  end
end
