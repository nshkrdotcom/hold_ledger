defmodule HoldLedger.Laws.PoB4Test do
  use ExUnit.Case
  use HoldLedger.ProofCase

  @moduletag timeout: 180_000

  alias HoldLedger.{Ledger, Spec}

  # PO-B4 (P1): no first authorization without approved result for that key.
  # Witness: test/mutations/preflight_test.exs.
  # Proof scope and commands: guides/verification.md.
  laws "po_b4", options: [maxHeartbeats: 1_500_000] do
    law(po_b4(s, event),
      requires: Spec.valid?(s),
      expects: Spec.authorized_only_on_result?(s, event, elem(Ledger.step(s, event), 0)),
      proof: ~LEAN"""
      exact Elixir.HoldLedger.ProofContracts.«po_b4/2» s event requires
      """
    )
  end
end
