defmodule HoldLedger.Laws.PoA2Test do
  use ExUnit.Case
  use HoldLedger.ProofCase

  alias HoldLedger.{Ledger, Spec}

  # PO-A2 (P0): obligatory positive admission including exact fit and exact counters.
  # Witness: test/hold_ledger_witness_test.exs.
  # Proof scope and commands: guides/verification.md.
  laws "po_a2", options: [maxHeartbeats: 4_000_000] do
    law(po_a2(s, key, amount),
      requires: Spec.request_eligible?(s, key, amount),
      expects:
        Ledger.request(s, key, amount) ==
          {{elem(s, 0), elem(s, 1), elem(s, 2) + amount, elem(s, 3) + 1,
            [{key, amount, :reserved} | elem(s, 4)]}, :admitted, []} and
          Ledger.request(s, key, amount) == Spec.expected_step(s, {:request, key, amount}),
      proof: ~LEAN"""
      exact Elixir.HoldLedger.ProofContracts.«po_a2/3» s key amount requires
      """
    )
  end
end
