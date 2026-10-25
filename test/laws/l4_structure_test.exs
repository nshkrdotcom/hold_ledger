defmodule HoldLedger.Laws.L4StructureTest do
  use ExUnit.Case
  use HoldLedger.ProofCase

  alias HoldLedger.{Ledger, Spec}

  # L4 (L): replacement by known status retains a well-formed unique list.
  # Witness: test/hold_ledger_transition_test.exs.
  # Proof scope and commands: guides/verification.md.
  laws "l4_structure" do
    law(l4_structure(entries, key, status),
      requires:
        Spec.proper_entries?(entries) and Spec.unique_keys?(entries) and
          Spec.has_key?(entries, key) and Spec.known_status?(status),
      expects:
        Spec.proper_entries?(Ledger.set_status(entries, key, status)) and
          Spec.unique_keys?(Ledger.set_status(entries, key, status)),
      proof: ~LEAN"""
      exact Elixir.HoldLedger.ProofContracts.«l4_structure/3» entries key status requires
      """
    )
  end
end
