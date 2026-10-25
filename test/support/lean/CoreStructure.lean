module

public import Elixir.HoldLedger.ProofContracts
public import HoldLedgerProof.Induction

public section
set_option maxHeartbeats 16000000

theorem HoldLedgerProof.seen_append_1 : ∀ xs k j, ¬ Lynx.Term.compare k j = Ordering.eq →
    Elixir.HoldLedger.Spec.«seen?/2» (Lynx.Term.list (xs ++ [k])) j =
    Elixir.HoldLedger.Spec.«seen?/2» (Lynx.Term.list xs) j := by
  intro xs k j hn
  induction xs with
  | nil => simp [Lynx.Term.list, Elixir.HoldLedger.Spec.«seen?/2», Erlang.erlang.«==/2», hn]
  | cons x xs ih =>
    simp [Lynx.Term.list, Elixir.HoldLedger.Spec.«seen?/2», Erlang.erlang.«==/2»]
    split <;> simp_all

theorem HoldLedgerProof.fresh_1 : ∀ es seen k,
    Elixir.HoldLedger.Spec.«proper_entries?/1» es = Except.ok Lynx.Term.true →
    Elixir.HoldLedger.Spec.«unique_keys_seen?/2» es (Lynx.Term.list seen) = Except.ok Lynx.Term.true →
    Elixir.HoldLedger.Spec.«lookup/2» es k = Except.ok (Lynx.Term.atom "not_found") →
    Elixir.HoldLedger.Spec.«unique_keys_seen?/2» es (Lynx.Term.list (seen ++ [k])) = Except.ok Lynx.Term.true := by
  intro es seen k hp hu hn
  fun_induction Elixir.HoldLedger.Spec.«lookup/2» es k generalizing seen
  all_goals try (rename_i ek av st rest ih; have recur := ih (ek :: seen))
  all_goals simp only [Elixir.HoldLedger.Spec.«proper_entries?/1»,
    Lynx.Except.guard, Lynx.Except.tryWith, bind, Except.bind] at hp
  all_goals repeat' (split at hp <;> try simp_all [Lynx.Term.true, Lynx.Term.false])
  all_goals simp_all [Elixir.HoldLedger.Spec.«unique_keys_seen?/2»,
    Elixir.HoldLedger.Spec.«lookup/2», Erlang.erlang.«is_integer/1»,
    Erlang.erlang.«==/2», Lynx.Term.true, Lynx.Term.false]
  all_goals repeat' (split at * <;> try simp_all [Lynx.Term.true, Lynx.Term.false])
  all_goals simp_all [Elixir.HoldLedger.Spec.«unique_keys_seen?/2», bind, Except.bind]
  all_goals have cmp_reverse (a b : Lynx.Term) :
      a.compare b = Ordering.eq ↔ b.compare a = Ordering.eq :=
    ⟨Std.OrientedCmp.eq_symm, Std.OrientedCmp.eq_symm⟩
  all_goals simp_all [HoldLedgerProof.seen_append_1, cmp_reverse,
    Elixir.HoldLedger.Spec.«unique_keys_seen?/2», bind, Except.bind]
  all_goals repeat' (split at * <;> try simp_all [HoldLedgerProof.seen_append_1, cmp_reverse,
    Lynx.Term.true, Lynx.Term.false])

