defmodule HoldLedger.Laws.PoITest do
  use ExUnit.Case
  use HoldLedger.ProofCase

  alias HoldLedger.{Ledger, Spec}

  # PO-I (P0): valid init at every nonnegative pair including zero.
  # Witness: test/hold_ledger_witness_test.exs.
  # Proof scope and commands: guides/verification.md.
  laws "po_i" do
    law(po_i(amount_limit, hold_limit),
      requires:
        is_integer(amount_limit) and amount_limit >= 0 and is_integer(hold_limit) and
          hold_limit >= 0,
      expects: Spec.valid?(Ledger.init(amount_limit, hold_limit)),
      proof: ~LEAN"""
      exact Elixir.HoldLedger.ProofContracts.«po_i/2» amount_limit hold_limit requires
      """
    )
  end
end
