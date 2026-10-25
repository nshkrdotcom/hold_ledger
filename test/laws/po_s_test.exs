defmodule HoldLedger.Laws.PoSTest do
  use ExUnit.Case
  use HoldLedger.ProofCase

  @moduletag timeout: 600_000

  alias HoldLedger.{Ledger, Spec}

  # PO-S (P0): one arbitrary event preserves valid state.
  # Witness: test/hold_ledger_witness_test.exs.
  # Proof scope and commands: guides/verification.md.
  laws "po_s", options: [maxHeartbeats: 12_000_000] do
    law(po_s(s, event),
      requires: Spec.valid?(s),
      expects: Spec.valid?(elem(Ledger.step(s, event), 0)),
      proof: ~LEAN"""
      exact Elixir.HoldLedger.ProofContracts.«po_s/2» s event requires
      """
    )
  end
end
