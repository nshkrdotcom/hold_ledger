module

public import Erlang.postlude

public section
namespace Elixir.HoldLedger.ProofContracts

-- Original pre-migration theorem and proof, checked against the current translation.
theorem «l1_find/2» (entries key : Lynx.Term)
    (requires : «l1_find:requires/2» entries key = Except.ok Lynx.Term.true) :
    «l1_find:ensures/2» entries key = Except.ok Lynx.Term.true := by
  have compatible := HoldLedgerProof.compatible_1
  unfold «l1_find:requires/2» at requires
  cases hp : Elixir.HoldLedger.Spec.«proper_entries?/1» entries <;>
    simp_all [Lynx.Term.true]
  all_goals repeat' (first | split_conjunction | split at requires <;> try simp_all [])
  all_goals obtain ⟨v, hf, hl⟩ := compatible entries key (by assumption)
  all_goals simp [«l1_find:ensures/2», hf, hl, Erlang.erlang.«==/2», Lynx.Term.true]

end Elixir.HoldLedger.ProofContracts

-- Elaboration checks identical theorem types; proof irrelevance closes equality.
example : @Elixir.HoldLedger.ProofContracts.«l1_find/2» =
    @HoldLedgerProof.Postludes.L1Find.l1_contract := by
  rfl
