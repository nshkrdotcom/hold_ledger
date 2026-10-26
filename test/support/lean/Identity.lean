module

public import Elixir.HoldLedger.ProofContracts
public import HoldLedgerProof.Induction
public import HoldLedgerProof.CoreLookup
public import HoldLedgerProof.CorePreservation

public section
set_option maxHeartbeats 16000000
namespace Elixir.HoldLedger.ProofContracts

theorem «po_b6/2» (s event : Lynx.Term)
    (requires : «po_b6:requires/2» s event = Except.ok Lynx.Term.true) :
    «po_b6:ensures/2» s event = Except.ok Lynx.Term.true := by
  have replaced := HoldLedgerProof.replaced_2
  have identities := HoldLedgerProof.identities_1
  have marked := HoldLedgerProof.marked_2
  have integer_key := HoldLedgerProof.integer_key_1
  have compatible := HoldLedgerProof.compatible_1
  have fresh := HoldLedgerProof.fresh_3
  have lookup_shape := HoldLedgerProof.lookup_shape_1
  have shaped : ∃ (al hl ua uh : Int) (es : Lynx.Term),
      s = Lynx.Term.tuple #[Lynx.Term.integer al, Lynx.Term.integer hl,
        Lynx.Term.integer ua, Lynx.Term.integer uh, es] ∧
      Elixir.HoldLedger.Spec.«proper_entries?/1» es = Except.ok Lynx.Term.true ∧
      Elixir.HoldLedger.Spec.«unique_keys_seen?/2» es Lynx.Term.nil = Except.ok Lynx.Term.true := by
    clear replaced identities marked integer_key compatible fresh lookup_shape
    simp only [«po_b6:requires/2», Elixir.HoldLedger.Spec.«valid?/1», Elixir.HoldLedger.Spec.«nonnegative_state_valid?/5»,
      Lynx.Except.guard, Lynx.Except.tryWith, bind, Except.bind] at requires
    all_goals repeat' (split at requires <;> try simp_all [Lynx.Term.true])
    all_goals repeat' (split at * <;> try simp_all [])
    all_goals simp only [Erlang.erlang.«is_integer/1», Elixir.HoldLedger.Spec.«unique_keys?/1»,
      Lynx.Except.guard, Lynx.Except.tryWith, bind, Except.bind] at *
    all_goals repeat' (split at * <;> try simp_all [Lynx.Term.true, Lynx.Term.false])
    all_goals exact ⟨_, _, _, _, _, by exact ⟨rfl, rfl, rfl, rfl, rfl⟩, by assumption, by assumption⟩
  obtain ⟨al, hl, ua, uh, es, rfl, hp, hu⟩ := shaped
  have same : Elixir.HoldLedger.Spec.«identities_present?/2» es es = Except.ok Lynx.Term.true :=
    identities es Lynx.Term.nil es hu (by intro q a old _ h; exact ⟨old,h⟩)
  have changing : ∀ k st, ∃ out,
      Elixir.HoldLedger.Ledger.«set_status/3» es k st = Except.ok out ∧
      Elixir.HoldLedger.Spec.«identities_present?/2» es out = Except.ok Lynx.Term.true := by
    intro k st
    obtain ⟨out, hm, hi⟩ := replaced es k st Lynx.Term.nil hu
    exact ⟨out, hm, identities es Lynx.Term.nil out hu (by intro q a old _ h; exact hi q a old h)⟩
  obtain ⟨restarted, hr, hri⟩ := marked es Lynx.Term.nil hu
  have restart_ids : Elixir.HoldLedger.Spec.«identities_present?/2» es restarted = Except.ok Lynx.Term.true :=
    identities es Lynx.Term.nil restarted hu (by intro q a old _ h; exact hri q a old h)
  have find_eq : ∀ k, Elixir.HoldLedger.Ledger.«find/2» es k = Elixir.HoldLedger.Spec.«lookup/2» es k := by
    intro k
    obtain ⟨v, hf, hl⟩ := compatible es k hp
    exact hf.trans hl.symm
  let changed (k st : Lynx.Term) := Classical.choose (changing k st)
  have change_eq (k st : Lynx.Term) : Elixir.HoldLedger.Ledger.«set_status/3» es k st = Except.ok (changed k st) :=
    (Classical.choose_spec (changing k st)).1
  have change_ids (k st : Lynx.Term) : Elixir.HoldLedger.Spec.«identities_present?/2» es (changed k st) = Except.ok Lynx.Term.true :=
    (Classical.choose_spec (changing k st)).2
  clear requires replaced identities marked integer_key compatible hri
  simp only [«po_b6:ensures/2», Elixir.HoldLedger.Ledger.«step/2»]
  split
  case h_1 ev k amount =>
    cases k <;> simp [Elixir.HoldLedger.Ledger.«request/3», Erlang.erlang.«is_integer/1»,
      Elixir.HoldLedger.Spec.«identity_preserved?/2», same, Erlang.erlang.«element/2»,
      Lynx.Except.guard, Lynx.Except.tryWith, bind, Except.bind,
      Lynx.Term.true, Lynx.Term.false]
    all_goals cases amount <;> simp [
       same,

      Lynx.Term.true]
    rename_i n amountn
    rcases lookup_shape es (Lynx.Term.integer n) hp with hn | ⟨ek, av, st, hlookup, hst⟩
    all_goals try have hid := fresh es n (Lynx.Term.integer amountn) hu (by assumption)
    all_goals simp_all [ Erlang.erlang.«>/2», Ordering.isGT_iff_eq_gt, Int.compare_eq_gt, Erlang.erlang.«=:=/2»,

      Lynx.Term.true, Lynx.Term.false]
    all_goals repeat' (split at * <;> (repeat' split_conjunction) <;> subst_vars <;> try simp_all [])
    all_goals try exact fresh es n (Lynx.Term.integer amountn) hu (by assumption)
    all_goals repeat' split_conjunction
    all_goals subst_vars
    all_goals try simp_all []
    all_goals try solve_by_elim (maxDepth := 20)
    all_goals try grind only [change_ids]
  case h_2 ev k =>
    rcases lookup_shape es k hp with hn | ⟨ek, av, st, hlookup, hst⟩
    all_goals simp only [Elixir.HoldLedger.Ledger.«dispatch/2»]
    all_goals try simp_all [
      Elixir.HoldLedger.Spec.«identity_preserved?/2»,
      Erlang.erlang.«element/2»,

        bind, Except.bind,
      Lynx.Term.true]
    all_goals repeat' (split at * <;> (repeat' split_conjunction) <;> subst_vars <;> try simp_all [])
    all_goals repeat' split_conjunction
    all_goals subst_vars
    all_goals try simp_all []
    all_goals try solve_by_elim (maxDepth := 20)
    all_goals try grind only [change_ids]
  case h_3 ev k =>
    rcases lookup_shape es k hp with hn | ⟨ek, av, st, hlookup, hst⟩
    all_goals simp only [Elixir.HoldLedger.Ledger.«timeout/2»]
    all_goals try simp_all [
      Elixir.HoldLedger.Spec.«identity_preserved?/2»,
      Erlang.erlang.«element/2»,

        bind, Except.bind,
      Lynx.Term.true]
    all_goals repeat' (split at * <;> (repeat' split_conjunction) <;> subst_vars <;> try simp_all [])
    all_goals repeat' split_conjunction
    all_goals subst_vars
    all_goals try simp_all []
    all_goals try solve_by_elim (maxDepth := 20)
    all_goals try grind only [change_ids]
  case h_5 ev k =>
    rcases lookup_shape es k hp with hn | ⟨ek, av, st, hlookup, hst⟩
    all_goals simp only [Elixir.HoldLedger.Ledger.«retry/2»]
    all_goals try simp_all [
      Elixir.HoldLedger.Spec.«identity_preserved?/2»,
      Erlang.erlang.«element/2»,

        bind, Except.bind,
      Lynx.Term.true]
    all_goals repeat' (split at * <;> (repeat' split_conjunction) <;> subst_vars <;> try simp_all [])
    all_goals repeat' split_conjunction
    all_goals subst_vars
    all_goals try simp_all []
    all_goals try solve_by_elim (maxDepth := 20)
    all_goals try grind only [change_ids]
  case h_6 ev k outcome =>
    rcases lookup_shape es k hp with hn | ⟨ek, av, st, hlookup, hst⟩
    all_goals simp only [Elixir.HoldLedger.Ledger.«processor_result/3»]
    all_goals try simp_all [
      Elixir.HoldLedger.Spec.«identity_preserved?/2»,
      Erlang.erlang.«element/2», Erlang.erlang.«is_integer/1»,

      Lynx.Except.guard, Lynx.Except.tryWith, bind, Except.bind,
      Lynx.Term.true, Lynx.Term.false]
    all_goals repeat' (split at * <;> (repeat' split_conjunction) <;> subst_vars <;> try simp_all [])
    all_goals repeat' split_conjunction
    all_goals subst_vars
    all_goals try simp_all []
    all_goals try solve_by_elim (maxDepth := 20)
    all_goals try grind only [change_ids]
  case h_7 ev k =>
    rcases lookup_shape es k hp with hn | ⟨ek, av, st, hlookup, hst⟩
    all_goals simp only [Elixir.HoldLedger.Ledger.«void/2»]
    all_goals try simp_all [
      Elixir.HoldLedger.Spec.«identity_preserved?/2»,
      Erlang.erlang.«element/2»,

        bind, Except.bind,
      Lynx.Term.true]
    all_goals repeat' (split at * <;> (repeat' split_conjunction) <;> subst_vars <;> try simp_all [])
    all_goals repeat' split_conjunction
    all_goals subst_vars
    all_goals try simp_all []
    all_goals try solve_by_elim (maxDepth := 20)
    all_goals try grind only [change_ids]
  case h_8 ev k =>
    rcases lookup_shape es k hp with hn | ⟨ek, av, st, hlookup, hst⟩
    all_goals simp only [Elixir.HoldLedger.Ledger.«void_confirmed/2»]
    all_goals try simp_all [
      Elixir.HoldLedger.Spec.«identity_preserved?/2»,
      Erlang.erlang.«element/2»,

        bind, Except.bind,
      Lynx.Term.true]
    all_goals repeat' (split at * <;> (repeat' split_conjunction) <;> subst_vars <;> try simp_all [])
    all_goals repeat' split_conjunction
    all_goals subst_vars
    all_goals try simp_all []
    all_goals try solve_by_elim (maxDepth := 20)
    all_goals try grind only [change_ids]
  case h_4 =>
    simp [Elixir.HoldLedger.Ledger.«restart/1», hr, restart_ids,
      Elixir.HoldLedger.Spec.«identity_preserved?/2», Erlang.erlang.«element/2»]
    all_goals repeat' split_conjunction
    all_goals subst_vars
    all_goals try simp_all [change_ids, Elixir.HoldLedger.Spec.«identity_preserved?/2», same, Erlang.erlang.«element/2», bind, Except.bind, Lynx.Term.true, Lynx.Term.false]
    all_goals try solve_by_elim (maxDepth := 20)
    all_goals try grind only [change_ids]
  case h_9 ev k =>
    cases k <;> simp [Elixir.HoldLedger.Ledger.«transport_ack/2»,
      Elixir.HoldLedger.Spec.«identity_preserved?/2», same,
      Erlang.erlang.«element/2»]
    all_goals repeat' split_conjunction
    all_goals subst_vars
    all_goals try simp_all [change_ids, Elixir.HoldLedger.Spec.«identity_preserved?/2», same, Erlang.erlang.«element/2», bind, Except.bind, Lynx.Term.true, Lynx.Term.false]
    all_goals try solve_by_elim (maxDepth := 20)
    all_goals try grind only [change_ids]
  case h_10 =>
    simp [Elixir.HoldLedger.Spec.«identity_preserved?/2», same,
      Erlang.erlang.«element/2»]

