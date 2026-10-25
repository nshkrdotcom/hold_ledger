module

public import Elixir.HoldLedger.ProofContracts
public import HoldLedgerProof.Induction
public import HoldLedgerProof.CorePreservation
public import HoldLedgerProof.CoreStructure

public section
set_option maxHeartbeats 16000000
namespace Elixir.HoldLedger.ProofContracts

theorem «l2_identity/3» (entries key to : Lynx.Term)
    (requires : «l2_identity:requires/3» entries key to = Except.ok Lynx.Term.true) :
    «l2_identity:ensures/3» entries key to = Except.ok Lynx.Term.true := by
  have replaced := HoldLedgerProof.replaced_2
  have identities := HoldLedgerProof.identities_1
  simp only [«l2_identity:requires/3», bind, Except.bind] at requires
  all_goals repeat' (split at requires <;> try simp_all [Lynx.Term.true, Lynx.Term.false])
  all_goals simp only [Elixir.HoldLedger.Spec.«unique_keys?/1»,
    Lynx.Except.guard, Lynx.Except.tryWith, bind, Except.bind] at *
  all_goals repeat' (split at * <;> try simp_all [Lynx.Term.true, Lynx.Term.false])
  all_goals obtain ⟨out, hm, hu⟩ := replaced entries key to Lynx.Term.nil (by assumption)
  all_goals have hid : Elixir.HoldLedger.Spec.«identities_present?/2» entries out = Except.ok Lynx.Term.true :=
    identities entries Lynx.Term.nil out (by assumption) (by
      intro q a old _ hl
      exact hu q a old hl)
  all_goals simp [«l2_identity:ensures/3», hm,
    Elixir.HoldLedger.Spec.«identity_preserved?/2», hid, bind, Except.bind]

theorem «l4_structure/3» (entries key status : Lynx.Term)
    (requires : «l4_structure:requires/3» entries key status = Except.ok Lynx.Term.true) :
    «l4_structure:ensures/3» entries key status = Except.ok Lynx.Term.true := by
  have structural := HoldLedgerProof.structural_1
  simp only [«l4_structure:requires/3», bind, Except.bind] at requires
  all_goals repeat' (split at requires <;> try simp_all [Lynx.Term.true, Lynx.Term.false])
  all_goals repeat' (split at * <;> try simp_all [Lynx.Term.true, Lynx.Term.false])
  all_goals obtain ⟨out, hm, hp, hl, hu⟩ := structural entries key status (by assumption) (by assumption)
  all_goals simp_all [«l4_structure:ensures/3», Elixir.HoldLedger.Spec.«unique_keys?/1»,
    Lynx.Except.guard, Lynx.Except.tryWith, bind, Except.bind]
  all_goals repeat' (split at * <;> try simp_all [Lynx.Term.true, Lynx.Term.false])

end Elixir.HoldLedger.ProofContracts
