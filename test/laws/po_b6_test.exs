defmodule HoldLedger.Laws.PoB6Test do
  use ExUnit.Case
  use HoldLedger.ProofCase

  @moduletag timeout: 180_000

  alias HoldLedger.{Ledger, Spec}

  # PO-B6 (P1): all previously seen identities and amounts remain recorded.
  # Witness: test/hold_ledger_witness_test.exs.
  # Proof scope and commands: guides/verification.md.
  laws "po_b6", options: [maxHeartbeats: 1_500_000] do
    law(po_b6(s, event),
      requires: Spec.valid?(s),
      expects: Spec.identity_preserved?(s, elem(Ledger.step(s, event), 0)),
      proof: ~LEAN"""
      exact Elixir.HoldLedger.ProofContracts.«po_b6/2» s event requires
      """
    )
  end
end
