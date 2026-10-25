defmodule HoldLedger.Laws.PoC3Test do
  use ExUnit.Case
  use HoldLedger.ProofCase

  alias HoldLedger.{Ledger, Spec}

  # PO-C3 (P1): finite histories retain terminal/identity and require independent approval evidence.
  # Witness: test/hold_ledger_witness_test.exs.
  # Proof scope and commands: guides/verification.md.
  laws "po_c3" do
    law(po_c3(s, events),
      requires: Spec.valid?(s) and Spec.proper_events?(events),
      expects:
        Ledger.run(s, events) == Spec.expected_run(s, events) and
          Spec.identity_preserved?(s, Ledger.run(s, events)) and
          Spec.terminal_preserved?(s, Ledger.run(s, events)) and
          Spec.history_authorizations_explained?(s, events),
      proof: ~LEAN"""
      exact Elixir.HoldLedger.ProofContracts.«po_c3/2» s events requires
      """
    )
  end
end
