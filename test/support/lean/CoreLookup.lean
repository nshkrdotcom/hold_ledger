module

public import Elixir.HoldLedger.ProofContracts
public import HoldLedgerProof.Induction

public section
set_option maxHeartbeats 16000000

theorem HoldLedgerProof.atom_exact (n : String) (x : Lynx.Term) :
    (Lynx.Term.atom n).exactCompare x = Ordering.eq ↔ x = Lynx.Term.atom n := by
  rw [Std.OrientedCmp.eq_swap (cmp := Lynx.Term.exactCompare), Ordering.swap_eq_eq]
  exact Lynx.Term.exactCompare_eq_atom x n

theorem HoldLedgerProof.known_exact_1 : ∀ st x, Elixir.HoldLedger.Spec.«known_status?/1» st = Except.ok Lynx.Term.true →
    st.exactCompare x = Ordering.eq → st = x := by
  intro st x hs he
  simp only [Elixir.HoldLedger.Spec.«known_status?/1»,
    Elixir.HoldLedger.Spec.«holding?/1», Elixir.HoldLedger.Spec.«terminal?/1»,
    bind, Except.bind] at hs
  repeat' (split at * <;> try simp_all [Lynx.Term.true, Lynx.Term.false, HoldLedgerProof.atom_exact, bind, Except.bind])

