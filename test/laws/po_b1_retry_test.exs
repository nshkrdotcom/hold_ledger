defmodule HoldLedger.Laws.PoB1RetryValidityTest do
  use ExUnit.Case
  use HoldLedger.ProofCase

  alias HoldLedger.{Ledger, Spec}

  # PO-B1/retry (P0): retry preserves validity for all valid states and arbitrary arguments.
  # Witness: test/hold_ledger_witness_test.exs.
  # Proof scope and commands: guides/verification.md.
  laws "po_b1_retry", options: [maxHeartbeats: 2_000_000] do
    law(po_b1_retry(s, key),
      requires: Spec.valid?(s),
      expects: Spec.valid?(elem(Ledger.retry(s, key), 0)),
      proof: ~LEAN"""
      exact Elixir.HoldLedger.ProofContracts.«po_b1_retry/2» s key requires
      """
    )
  end
end
