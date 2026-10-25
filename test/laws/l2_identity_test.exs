defmodule HoldLedger.Laws.L2IdentityTest do
  use ExUnit.Case
  use HoldLedger.ProofCase

  alias HoldLedger.{Ledger, Spec}

  # L2 (L): status replacement retains all existing key/amount identities.
  # Witness: test/hold_ledger_transition_test.exs.
  # Proof scope and commands: guides/verification.md.
  laws "l2_identity" do
    law(l2_identity(entries, key, to),
      requires:
        Spec.proper_entries?(entries) and Spec.unique_keys?(entries) and
          Spec.has_key?(entries, key) and Spec.known_status?(to),
      expects:
        Spec.identity_preserved?(
          {0, 0, 0, 0, entries},
          {0, 0, 0, 0, Ledger.set_status(entries, key, to)}
        ),
      proof: ~LEAN"""
      exact Elixir.HoldLedger.ProofContracts.«l2_identity/3» entries key to requires
      """
    )
  end
end
