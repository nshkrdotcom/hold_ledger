defmodule HoldLedger.Laws.PoB1ProcessorResultTest do
  use ExUnit.Case
  use HoldLedger.ProofCase

  alias HoldLedger.{Ledger, Spec}

  # PO-B1/processor_result (P0): processor_result preserves validity for all valid states and arbitrary arguments.
  # Witness: test/hold_ledger_witness_test.exs.
  # Proof scope and commands: guides/verification.md.
  laws "po_b1_processor_result", options: [maxHeartbeats: 2_000_000] do
    law(po_b1_processor_result(s, key, outcome),
      requires: Spec.valid?(s),
      expects: Spec.valid?(elem(Ledger.processor_result(s, key, outcome), 0)),
      proof: ~LEAN"""
      exact Elixir.HoldLedger.ProofContracts.«po_b1_processor_result/3» s key outcome requires
      """
    )
  end
end
