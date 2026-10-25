defmodule HoldLedger.Laws.PoA3Test do
  use ExUnit.Case
  use HoldLedger.ProofCase

  alias HoldLedger.{Ledger, Spec}

  # PO-A3 (P0): any not-applied operation returns input unchanged and no intents.
  # Witness: test/hold_ledger_witness_test.exs.
  # Proof scope and commands: guides/verification.md.
  laws "po_a3", options: [maxHeartbeats: 1_000_000] do
    law(po_a3(s, event),
      requires: Spec.valid?(s) and Spec.not_applied_result?(elem(Ledger.step(s, event), 1)),
      expects: Ledger.step(s, event) == {s, elem(Ledger.step(s, event), 1), []},
      proof: ~LEAN"""
      exact Elixir.HoldLedger.ProofContracts.«po_a3/2» s event requires
      """
    )
  end
end
