defmodule HoldLedger.Laws.PoC1Test do
  use ExUnit.Case
  use HoldLedger.ProofCase

  @moduletag timeout: 600_000

  alias HoldLedger.{Ledger, Spec}

  # PO-C1 (P0): induct over every proper finite list of arbitrary event terms.
  # Witness: test/hold_ledger_witness_test.exs.
  # Proof scope and commands: guides/verification.md.
  laws "po_c1", options: [maxHeartbeats: 14_000_000] do
    law(po_c1(s, events),
      requires: Spec.valid?(s) and Spec.proper_events?(events),
      expects: Spec.valid?(Ledger.run(s, events)),
      proof: ~LEAN"""
      exact Elixir.HoldLedger.ProofContracts.«po_c1/2» s events requires
      """
    )
  end
end