theorem HoldLedgerProof.structural_1 : ∀ es k st,
    Elixir.HoldLedger.Spec.«proper_entries?/1» es = Except.ok Lynx.Term.true →
    Elixir.HoldLedger.Spec.«known_status?/1» st = Except.ok Lynx.Term.true →
    ∃ out, Elixir.HoldLedger.Ledger.«set_status/3» es k st = Except.ok out ∧
      Elixir.HoldLedger.Spec.«proper_entries?/1» out = Except.ok Lynx.Term.true ∧
      Erlang.erlang.«is_list/1» out = Except.ok Lynx.Term.true ∧
      ∀ seen, Elixir.HoldLedger.Spec.«unique_keys_seen?/2» out seen =
        Elixir.HoldLedger.Spec.«unique_keys_seen?/2» es seen := by
  intro es k st h hs
  fun_induction Elixir.HoldLedger.Ledger.«set_status/3» es k st
  all_goals simp only [Elixir.HoldLedger.Spec.«proper_entries?/1»,
    Lynx.Except.guard, Lynx.Except.tryWith, bind, Except.bind] at h
  all_goals repeat' (split at h <;> try simp_all [Lynx.Term.true, Lynx.Term.false])
  all_goals try simp_all [Elixir.HoldLedger.Ledger.«set_status/3»,
    Elixir.HoldLedger.Spec.«proper_entries?/1», Elixir.HoldLedger.Spec.«unique_keys_seen?/2»,
    Erlang.erlang.«is_list/1», Erlang.erlang.«is_integer/1»,
    Lynx.Term.true, Lynx.Term.false]
  all_goals repeat' (split at * <;> try simp_all [Lynx.Term.true, Lynx.Term.false])
  all_goals obtain ⟨out, hm, hp, hl, hu⟩ :=
    (by assumption : ∃ out : Lynx.Term, _ ∧ _ ∧ _ ∧
      ∀ seen : Lynx.Term, Elixir.HoldLedger.Spec.«unique_keys_seen?/2» out seen =
        Elixir.HoldLedger.Spec.«unique_keys_seen?/2» _ seen)
  all_goals simp_all [Elixir.HoldLedger.Ledger.«set_status/3»,
    Elixir.HoldLedger.Spec.«proper_entries?/1», Elixir.HoldLedger.Spec.«unique_keys_seen?/2»,
    Erlang.erlang.«is_list/1», Erlang.erlang.«is_integer/1», Erlang.erlang.«==/2»,
    Lynx.Except.guard, Lynx.Except.tryWith, bind, Except.bind,
    Lynx.Term.true, Lynx.Term.false]
  all_goals repeat' (split <;> try simp_all [Elixir.HoldLedger.Spec.«proper_entries?/1»,
    Elixir.HoldLedger.Spec.«unique_keys_seen?/2», Erlang.erlang.«is_integer/1»,
    Lynx.Term.true, Lynx.Term.false])

  all_goals exact fun _ => rfl

theorem HoldLedgerProof.restarted_structure_1 : ∀ es,
    Elixir.HoldLedger.Spec.«proper_entries?/1» es = Except.ok Lynx.Term.true →
    ∃ out, Elixir.HoldLedger.Ledger.«mark_unknown/1» es = Except.ok out ∧
      Elixir.HoldLedger.Spec.«proper_entries?/1» out = Except.ok Lynx.Term.true ∧
      Erlang.erlang.«is_list/1» out = Except.ok Lynx.Term.true ∧
      ∀ seen, Elixir.HoldLedger.Spec.«unique_keys_seen?/2» out seen =
        Elixir.HoldLedger.Spec.«unique_keys_seen?/2» es seen := by
  intro es h
  fun_induction Elixir.HoldLedger.Ledger.«mark_unknown/1» es
  all_goals simp only [Elixir.HoldLedger.Spec.«proper_entries?/1»,
    Lynx.Except.guard, Lynx.Except.tryWith, bind, Except.bind] at h
  all_goals repeat' (split at h <;> try simp_all [Lynx.Term.true, Lynx.Term.false])
  all_goals try simp_all [Elixir.HoldLedger.Ledger.«mark_unknown/1»,
    Elixir.HoldLedger.Spec.«proper_entries?/1», Elixir.HoldLedger.Spec.«unique_keys_seen?/2»,
    Erlang.erlang.«is_list/1», Erlang.erlang.«is_integer/1»,
    Elixir.HoldLedger.Spec.«known_status?/1», Elixir.HoldLedger.Spec.«holding?/1»,
    Elixir.HoldLedger.Spec.«terminal?/1», Lynx.Term.true, Lynx.Term.false]
  all_goals repeat' (split at * <;> try simp_all [Lynx.Term.true, Lynx.Term.false])
  all_goals obtain ⟨out, hm, hp, hl, hu⟩ :=
    (by assumption : ∃ out : Lynx.Term, _ ∧ _ ∧ _ ∧
      ∀ seen : Lynx.Term, Elixir.HoldLedger.Spec.«unique_keys_seen?/2» out seen =
        Elixir.HoldLedger.Spec.«unique_keys_seen?/2» _ seen)
  all_goals simp_all [Elixir.HoldLedger.Ledger.«mark_unknown/1»,
    Elixir.HoldLedger.Spec.«proper_entries?/1», Elixir.HoldLedger.Spec.«unique_keys_seen?/2»,
    Erlang.erlang.«is_list/1», Erlang.erlang.«is_integer/1»,
    Elixir.HoldLedger.Spec.«known_status?/1», Elixir.HoldLedger.Spec.«holding?/1»,
    Elixir.HoldLedger.Spec.«terminal?/1», Lynx.Term.true, Lynx.Term.false]
  all_goals repeat' (split <;> try simp_all [Lynx.Term.true, Lynx.Term.false])
  all_goals exact fun _ => rfl

