module

public import Elixir.HoldLedger.ProofContracts
public import HoldLedgerProof.Induction
public import HoldLedgerProof.CoreLookup

public section
set_option maxHeartbeats 16000000
namespace Elixir.HoldLedger.ProofContracts

theorem «l1_find/2» (entries key : Lynx.Term)
    (requires : «l1_find:requires/2» entries key = Except.ok Lynx.Term.true) :
    «l1_find:ensures/2» entries key = Except.ok Lynx.Term.true := by
  have compatible := HoldLedgerProof.compatible_1
  unfold «l1_find:requires/2» at requires
  cases hp : Elixir.HoldLedger.Spec.«proper_entries?/1» entries <;>
    simp_all [Lynx.Term.true]
  all_goals repeat' (split at requires <;> try simp_all [])
  all_goals obtain ⟨v, hf, hl⟩ := compatible entries key (by assumption)
  all_goals simp [«l1_find:ensures/2», hf, hl, Erlang.erlang.«==/2», Lynx.Term.true]

theorem «po_a4_duplicate/4» (s key amount status : Lynx.Term)
    (requires : «po_a4_duplicate:requires/4» s key amount status = Except.ok Lynx.Term.true) :
    «po_a4_duplicate:ensures/4» s key amount status = Except.ok Lynx.Term.true := by
  have compatible := HoldLedgerProof.compatible_2
  have shaped : ∀ s, Elixir.HoldLedger.Spec.«valid?/1» s = Except.ok Lynx.Term.true →
      ∃ al hl ua uh es, s = Lynx.Term.tuple #[al, hl, ua, uh, es] ∧
        Elixir.HoldLedger.Spec.«proper_entries?/1» es = Except.ok Lynx.Term.true := by
    intro s h
    simp only [Elixir.HoldLedger.Spec.«valid?/1», Elixir.HoldLedger.Spec.«nonnegative_state_valid?/5»,
      Lynx.Except.guard, Lynx.Except.tryWith, bind, Except.bind] at h
    all_goals repeat' (split at h <;> try simp_all [Lynx.Term.true])
    all_goals repeat' (split at * <;> try simp_all [])
    all_goals exact ⟨_, _, _, _, _, by exact ⟨rfl, rfl, rfl, rfl, rfl⟩, by assumption⟩
  simp only [«po_a4_duplicate:requires/4», bind, Except.bind] at requires
  all_goals repeat' (split at requires <;> try simp_all [Lynx.Term.true])
  all_goals repeat' (split at * <;> try simp_all [])
  all_goals obtain ⟨al, hl, ua, uh, es, rfl, hp⟩ := shaped s (by assumption)
  all_goals obtain ⟨v, hf, hl, hs⟩ := compatible es key hp
  all_goals rcases hs with rfl | ⟨ek, n, st, rfl⟩
  all_goals simp_all [Erlang.erlang.«element/2», Erlang.erlang.«==/2»,
     Erlang.erlang.«is_integer/1», Erlang.erlang.«>/2»,
    Ordering.isGT_iff_eq_gt,
    Lynx.Term.compare_tuple, List.compareLex,  HoldLedgerProof.atom_tuple]
  all_goals repeat' (split at requires <;> try simp_all [])
  all_goals simp_all [«po_a4_duplicate:ensures/4», Elixir.HoldLedger.Ledger.«request/3»,
    Erlang.erlang.«==/2», Erlang.erlang.«=:=/2», Erlang.erlang.«is_integer/1»,
    Erlang.erlang.«>/2»,   bind, Except.bind,
    Lynx.Term.true, Lynx.Term.false]
  all_goals repeat' (split at * <;> try simp_all [])

theorem «po_a4_conflict/5» (s key amount original status : Lynx.Term)
    (requires : «po_a4_conflict:requires/5» s key amount original status = Except.ok Lynx.Term.true) :
    «po_a4_conflict:ensures/5» s key amount original status = Except.ok Lynx.Term.true := by
  have compatible := HoldLedgerProof.compatible_2
  have shaped : ∀ s, Elixir.HoldLedger.Spec.«valid?/1» s = Except.ok Lynx.Term.true →
      ∃ al hl ua uh es, s = Lynx.Term.tuple #[al, hl, ua, uh, es] ∧
        Elixir.HoldLedger.Spec.«proper_entries?/1» es = Except.ok Lynx.Term.true := by
    intro s h
    simp only [Elixir.HoldLedger.Spec.«valid?/1», Elixir.HoldLedger.Spec.«nonnegative_state_valid?/5»,
      Lynx.Except.guard, Lynx.Except.tryWith, bind, Except.bind] at h
    all_goals repeat' (split at h <;> try simp_all [Lynx.Term.true])
    all_goals repeat' (split at * <;> try simp_all [])
    all_goals exact ⟨_, _, _, _, _, by exact ⟨rfl, rfl, rfl, rfl, rfl⟩, by assumption⟩
  simp only [«po_a4_conflict:requires/5», bind, Except.bind] at requires
  all_goals repeat' (split at requires <;> try simp_all [Lynx.Term.true])
  all_goals repeat' (split at * <;> try simp_all [])
  all_goals obtain ⟨al, hl, ua, uh, es, rfl, hp⟩ := shaped s (by assumption)
  all_goals obtain ⟨v, hf, hl, hs⟩ := compatible es key hp
  all_goals rcases hs with rfl | ⟨ek, n, st, rfl⟩
  all_goals simp_all [Erlang.erlang.«element/2», Erlang.erlang.«==/2»,
    Erlang.erlang.«/=/2», Erlang.erlang.«is_integer/1», Erlang.erlang.«>/2»,
    Ordering.isGT_iff_eq_gt,
    Lynx.Term.compare_tuple, List.compareLex,  HoldLedgerProof.atom_tuple]
  all_goals repeat' (split at requires <;> try simp_all [])
  all_goals simp_all [«po_a4_conflict:ensures/5», Elixir.HoldLedger.Ledger.«request/3»,
    Erlang.erlang.«==/2», Erlang.erlang.«=:=/2», Erlang.erlang.«is_integer/1»,
    Erlang.erlang.«>/2»,   bind, Except.bind,
    Lynx.Term.true, Lynx.Term.false]
  all_goals repeat' (split at * <;> try simp_all [])

end Elixir.HoldLedger.ProofContracts
