defmodule HoldLedger.Laws.L6RestartTest do
  use ExUnit.Case
  use HoldLedger.ProofCase

  alias HoldLedger.{Ledger, Spec}

  # L6 (L): sent-to-unknown preserves both accounting totals.
  # Witness: test/hold_ledger_transition_test.exs.
  # Proof scope and commands: guides/verification.md.
  laws "l6_restart" do
    law(l6_restart(entries),
      requires: Spec.proper_entries?(entries) and Spec.unique_keys?(entries),
      expects:
        Spec.hold_amount(Ledger.mark_unknown(entries)) == Spec.hold_amount(entries) and
          Spec.hold_count(Ledger.mark_unknown(entries)) == Spec.hold_count(entries),
      proof: ~LEAN"""
      exact Elixir.HoldLedger.ProofContracts.«l6_restart/1» entries requires
      """
    )
  end
end
