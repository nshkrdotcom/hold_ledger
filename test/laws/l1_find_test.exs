defmodule HoldLedger.Laws.L1FindTest do
  use ExUnit.Case
  use HoldLedger.ProofCase

  alias HoldLedger.{Ledger, Spec}

  # L1 (L): proper unique list lookup compatibility.
  # Witness: test/hold_ledger_transition_test.exs.
  # Proof scope and commands: guides/verification.md.
  laws "l1_find" do
    # Opt-in postlude smoke check: refers to the actual translated find/2.
    # This does not replace or weaken the original L1 theorem.
    postlude(~LEAN"""
    namespace HoldLedgerProof.Postludes.L1Find

    theorem translated_find_reflexive (entries key : Lynx.Term) :
        Elixir.HoldLedger.Ledger.«find/2» entries key =
          Elixir.HoldLedger.Ledger.«find/2» entries key := by
      rfl

    -- Also force resolution of a custom shared-support theorem. This only
    -- elaborates when our postlude imports the HoldLedgerProof.* support graph.
    theorem shared_lookup_lemma_resolves :
        @HoldLedgerProof.compatible_1 = @HoldLedgerProof.compatible_1 := by
      rfl

    -- The original L1 contract proof moved from shared Lookup.lean into this
    -- group-local postlude; the theorem type and original requires/expects stay
    -- unchanged. Other groups still import Lookup for their separate theorems.
    theorem l1_contract (entries key : Lynx.Term)
        (requires : Elixir.HoldLedger.ProofContracts.«l1_find:requires/2» entries key =
          Except.ok Lynx.Term.true) :
        Elixir.HoldLedger.ProofContracts.«l1_find:ensures/2» entries key =
          Except.ok Lynx.Term.true := by
      have compatible := HoldLedgerProof.compatible_1
      unfold Elixir.HoldLedger.ProofContracts.«l1_find:requires/2» at requires
      cases hp : Elixir.HoldLedger.Spec.«proper_entries?/1» entries <;>
        simp_all [Lynx.Term.true]
      all_goals repeat' (first | split_conjunction | split at requires <;> try simp_all [])
      all_goals obtain ⟨v, hf, hl⟩ := compatible entries key (by assumption)
      all_goals simp [Elixir.HoldLedger.ProofContracts.«l1_find:ensures/2», hf, hl,
        Erlang.erlang.«==/2», Lynx.Term.true]

    end HoldLedgerProof.Postludes.L1Find
    """)

    law(l1_find(entries, key),
      requires: Spec.proper_entries?(entries) and Spec.unique_keys?(entries),
      expects: Ledger.find(entries, key) == Spec.lookup(entries, key),
      proof: ~LEAN"""
      exact HoldLedgerProof.Postludes.L1Find.l1_contract entries key requires
      """
    )
  end
end
