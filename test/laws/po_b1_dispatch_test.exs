defmodule HoldLedger.Laws.PoB1DispatchTest do
  use ExUnit.Case
  use HoldLedger.ProofCase

  alias HoldLedger.{Ledger, Spec}

  # PO-B1/dispatch (P0): dispatch preserves validity for all valid states and arbitrary arguments.
  # Witness: test/hold_ledger_witness_test.exs.
  # Proof scope and commands: guides/verification.md.
  laws "po_b1_dispatch", options: [maxHeartbeats: 2_000_000] do
    law(po_b1_dispatch(s, key),
      requires: Spec.valid?(s),
      expects: Spec.valid?(elem(Ledger.dispatch(s, key), 0)),
      proof: ~LEAN"""
      exact Elixir.HoldLedger.ProofContracts.«po_b1_dispatch/2» s key requires
      """
    )
  end
end
