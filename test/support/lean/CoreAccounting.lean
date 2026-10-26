module

public import Elixir.HoldLedger.ProofContracts
public import HoldLedgerProof.Induction

public section
set_option maxHeartbeats 16000000

@[expose] def HoldLedgerProof.held : Lynx.Term → Bool := fun st => match st with
  | Lynx.Term.atom "reserved" | Lynx.Term.atom "sent" | Lynx.Term.atom "unknown" | Lynx.Term.atom "authorized" | Lynx.Term.atom "voiding" => true
  | _ => false

theorem HoldLedgerProof.holding_model (st : Lynx.Term) :
    Elixir.HoldLedger.Spec.«holding?/1» st = Except.ok (if HoldLedgerProof.held st then Lynx.Term.true else Lynx.Term.false) := by
  simp only [HoldLedgerProof.held, Elixir.HoldLedger.Spec.«holding?/1»]
  repeat' (split <;> try simp_all [Lynx.Term.true, Lynx.Term.false])
  all_goals rfl

theorem HoldLedgerProof.totals_1 : ∀ es, Elixir.HoldLedger.Spec.«proper_entries?/1» es = Except.ok Lynx.Term.true →
    ∃ a c, Elixir.HoldLedger.Spec.«hold_amount/1» es = Except.ok (Lynx.Term.integer a) ∧
      Elixir.HoldLedger.Spec.«hold_count/1» es = Except.ok (Lynx.Term.integer c) := by
  intro es h
  fun_induction Elixir.HoldLedger.Spec.«hold_amount/1» es
  all_goals simp only [Elixir.HoldLedger.Spec.«proper_entries?/1»,
    Lynx.Except.guard, Lynx.Except.tryWith, bind, Except.bind] at h
  all_goals repeat' (split at h <;> try simp_all [Lynx.Term.true])
  all_goals simp_all [ Elixir.HoldLedger.Spec.«hold_count/1»,
    Elixir.HoldLedger.Spec.«holding?/1», Erlang.erlang.«is_integer/1»]
  all_goals repeat' (split at * <;> try simp_all [])
  all_goals obtain ⟨⟨a, ha⟩, c, hc⟩ :=
    (by assumption : (∃ a : Int, _) ∧ ∃ c : Int, _)
  all_goals simp_all []

theorem HoldLedgerProof.delta_1 : ∀ es k (a : Int) old to,
    Elixir.HoldLedger.Spec.«proper_entries?/1» es = Except.ok Lynx.Term.true →
    Elixir.HoldLedger.Spec.«lookup/2» es k =
      Except.ok (Lynx.Term.tuple #[Lynx.Term.atom "ok", Lynx.Term.tuple #[k, Lynx.Term.integer a, old]]) →
    ∃ out ba bc aa ac,
      Elixir.HoldLedger.Ledger.«set_status/3» es k to = Except.ok out ∧
      Elixir.HoldLedger.Spec.«hold_amount/1» es = Except.ok (Lynx.Term.integer ba) ∧
      Elixir.HoldLedger.Spec.«hold_count/1» es = Except.ok (Lynx.Term.integer bc) ∧
      Elixir.HoldLedger.Spec.«hold_amount/1» out = Except.ok (Lynx.Term.integer aa) ∧
      Elixir.HoldLedger.Spec.«hold_count/1» out = Except.ok (Lynx.Term.integer ac) ∧
      aa = ba - (if HoldLedgerProof.held old then a else 0) + (if HoldLedgerProof.held to then a else 0) ∧
      ac = bc - (if HoldLedgerProof.held old then 1 else 0) + (if HoldLedgerProof.held to then 1 else 0) := by
  intro es k a old to hp hf
  fun_induction Elixir.HoldLedger.Spec.«lookup/2» es k generalizing a old to
  all_goals try (rename_i ek av st rest ih; have recur := ih a old to)
  all_goals simp only [Elixir.HoldLedger.Spec.«proper_entries?/1»,
    Lynx.Except.guard, Lynx.Except.tryWith, bind, Except.bind] at hp
  all_goals repeat' (split at hp <;> try simp_all [Lynx.Term.true])
  all_goals simp_all [Erlang.erlang.«==/2», Erlang.erlang.«is_integer/1», Lynx.Term.true, Lynx.Term.false]
  all_goals repeat' (split at * <;> try simp_all [])
  all_goals try obtain ⟨⟨b, hb⟩, c, hc⟩ := HoldLedgerProof.totals_1 rest (by assumption)
  all_goals try obtain ⟨out, hm, ba, hba, bc, hbc, haa, hac⟩ := ih a old to rfl rfl
  all_goals simp_all [Elixir.HoldLedger.Ledger.«set_status/3»,
    Elixir.HoldLedger.Spec.«hold_amount/1», Elixir.HoldLedger.Spec.«hold_count/1»,
    HoldLedgerProof.holding_model, Erlang.erlang.«==/2»,
      Lynx.Term.true, Lynx.Term.false]
  all_goals repeat' (split <;> try simp_all [])
  all_goals first | omega | constructor <;> omega

theorem HoldLedgerProof.accounting_1 : ∀ es, Elixir.HoldLedger.Spec.«proper_entries?/1» es = Except.ok Lynx.Term.true →
    ∃ out a c, Elixir.HoldLedger.Ledger.«mark_unknown/1» es = Except.ok out ∧
      Elixir.HoldLedger.Spec.«hold_amount/1» es = Except.ok (Lynx.Term.integer a) ∧
      Elixir.HoldLedger.Spec.«hold_amount/1» out = Except.ok (Lynx.Term.integer a) ∧
      Elixir.HoldLedger.Spec.«hold_count/1» es = Except.ok (Lynx.Term.integer c) ∧
      Elixir.HoldLedger.Spec.«hold_count/1» out = Except.ok (Lynx.Term.integer c) := by
  intro es h
  fun_induction Elixir.HoldLedger.Ledger.«mark_unknown/1» es
  all_goals simp only [Elixir.HoldLedger.Spec.«proper_entries?/1»,
    Lynx.Except.guard, Lynx.Except.tryWith, bind, Except.bind] at h
  all_goals repeat' (split at h <;> try simp_all [Lynx.Term.true, Lynx.Term.false,
    Erlang.erlang.«is_integer/1», Elixir.HoldLedger.Spec.«known_status?/1»,
    Elixir.HoldLedger.Spec.«holding?/1», Elixir.HoldLedger.Spec.«terminal?/1»])
  all_goals simp_all [
    Elixir.HoldLedger.Spec.«hold_amount/1», Elixir.HoldLedger.Spec.«hold_count/1»,
    Elixir.HoldLedger.Spec.«holding?/1»]
  all_goals repeat' (split at * <;> try simp_all [])
  all_goals obtain ⟨out, hm, a, ha, hb, c, hc, hd⟩ :=
    (by assumption : ∃ out : Lynx.Term, _ ∧ ∃ a : Int, _ ∧ _ ∧ ∃ c : Int, _ ∧ _)
  all_goals simp_all [
    Elixir.HoldLedger.Spec.«hold_amount/1», Elixir.HoldLedger.Spec.«hold_count/1»,
    Elixir.HoldLedger.Spec.«holding?/1»]