theorem «po_b7/1» (s : Lynx.Term)
    (requires : «po_b7:requires/1» s = Except.ok Lynx.Term.true) :
    «po_b7:ensures/1» s = Except.ok Lynx.Term.true := by
  have clearing := HoldLedgerProof.clearing_1
  have shaped : ∃ al hl ua uh es, s = Lynx.Term.tuple #[al, hl, ua, uh, es] ∧
      Elixir.HoldLedger.Spec.«proper_entries?/1» es = Except.ok Lynx.Term.true := by
    simp only [«po_b7:requires/1», Elixir.HoldLedger.Spec.«valid?/1», Elixir.HoldLedger.Spec.«nonnegative_state_valid?/5»,
      Lynx.Except.guard, Lynx.Except.tryWith, bind, Except.bind] at requires
    all_goals repeat' (split at requires <;> try simp_all [Lynx.Term.true])
    all_goals repeat' (split at * <;> try simp_all [])
    all_goals exact ⟨_, _, _, _, _, by exact ⟨rfl, rfl, rfl, rfl, rfl⟩, by assumption⟩
  obtain ⟨al, hl, ua, uh, es, rfl, hp⟩ := shaped
  obtain ⟨out, hm, hn⟩ := clearing es hp
  all_goals simp_all [«po_b7:ensures/1», Elixir.HoldLedger.Ledger.«step/2»,
    Elixir.HoldLedger.Ledger.«restart/1», Erlang.erlang.«element/2»,
    Erlang.erlang.«==/2», Lynx.Term.true]

end Elixir.HoldLedger.ProofContracts
