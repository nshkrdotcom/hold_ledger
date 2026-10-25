defmodule HoldLedger.Laws.PoC2Test do
  use ExUnit.Case
  use HoldLedger.ProofCase

  @moduletag timeout: 600_000

  alias HoldLedger.{Ledger, Spec}

  # PO-C2 (P0): validity of every modeled journal prefix from initial limits.
  # Witness: test/hold_ledger_witness_test.exs.
  # Proof scope and commands: guides/verification.md.
  laws "po_c2", options: [maxHeartbeats: 14_000_000] do
    law(po_c2(amount_limit, hold_limit, events),
      requires:
        is_integer(amount_limit) and amount_limit >= 0 and is_integer(hold_limit) and
          hold_limit >= 0 and Spec.proper_events?(events),
      expects: Spec.valid?(Ledger.run(Ledger.init(amount_limit, hold_limit), events)),
      proof: ~LEAN"""
      exact Elixir.HoldLedger.ProofContracts.«po_c2/3» amount_limit hold_limit events requires
      """
    )
  end
end