theorem HoldLedgerProof.delta_2 : ∀ es k ek (a : Int) old to,
    Elixir.HoldLedger.Spec.«proper_entries?/1» es = Except.ok Lynx.Term.true →
    Elixir.HoldLedger.Ledger.«find/2» es k =
      Except.ok (Lynx.Term.tuple #[Lynx.Term.atom "ok", Lynx.Term.tuple #[ek, Lynx.Term.integer a, old]]) →
    ∃ out ba bc aa ac,
      Elixir.HoldLedger.Ledger.«set_status/3» es k to = Except.ok out ∧
      Elixir.HoldLedger.Spec.«hold_amount/1» es = Except.ok (Lynx.Term.integer ba) ∧
      Elixir.HoldLedger.Spec.«hold_count/1» es = Except.ok (Lynx.Term.integer bc) ∧
      Elixir.HoldLedger.Spec.«hold_amount/1» out = Except.ok (Lynx.Term.integer aa) ∧
      Elixir.HoldLedger.Spec.«hold_count/1» out = Except.ok (Lynx.Term.integer ac) ∧
      aa = ba - (if HoldLedgerProof.held old then a else 0) + (if HoldLedgerProof.held to then a else 0) ∧
      ac = bc - (if HoldLedgerProof.held old then 1 else 0) + (if HoldLedgerProof.held to then 1 else 0) := by
  intro es k ek a old to hp hf
  fun_induction Elixir.HoldLedger.Ledger.«find/2» es k generalizing ek a old to
  all_goals try (rename_i stored av st rest ih; have recur := ih ek a old to)
  all_goals simp only [Elixir.HoldLedger.Spec.«proper_entries?/1»,
    Lynx.Except.guard, Lynx.Except.tryWith, bind, Except.bind] at hp
  all_goals repeat' (split at hp <;> try simp_all [Lynx.Term.true])
  all_goals simp_all [Erlang.erlang.«==/2», Erlang.erlang.«is_integer/1», Lynx.Term.true, Lynx.Term.false]
  all_goals repeat' (split at * <;> try simp_all [])
  all_goals try obtain ⟨⟨b, hb⟩, c, hc⟩ := HoldLedgerProof.totals_1 rest (by assumption)
  all_goals try obtain ⟨out, hm, ba, hba, bc, hbc, haa, hac⟩ := ih ek a old to rfl rfl rfl
  all_goals simp_all [Elixir.HoldLedger.Ledger.«set_status/3»,
    Elixir.HoldLedger.Spec.«hold_amount/1», Elixir.HoldLedger.Spec.«hold_count/1»,
    HoldLedgerProof.holding_model, Erlang.erlang.«==/2»,
      Lynx.Term.true, Lynx.Term.false]
  all_goals repeat' (split <;> try simp_all [])
  all_goals first | omega | constructor <;> omega

theorem HoldLedgerProof.nonnegative_1 : ∀ es,
    Elixir.HoldLedger.Spec.«proper_entries?/1» es = Except.ok Lynx.Term.true →
    ∃ a c, Elixir.HoldLedger.Spec.«hold_amount/1» es = Except.ok (Lynx.Term.integer a) ∧
      Elixir.HoldLedger.Spec.«hold_count/1» es = Except.ok (Lynx.Term.integer c) ∧ 0 ≤ a ∧ 0 ≤ c := by
  intro es hp
  fun_induction Elixir.HoldLedger.Spec.«hold_amount/1» es
  all_goals simp only [Elixir.HoldLedger.Spec.«proper_entries?/1»,
    Lynx.Except.guard, Lynx.Except.tryWith, bind, Except.bind] at hp
  all_goals repeat' (split at hp <;> try simp_all [Lynx.Term.true])
  all_goals simp_all [ Elixir.HoldLedger.Spec.«hold_count/1»,
    Elixir.HoldLedger.Spec.«holding?/1», Erlang.erlang.«is_integer/1»,
    Erlang.erlang.«>/2», Ordering.isGT_iff_eq_gt]
  all_goals repeat' (split at * <;> try simp_all [])
  all_goals obtain ⟨a, ha, c, hc, hna, hnc⟩ := (by assumption : ∃ a : Int, _ ∧ ∃ c : Int, _ ∧ 0 ≤ a ∧ 0 ≤ c)
  all_goals simp_all [
     Int.compare_eq_gt]
  all_goals first | omega | constructor <;> omega

theorem HoldLedgerProof.selected_bound_1 : ∀ es k ek (a : Int) st,
    Elixir.HoldLedger.Spec.«proper_entries?/1» es = Except.ok Lynx.Term.true →
    Elixir.HoldLedger.Ledger.«find/2» es k = Except.ok
      (Lynx.Term.tuple #[Lynx.Term.atom "ok", Lynx.Term.tuple #[ek, Lynx.Term.integer a, st]]) →
    Elixir.HoldLedger.Spec.«holding?/1» st = Except.ok Lynx.Term.true →
    ∃ ba bc, Elixir.HoldLedger.Spec.«hold_amount/1» es = Except.ok (Lynx.Term.integer ba) ∧
      Elixir.HoldLedger.Spec.«hold_count/1» es = Except.ok (Lynx.Term.integer bc) ∧ a ≤ ba ∧ 1 ≤ bc := by
  intro es k ek a st hp hf hh
  fun_induction Elixir.HoldLedger.Ledger.«find/2» es k generalizing ek a st
  all_goals try (rename_i stored av status rest ih; have recur := ih ek a st)
  all_goals simp only [Elixir.HoldLedger.Spec.«proper_entries?/1»,
    Lynx.Except.guard, Lynx.Except.tryWith, bind, Except.bind] at hp
  all_goals repeat' (split at hp <;> try simp_all [Lynx.Term.true])
  all_goals simp_all [Erlang.erlang.«==/2», Erlang.erlang.«is_integer/1»,
    Erlang.erlang.«>/2», Ordering.isGT_iff_eq_gt,
    Lynx.Term.true, Lynx.Term.false]
  all_goals repeat' (split at * <;> try simp_all [])
  all_goals subst_vars
  all_goals try obtain ⟨ba, hba, bc, hbc, hna, hnc⟩ := recur
  all_goals try obtain ⟨ba, hba, bc, hbc, hna, hnc⟩ := HoldLedgerProof.nonnegative_1 _ (by assumption)
  all_goals simp_all [Elixir.HoldLedger.Spec.«hold_amount/1», Elixir.HoldLedger.Spec.«hold_count/1»,
    HoldLedgerProof.holding_model, Int.compare_eq_gt]
  all_goals repeat' (split <;> try simp_all [])
  all_goals try constructor <;> try omega

theorem HoldLedgerProof.positive_1 : ∀ es k ek (a : Int) st,
    Elixir.HoldLedger.Spec.«proper_entries?/1» es = Except.ok Lynx.Term.true →
    Elixir.HoldLedger.Ledger.«find/2» es k = Except.ok
      (Lynx.Term.tuple #[Lynx.Term.atom "ok", Lynx.Term.tuple #[ek, Lynx.Term.integer a, st]]) → 0 ≤ a := by
  intro es k ek a st hp hf
  fun_induction Elixir.HoldLedger.Ledger.«find/2» es k generalizing ek a st
  all_goals simp only [Elixir.HoldLedger.Spec.«proper_entries?/1»,
    Lynx.Except.guard, Lynx.Except.tryWith, bind, Except.bind] at hp
  all_goals repeat' (split at hp <;> try simp_all [Lynx.Term.true])
  all_goals simp_all [Erlang.erlang.«==/2», Erlang.erlang.«is_integer/1»,
    Erlang.erlang.«>/2», Ordering.isGT_iff_eq_gt,  Lynx.Term.true, Lynx.Term.false]
  all_goals repeat' (split at * <;> subst_vars <;> try simp_all [Int.compare_eq_gt])
  all_goals omega