theorem HoldLedgerProof.fresh_4 : ∀ es seen k,
    Elixir.HoldLedger.Spec.«proper_entries?/1» es = Except.ok Lynx.Term.true →
    Elixir.HoldLedger.Spec.«unique_keys_seen?/2» es (Lynx.Term.list seen) = Except.ok Lynx.Term.true →
    Elixir.HoldLedger.Ledger.«find/2» es k = Except.ok (Lynx.Term.atom "not_found") →
    Elixir.HoldLedger.Spec.«unique_keys_seen?/2» es (Lynx.Term.list (seen ++ [k])) = Except.ok Lynx.Term.true := by
  intro es seen k hp hu hn
  fun_induction Elixir.HoldLedger.Ledger.«find/2» es k generalizing seen
  all_goals try (rename_i ek av st rest ih; have recur := ih (ek :: seen))
  all_goals simp only [Elixir.HoldLedger.Spec.«proper_entries?/1»,
    Lynx.Except.guard, Lynx.Except.tryWith, bind, Except.bind] at hp
  all_goals repeat' (split at hp <;> try simp_all [Lynx.Term.true, Lynx.Term.false])
  all_goals simp_all [Elixir.HoldLedger.Spec.«unique_keys_seen?/2»,
    Elixir.HoldLedger.Ledger.«find/2», Erlang.erlang.«is_integer/1»,
    Erlang.erlang.«==/2», Lynx.Term.true, Lynx.Term.false]
  all_goals repeat' (split at * <;> try simp_all [Lynx.Term.true, Lynx.Term.false])
  all_goals simp_all [Elixir.HoldLedger.Spec.«unique_keys_seen?/2», bind, Except.bind]
  all_goals have cmp_reverse (a b : Lynx.Term) :
      a.compare b = Ordering.eq ↔ b.compare a = Ordering.eq :=
    ⟨Std.OrientedCmp.eq_symm, Std.OrientedCmp.eq_symm⟩
  all_goals simp_all [HoldLedgerProof.seen_append_1, cmp_reverse,
    Elixir.HoldLedger.Spec.«unique_keys_seen?/2», bind, Except.bind]
  all_goals repeat' (split at * <;> try simp_all [HoldLedgerProof.seen_append_1, cmp_reverse,
    Lynx.Term.true, Lynx.Term.false])

theorem HoldLedgerProof.insert_unique_1 : ∀ es (k : Int) amount,
    Elixir.HoldLedger.Spec.«proper_entries?/1» es = Except.ok Lynx.Term.true →
    Elixir.HoldLedger.Spec.«unique_keys?/1» es = Except.ok Lynx.Term.true →
    Elixir.HoldLedger.Ledger.«find/2» es (Lynx.Term.integer k) = Except.ok (Lynx.Term.atom "not_found") →
    Elixir.HoldLedger.Spec.«unique_keys?/1» (Lynx.Term.cons
      (Lynx.Term.tuple #[Lynx.Term.integer k, amount, Lynx.Term.atom "reserved"]) es) = Except.ok Lynx.Term.true := by
  intro es k amount hp hu hn
  simp only [Elixir.HoldLedger.Spec.«unique_keys?/1»,
    Lynx.Except.guard, Lynx.Except.tryWith, bind, Except.bind] at hu
  all_goals repeat' (split at hu <;> try simp_all [Lynx.Term.true, Lynx.Term.false])
  all_goals
    have hnew := HoldLedgerProof.fresh_4 es [] (Lynx.Term.integer k) hp
      (by simpa [Lynx.Term.list] using hu) hn
    simpa [Elixir.HoldLedger.Spec.«unique_keys?/1», Elixir.HoldLedger.Spec.«unique_keys_seen?/2»,
      Elixir.HoldLedger.Spec.«seen?/2», Erlang.erlang.«is_list/1», Lynx.Term.list] using hnew