theorem HoldLedgerProof.lookup_shape_1 : ∀ es k, Elixir.HoldLedger.Spec.«proper_entries?/1» es = Except.ok Lynx.Term.true →
    Elixir.HoldLedger.Spec.«lookup/2» es k = Except.ok (Lynx.Term.atom "not_found") ∨
    ∃ (ek a : Int) (st : Lynx.Term),
      Elixir.HoldLedger.Spec.«lookup/2» es k =
        Except.ok (Lynx.Term.tuple #[Lynx.Term.atom "ok", Lynx.Term.tuple #[Lynx.Term.integer ek, Lynx.Term.integer a, st]]) ∧
      Elixir.HoldLedger.Spec.«known_status?/1» st = Except.ok Lynx.Term.true := by
  intro es k h
  fun_induction Elixir.HoldLedger.Spec.«lookup/2» es k
  all_goals simp only [Elixir.HoldLedger.Spec.«proper_entries?/1»,
    Lynx.Except.guard, Lynx.Except.tryWith, bind, Except.bind] at h
  all_goals repeat' (split at h <;> try simp_all [Lynx.Term.true, Lynx.Term.false])
  all_goals simp_all [Elixir.HoldLedger.Spec.«lookup/2», Erlang.erlang.«is_integer/1»,
    Erlang.erlang.«==/2», Lynx.Term.true, Lynx.Term.false]
  all_goals repeat' (split at * <;> try simp_all [Lynx.Term.true, Lynx.Term.false])
  all_goals first | assumption | exact ⟨_, _, _, by exact ⟨rfl, rfl, rfl⟩, by assumption⟩

theorem HoldLedgerProof.integer_key_1 : ∀ es seen q a old,
    Elixir.HoldLedger.Spec.«unique_keys_seen?/2» es seen = Except.ok Lynx.Term.true →
    Elixir.HoldLedger.Spec.«lookup/2» es q =
      Except.ok (Lynx.Term.tuple #[Lynx.Term.atom "ok", Lynx.Term.tuple #[q,a,old]]) →
    ∃ n, q = Lynx.Term.integer n := by
  intro es seen q a old h hl
  fun_induction Elixir.HoldLedger.Spec.«unique_keys_seen?/2» es seen generalizing q a old
  all_goals try simp only [Elixir.HoldLedger.Spec.«unique_keys_seen?/2»,
    Elixir.HoldLedger.Spec.«seen?/2», bind, Except.bind] at h
  all_goals repeat' (split at h <;> try simp_all [Lynx.Term.true, Lynx.Term.false])
  all_goals try simp_all [Elixir.HoldLedger.Spec.«lookup/2», Erlang.erlang.«==/2»,
    bind, Except.bind, Lynx.Term.true, Lynx.Term.false]
  all_goals repeat' (split at hl <;> try simp_all [Lynx.Term.true, Lynx.Term.false])
  all_goals first | solve_by_elim | exact ⟨_, hl.1.symm⟩

theorem HoldLedgerProof.compatible_1 : ∀ es k, Elixir.HoldLedger.Spec.«proper_entries?/1» es = Except.ok Lynx.Term.true →
    ∃ v, Elixir.HoldLedger.Ledger.«find/2» es k = Except.ok v ∧
      Elixir.HoldLedger.Spec.«lookup/2» es k = Except.ok v := by
  intro es k h
  fun_induction Elixir.HoldLedger.Ledger.«find/2» es k
  all_goals simp only [Elixir.HoldLedger.Spec.«proper_entries?/1»,
    Lynx.Except.guard, Lynx.Except.tryWith, bind, Except.bind] at h
  all_goals try { exact ⟨Lynx.Term.atom "not_found", rfl, rfl⟩ }
  all_goals repeat' (split at h <;> try simp_all [Lynx.Term.true, Lynx.Term.false])
  all_goals simp_all [Erlang.erlang.«==/2», Elixir.HoldLedger.Ledger.«find/2», Elixir.HoldLedger.Spec.«lookup/2»]
  all_goals repeat' (split <;> try simp_all [Lynx.Term.true, Lynx.Term.false])
  all_goals first | assumption | exact ⟨_, rfl, rfl⟩

theorem HoldLedgerProof.lookup_shape_2 : ∀ es k, Elixir.HoldLedger.Spec.«proper_entries?/1» es = Except.ok Lynx.Term.true →
    Elixir.HoldLedger.Ledger.«find/2» es k = Except.ok (Lynx.Term.atom "not_found") ∨
    ∃ (ek a : Int) (st : Lynx.Term),
      Elixir.HoldLedger.Ledger.«find/2» es k =
        Except.ok (Lynx.Term.tuple #[Lynx.Term.atom "ok", Lynx.Term.tuple #[Lynx.Term.integer ek, Lynx.Term.integer a, st]]) ∧
      Elixir.HoldLedger.Spec.«known_status?/1» st = Except.ok Lynx.Term.true := by
  intro es k h
  fun_induction Elixir.HoldLedger.Ledger.«find/2» es k
  all_goals simp only [Elixir.HoldLedger.Spec.«proper_entries?/1»,
    Lynx.Except.guard, Lynx.Except.tryWith, bind, Except.bind] at h
  all_goals repeat' (split at h <;> try simp_all [Lynx.Term.true, Lynx.Term.false])
  all_goals simp_all [Elixir.HoldLedger.Ledger.«find/2», Erlang.erlang.«is_integer/1»,
    Erlang.erlang.«==/2», Lynx.Term.true, Lynx.Term.false]
  all_goals repeat' (split at * <;> try simp_all [Lynx.Term.true, Lynx.Term.false])
  all_goals first | assumption | exact ⟨_, _, _, by exact ⟨rfl, rfl, rfl⟩, by assumption⟩

theorem HoldLedgerProof.compatible_2 : ∀ es k, Elixir.HoldLedger.Spec.«proper_entries?/1» es = Except.ok Lynx.Term.true →
    ∃ v, Elixir.HoldLedger.Ledger.«find/2» es k = Except.ok v ∧
      Elixir.HoldLedger.Spec.«lookup/2» es k = Except.ok v ∧
      (v = Lynx.Term.atom "not_found" ∨ ∃ (ek : Lynx.Term) (n : Int) (st : Lynx.Term),
        v = Lynx.Term.tuple #[Lynx.Term.atom "ok", Lynx.Term.tuple #[ek, Lynx.Term.integer n, st]]) := by
  intro es k h
  fun_induction Elixir.HoldLedger.Ledger.«find/2» es k
  all_goals simp only [Elixir.HoldLedger.Spec.«proper_entries?/1»,
    Lynx.Except.guard, Lynx.Except.tryWith, bind, Except.bind] at h
  all_goals try { exact ⟨Lynx.Term.atom "not_found", rfl, rfl, Or.inl rfl⟩ }
  all_goals repeat' (split at h <;> try simp_all [Lynx.Term.true, Lynx.Term.false])
  all_goals simp_all [Erlang.erlang.«==/2», Elixir.HoldLedger.Ledger.«find/2», Elixir.HoldLedger.Spec.«lookup/2»]
  all_goals repeat' (split <;> try simp_all [Lynx.Term.true, Lynx.Term.false])
  all_goals simp_all [Erlang.erlang.«is_integer/1»]
  all_goals repeat' (split at * <;> try simp_all [Lynx.Term.true, Lynx.Term.false])
  all_goals first | assumption | exact ⟨_, rfl, rfl, Or.inr ⟨_, _, _, rfl⟩⟩

theorem HoldLedgerProof.compatible_3 : ∀ es k, Elixir.HoldLedger.Spec.«proper_entries?/1» es = Except.ok Lynx.Term.true →
    ∃ v, Elixir.HoldLedger.Ledger.«find/2» es k = Except.ok v ∧
      Elixir.HoldLedger.Ledger.«find/2» es k = Except.ok v ∧
      (v = Lynx.Term.atom "not_found" ∨ ∃ (ek : Lynx.Term) (n : Int) (st : Lynx.Term),
        v = Lynx.Term.tuple #[Lynx.Term.atom "ok", Lynx.Term.tuple #[ek, Lynx.Term.integer n, st]]) := by
  intro es k h
  fun_induction Elixir.HoldLedger.Ledger.«find/2» es k
  all_goals simp only [Elixir.HoldLedger.Spec.«proper_entries?/1»,
    Lynx.Except.guard, Lynx.Except.tryWith, bind, Except.bind] at h
  all_goals try { exact ⟨Lynx.Term.atom "not_found", rfl, rfl, Or.inl rfl⟩ }
  all_goals repeat' (split at h <;> try simp_all [Lynx.Term.true, Lynx.Term.false])
  all_goals simp_all [Erlang.erlang.«==/2», Elixir.HoldLedger.Ledger.«find/2», Elixir.HoldLedger.Ledger.«find/2»]
  all_goals repeat' (split <;> try simp_all [Lynx.Term.true, Lynx.Term.false])
  all_goals simp_all [Erlang.erlang.«is_integer/1»]
  all_goals repeat' (split at * <;> try simp_all [Lynx.Term.true, Lynx.Term.false])
  all_goals first | assumption | exact ⟨_, rfl, rfl, Or.inr ⟨_, _, _, rfl⟩⟩

theorem HoldLedgerProof.lookup_equiv_1 : ∀ es (n : Int) query,
    Elixir.HoldLedger.Spec.«proper_entries?/1» es = Except.ok Lynx.Term.true →
    (Lynx.Term.integer n).compare query = Ordering.eq →
    Elixir.HoldLedger.Spec.«lookup/2» es query = Elixir.HoldLedger.Spec.«lookup/2» es (Lynx.Term.integer n) := by
  intro es n query hp he
  fun_induction Elixir.HoldLedger.Spec.«lookup/2» es query generalizing n
  all_goals simp only [Elixir.HoldLedger.Spec.«proper_entries?/1»,
    Lynx.Except.guard, Lynx.Except.tryWith, bind, Except.bind] at hp
  all_goals repeat' (split at hp <;> try simp_all [Lynx.Term.true, Lynx.Term.false])
  all_goals simp_all [Erlang.erlang.«is_integer/1», Lynx.Term.true, Lynx.Term.false]
  all_goals repeat' (split at * <;> try simp_all [Lynx.Term.true, Lynx.Term.false])
  all_goals simp_all [Elixir.HoldLedger.Spec.«lookup/2», Erlang.erlang.«==/2»,
    HoldLedgerProof.integer_query _ _ _ he, Int.compare_eq_eq, bind, Except.bind]
  all_goals repeat' (split <;> try simp_all [Lynx.Term.true, Lynx.Term.false])
