defmodule HoldLedger.Laws.PoA4DuplicateTest do
  use ExUnit.Case
  use HoldLedger.ProofCase

  alias HoldLedger.{Ledger, Spec}

  # PO-A4 (P0): all seen keys including terminal matching-amount requests duplicate.
  # Witness: test/mutations/preflight_test.exs.
  # Proof scope and commands: guides/verification.md.
  laws "po_a4_duplicate" do
    law(po_a4_duplicate(s, key, amount, status),
      requires:
        Spec.valid?(s) and is_integer(key) and is_integer(amount) and amount > 0 and
          Spec.lookup(elem(s, 4), key) == {:ok, {key, amount, status}},
      expects: Ledger.request(s, key, amount) == {s, :duplicate, []},
      proof: ~LEAN"""
      exact Elixir.HoldLedger.ProofContracts.«po_a4_duplicate/4» s key amount status requires
      """
    )
  end
end
