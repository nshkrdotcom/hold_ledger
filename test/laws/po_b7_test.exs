defmodule HoldLedger.Laws.PoB7Test do
  use ExUnit.Case
  use HoldLedger.ProofCase

  alias HoldLedger.{Ledger, Spec}

  # PO-B7 (P1): restart removes all sent without reducing holding counters.
  # Witness: test/hold_ledger_witness_test.exs.
  # Proof scope and commands: guides/verification.md.
  laws "po_b7" do
    law(po_b7(s),
      requires: Spec.valid?(s),
      expects:
        Spec.no_sent?(elem(elem(Ledger.step(s, :restart), 0), 4)) and
          elem(elem(Ledger.step(s, :restart), 0), 2) == elem(s, 2) and
          elem(elem(Ledger.step(s, :restart), 0), 3) == elem(s, 3),
      proof: ~LEAN"""
      exact Elixir.HoldLedger.ProofContracts.«po_b7/1» s requires
      """
    )
  end
end
