defmodule HoldLedger.Laws.PoA1Test do
  use ExUnit.Case
  use HoldLedger.ProofCase

  alias HoldLedger.{Ledger, Spec}

  # PO-A1 (P0): request preserves validity for arbitrary key and amount terms.
  # Witness: test/hold_ledger_witness_test.exs.
  # Proof scope and commands: guides/verification.md.
  laws "po_a1", options: [maxHeartbeats: 4_000_000] do
    law(po_a1(s, key, amount),
      requires: Spec.valid?(s),
      expects: Spec.valid?(elem(Ledger.request(s, key, amount), 0)),
      proof: ~LEAN"""
      exact Elixir.HoldLedger.ProofContracts.«po_a1/3» s key amount requires
      """
    )
  end
end
