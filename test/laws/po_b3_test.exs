defmodule HoldLedger.Laws.PoB3Test do
  use ExUnit.Case
  use HoldLedger.ProofCase

  @moduletag timeout: 600_000

  alias HoldLedger.{Ledger, Spec}

  # PO-B3 (P0): all authorize and void intents match stored identity; rejected emits no intents.
  # Witness: test/hold_ledger_witness_test.exs.
  # Proof scope and commands: guides/verification.md.
  laws "po_b3", options: [maxHeartbeats: 16_000_000] do
    law(po_b3(s, event),
      requires: Spec.valid?(s),
      expects:
        Spec.effects_valid?(
          s,
          event,
          elem(Ledger.step(s, event), 0),
          elem(Ledger.step(s, event), 1),
          elem(Ledger.step(s, event), 2)
        ),
      proof: ~LEAN"""
      exact Elixir.HoldLedger.ProofContracts.«po_b3/2» s event requires
      """
    )
  end
end
