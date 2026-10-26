defmodule HoldLedger.Laws.PoB1VoidConfirmedTest do
  use ExUnit.Case
  use HoldLedger.ProofCase

  alias HoldLedger.{Ledger, Spec}

  # PO-B1/void_confirmed (P0): void preserves validity for all valid states and arbitrary arguments.
  # Witness: test/hold_ledger_witness_test.exs.
  # Proof scope and commands: guides/verification.md.
  laws "po_b1_void_confirmed", options: [maxHeartbeats: 2_000_000] do
    law(po_b1_void_confirmed(s, key),
      requires: Spec.valid?(s),
      expects: Spec.valid?(elem(Ledger.void_confirmed(s, key), 0)),
      proof: ~LEAN"""
      exact Elixir.HoldLedger.ProofContracts.«po_b1_void_confirmed/2» s key requires
      """
    )
  end
end
