defmodule HoldLedger.Laws.L1FindTest do
  use ExUnit.Case
  use HoldLedger.ProofCase

  alias HoldLedger.{Ledger, Spec}

  # L1 (L): proper unique list lookup compatibility.
  # Witness: test/hold_ledger_transition_test.exs.
  # Proof scope and commands: guides/verification.md.
  laws "l1_find" do
    law(l1_find(entries, key),
      requires: Spec.proper_entries?(entries) and Spec.unique_keys?(entries),
      expects: Ledger.find(entries, key) == Spec.lookup(entries, key),
      proof: ~LEAN"""
      exact Elixir.HoldLedger.ProofContracts.«l1_find/2» entries key requires
      """
    )
  end
end
