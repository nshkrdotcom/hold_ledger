defmodule HoldLedger.Laws.PoB1RestartTest do
  use ExUnit.Case
  use HoldLedger.ProofCase

  alias HoldLedger.{Ledger, Spec}

  # PO-B1/restart (P0): restart preserves validity for all valid states and arbitrary arguments.
  # Witness: test/hold_ledger_witness_test.exs.
  # Proof scope and commands: guides/verification.md.
  laws "po_b1_restart", options: [maxHeartbeats: 2_000_000] do
    law(po_b1_restart(s),
      requires: Spec.valid?(s),
      expects: Spec.valid?(elem(Ledger.restart(s), 0)),
      proof: ~LEAN"""
      exact Elixir.HoldLedger.ProofContracts.«po_b1_restart/1» s requires
      """
    )
  end
end
