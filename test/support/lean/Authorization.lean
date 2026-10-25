module

public import Elixir.HoldLedger.ProofContracts
public import HoldLedgerProof.Induction
public import HoldLedgerProof.CoreLookup
public import HoldLedgerProof.CorePreservation

public section
set_option maxHeartbeats 16000000
namespace Elixir.HoldLedger.ProofContracts

theorem «po_b4/2» (s event : Lynx.Term)
    (requires : «po_b4:requires/2» s event = Except.ok Lynx.Term.true) :
    «po_b4:ensures/2» s event = Except.ok Lynx.Term.true := by
  have replaced := HoldLedgerProof.replaced_1
  have explained := HoldLedgerProof.explained_1
  have marked := HoldLedgerProof.marked_1
  have integer_key := HoldLedgerProof.integer_key_1
  have compatible := HoldLedgerProof.compatible_1
  have reflexive := HoldLedgerProof.reflexive_1
  have nonauthorized := HoldLedgerProof.nonauthorized_1
  have marked_safe := HoldLedgerProof.marked_safe_1
  have fresh := HoldLedgerProof.fresh_2
  have authorized := HoldLedgerProof.authorized_1
  have lookup_shape := HoldLedgerProof.lookup_shape_1
  have shaped : ∃ (al hl ua uh : Int) (es : Lynx.Term),
      s = Lynx.Term.tuple #[Lynx.Term.integer al, Lynx.Term.integer hl,
        Lynx.Term.integer ua, Lynx.Term.integer uh, es] ∧
      Elixir.HoldLedger.Spec.«proper_entries?/1» es = Except.ok Lynx.Term.true ∧
      Elixir.HoldLedger.Spec.«unique_keys_seen?/2» es Lynx.Term.nil = Except.ok Lynx.Term.true := by
    clear replaced explained marked integer_key compatible reflexive nonauthorized marked_safe fresh authorized lookup_shape
    simp only [«po_b4:requires/2», Elixir.HoldLedger.Spec.«valid?/1», Elixir.HoldLedger.Spec.«nonnegative_state_valid?/5»,
      Lynx.Except.guard, Lynx.Except.tryWith, bind, Except.bind] at requires
    all_goals repeat' (split at requires <;> try simp_all [Lynx.Term.true, Lynx.Term.false])
    all_goals repeat' (split at * <;> try simp_all [Lynx.Term.true, Lynx.Term.false])
    all_goals simp only [Erlang.erlang.«is_integer/1», Elixir.HoldLedger.Spec.«unique_keys?/1»,
      Lynx.Except.guard, Lynx.Except.tryWith, bind, Except.bind] at *
    all_goals repeat' (split at * <;> try simp_all [Lynx.Term.true, Lynx.Term.false])
    all_goals exact ⟨_, _, _, _, _, by exact ⟨rfl, rfl, rfl, rfl, rfl⟩, by assumption, by assumption⟩
  obtain ⟨al, hl, ua, uh, es, rfl, hp, hu⟩ := shaped
  have same := reflexive es event hu
  have find_eq : ∀ k, Elixir.HoldLedger.Ledger.«find/2» es k = Elixir.HoldLedger.Spec.«lookup/2» es k := by
    intro k
    obtain ⟨v, hf, hl⟩ := compatible es k hp
    exact hf.trans hl.symm
  let changed (k st : Lynx.Term) := Classical.choose (replaced es k st Lynx.Term.nil hu)
  have change_eq (k st : Lynx.Term) : Elixir.HoldLedger.Ledger.«set_status/3» es k st = Except.ok (changed k st) :=
    (Classical.choose_spec (replaced es k st Lynx.Term.nil hu)).1
  have change_safe (k st : Lynx.Term) (hn : st ≠ Lynx.Term.atom "authorized") :
      Elixir.HoldLedger.Spec.«authorizations_explained?/3» es (changed k st) event = Except.ok Lynx.Term.true := by
    obtain ⟨out, hm, hs⟩ := nonauthorized es k st event hu hn
    have he : out = changed k st := Except.ok.inj (hm.symm.trans (change_eq k st))
    simpa [he] using hs
  have change_approved (k : Int) (ek a old : Lynx.Term)
      (hlookup : Elixir.HoldLedger.Spec.«lookup/2» es (Lynx.Term.integer k) =
        Except.ok (Lynx.Term.tuple #[Lynx.Term.atom "ok", Lynx.Term.tuple #[ek,a,old]]))
      (hstatus : old = Lynx.Term.atom "sent" ∨ old = Lynx.Term.atom "unknown") :
      Elixir.HoldLedger.Spec.«authorizations_explained?/3» es
        (changed (Lynx.Term.integer k) (Lynx.Term.atom "authorized"))
        (Lynx.Term.tuple #[Lynx.Term.atom "processor_result", Lynx.Term.integer k, Lynx.Term.atom "approved"]) =
          Except.ok Lynx.Term.true := by
    obtain ⟨out, hm, hs⟩ := authorized es k ek a old hu hlookup hstatus
    have he : out = changed (Lynx.Term.integer k) (Lynx.Term.atom "authorized") :=
      Except.ok.inj (hm.symm.trans (change_eq _ _))
    simpa [he] using hs
  obtain ⟨restarted, hr, restart_safe⟩ := marked_safe es event hu
  clear_value changed
  clear requires replaced explained marked integer_key compatible reflexive nonauthorized marked_safe authorized
  simp only [«po_b4:ensures/2», Elixir.HoldLedger.Ledger.«step/2»]
  split
  case h_1 ev k amount =>
    cases k <;> simp [Elixir.HoldLedger.Ledger.«request/3», Erlang.erlang.«is_integer/1»,
      Elixir.HoldLedger.Spec.«authorized_only_on_result?/3», same, Erlang.erlang.«element/2»,
      Lynx.Except.guard, Lynx.Except.tryWith, bind, Except.bind,
      Lynx.Term.true, Lynx.Term.false]
    all_goals cases amount <;> simp [Elixir.HoldLedger.Ledger.«request/3», Erlang.erlang.«is_integer/1»,
      Elixir.HoldLedger.Spec.«authorized_only_on_result?/3», same, Erlang.erlang.«element/2»,
      Lynx.Except.guard, Lynx.Except.tryWith, bind, Except.bind,
      Lynx.Term.true, Lynx.Term.false]
    rename_i n amountn
    rcases lookup_shape es (Lynx.Term.integer n) hp with hn | ⟨ek, av, st, hlookup, hst⟩
    all_goals try have hid := fresh es n (Lynx.Term.integer amountn) event hu (by assumption)
    all_goals simp_all [find_eq, Erlang.erlang.«>/2», Erlang.erlang.«=:=/2»,
      Elixir.HoldLedger.Spec.«authorized_only_on_result?/3», Erlang.erlang.«element/2»,
      Lynx.Except.guard, Lynx.Except.tryWith, bind, Except.bind,
      Lynx.Term.true, Lynx.Term.false]
    all_goals repeat' (split at * <;> (repeat' split_conjunction) <;> subst_vars <;> try simp_all [Elixir.HoldLedger.Spec.«authorized_only_on_result?/3»,
      Erlang.erlang.«element/2», bind, Except.bind, Lynx.Term.true, Lynx.Term.false])
    all_goals repeat' split_conjunction
    all_goals subst_vars
    all_goals try simp_all [change_safe, change_approved, Elixir.HoldLedger.Spec.«authorized_only_on_result?/3», same, Erlang.erlang.«element/2», bind, Except.bind, Lynx.Term.true, Lynx.Term.false]
    all_goals try solve_by_elim (maxDepth := 20)
    all_goals try grind only [change_safe, change_approved]
  case h_2 ev k =>
    rcases lookup_shape es k hp with hn | ⟨ek, av, st, hlookup, hst⟩
    all_goals simp only [Elixir.HoldLedger.Ledger.«dispatch/2»]
    all_goals try simp_all [find_eq, change_eq, change_safe, change_approved,
      Elixir.HoldLedger.Spec.«authorized_only_on_result?/3», same,
      Erlang.erlang.«element/2», Erlang.erlang.«is_integer/1»,
      Erlang.erlang.«=:=/2», Erlang.erlang.«==/2»,
      Lynx.Except.guard, Lynx.Except.tryWith, bind, Except.bind,
      Lynx.Term.true, Lynx.Term.false]
    all_goals repeat' (split at * <;> (repeat' split_conjunction) <;> subst_vars <;> try simp_all [find_eq, change_eq, change_safe, change_approved,
      Elixir.HoldLedger.Spec.«authorized_only_on_result?/3», same,
      Erlang.erlang.«element/2», Erlang.erlang.«is_integer/1»,
      Erlang.erlang.«=:=/2», Erlang.erlang.«==/2»,
      Lynx.Except.guard, Lynx.Except.tryWith, bind, Except.bind,
      Lynx.Term.true, Lynx.Term.false])
    all_goals repeat' split_conjunction
    all_goals subst_vars
    all_goals try simp_all [change_safe, change_approved, Elixir.HoldLedger.Spec.«authorized_only_on_result?/3», same, Erlang.erlang.«element/2», bind, Except.bind, Lynx.Term.true, Lynx.Term.false]
    all_goals try solve_by_elim (maxDepth := 20)
    all_goals try grind only [change_safe, change_approved]
  case h_3 ev k =>
    rcases lookup_shape es k hp with hn | ⟨ek, av, st, hlookup, hst⟩
    all_goals simp only [Elixir.HoldLedger.Ledger.«timeout/2»]
    all_goals try simp_all [find_eq, change_eq, change_safe, change_approved,
      Elixir.HoldLedger.Spec.«authorized_only_on_result?/3», same,
      Erlang.erlang.«element/2», Erlang.erlang.«is_integer/1»,
      Erlang.erlang.«=:=/2», Erlang.erlang.«==/2»,
      Lynx.Except.guard, Lynx.Except.tryWith, bind, Except.bind,
      Lynx.Term.true, Lynx.Term.false]
    all_goals repeat' (split at * <;> (repeat' split_conjunction) <;> subst_vars <;> try simp_all [find_eq, change_eq, change_safe, change_approved,
      Elixir.HoldLedger.Spec.«authorized_only_on_result?/3», same,
      Erlang.erlang.«element/2», Erlang.erlang.«is_integer/1»,
      Erlang.erlang.«=:=/2», Erlang.erlang.«==/2»,
      Lynx.Except.guard, Lynx.Except.tryWith, bind, Except.bind,
      Lynx.Term.true, Lynx.Term.false])
    all_goals repeat' split_conjunction
    all_goals subst_vars
    all_goals try simp_all [change_safe, change_approved, Elixir.HoldLedger.Spec.«authorized_only_on_result?/3», same, Erlang.erlang.«element/2», bind, Except.bind, Lynx.Term.true, Lynx.Term.false]
    all_goals try solve_by_elim (maxDepth := 20)
    all_goals try grind only [change_safe, change_approved]
  case h_5 ev k =>
    rcases lookup_shape es k hp with hn | ⟨ek, av, st, hlookup, hst⟩
    all_goals simp only [Elixir.HoldLedger.Ledger.«retry/2»]
    all_goals try simp_all [find_eq, change_eq, change_safe, change_approved,
      Elixir.HoldLedger.Spec.«authorized_only_on_result?/3», same,
      Erlang.erlang.«element/2», Erlang.erlang.«is_integer/1»,
      Erlang.erlang.«=:=/2», Erlang.erlang.«==/2»,
      Lynx.Except.guard, Lynx.Except.tryWith, bind, Except.bind,
      Lynx.Term.true, Lynx.Term.false]
    all_goals repeat' (split at * <;> (repeat' split_conjunction) <;> subst_vars <;> try simp_all [find_eq, change_eq, change_safe, change_approved,
      Elixir.HoldLedger.Spec.«authorized_only_on_result?/3», same,
      Erlang.erlang.«element/2», Erlang.erlang.«is_integer/1»,
      Erlang.erlang.«=:=/2», Erlang.erlang.«==/2»,
      Lynx.Except.guard, Lynx.Except.tryWith, bind, Except.bind,
      Lynx.Term.true, Lynx.Term.false])
    all_goals repeat' split_conjunction
    all_goals subst_vars
    all_goals try simp_all [change_safe, change_approved, Elixir.HoldLedger.Spec.«authorized_only_on_result?/3», same, Erlang.erlang.«element/2», bind, Except.bind, Lynx.Term.true, Lynx.Term.false]
    all_goals try solve_by_elim (maxDepth := 20)
    all_goals try grind only [change_safe, change_approved]
  case h_6 ev k outcome =>
    rcases lookup_shape es k hp with hn | ⟨ek, av, st, hlookup, hst⟩
    all_goals simp only [Elixir.HoldLedger.Ledger.«processor_result/3»]
    all_goals try simp_all [find_eq, change_eq, change_safe, change_approved,
      Elixir.HoldLedger.Spec.«authorized_only_on_result?/3», same,
      Erlang.erlang.«element/2», Erlang.erlang.«is_integer/1»,
      Erlang.erlang.«=:=/2», Erlang.erlang.«==/2»,
      Lynx.Except.guard, Lynx.Except.tryWith, bind, Except.bind,
      Lynx.Term.true, Lynx.Term.false]
    all_goals repeat' (split at * <;> (repeat' split_conjunction) <;> subst_vars <;> try simp_all [find_eq, change_eq, change_safe, change_approved,
      Elixir.HoldLedger.Spec.«authorized_only_on_result?/3», same,
      Erlang.erlang.«element/2», Erlang.erlang.«is_integer/1»,
      Erlang.erlang.«=:=/2», Erlang.erlang.«==/2»,
      Lynx.Except.guard, Lynx.Except.tryWith, bind, Except.bind,
      Lynx.Term.true, Lynx.Term.false])
    all_goals repeat' split_conjunction
    all_goals subst_vars
    all_goals try simp_all [change_safe, change_approved, Elixir.HoldLedger.Spec.«authorized_only_on_result?/3», same, Erlang.erlang.«element/2», bind, Except.bind, Lynx.Term.true, Lynx.Term.false]
    all_goals try solve_by_elim (maxDepth := 20)
    all_goals try grind only [change_safe, change_approved]
    all_goals try exact change_approved _ _ _ _ (by assumption) (by
      by_cases h : st = Lynx.Term.atom "sent"
      · exact Or.inl h
      · exact Or.inr (by solve_by_elim))
  case h_7 ev k =>
    rcases lookup_shape es k hp with hn | ⟨ek, av, st, hlookup, hst⟩
    all_goals simp only [Elixir.HoldLedger.Ledger.«void/2»]
    all_goals try simp_all [find_eq, change_eq, change_safe, change_approved,
      Elixir.HoldLedger.Spec.«authorized_only_on_result?/3», same,
      Erlang.erlang.«element/2», Erlang.erlang.«is_integer/1»,
      Erlang.erlang.«=:=/2», Erlang.erlang.«==/2»,
      Lynx.Except.guard, Lynx.Except.tryWith, bind, Except.bind,
      Lynx.Term.true, Lynx.Term.false]
    all_goals repeat' (split at * <;> (repeat' split_conjunction) <;> subst_vars <;> try simp_all [find_eq, change_eq, change_safe, change_approved,
      Elixir.HoldLedger.Spec.«authorized_only_on_result?/3», same,
      Erlang.erlang.«element/2», Erlang.erlang.«is_integer/1»,
      Erlang.erlang.«=:=/2», Erlang.erlang.«==/2»,
      Lynx.Except.guard, Lynx.Except.tryWith, bind, Except.bind,
      Lynx.Term.true, Lynx.Term.false])
    all_goals repeat' split_conjunction
    all_goals subst_vars
    all_goals try simp_all [change_safe, change_approved, Elixir.HoldLedger.Spec.«authorized_only_on_result?/3», same, Erlang.erlang.«element/2», bind, Except.bind, Lynx.Term.true, Lynx.Term.false]
    all_goals try solve_by_elim (maxDepth := 20)
    all_goals try grind only [change_safe, change_approved]
  case h_4 =>
    simp [Elixir.HoldLedger.Ledger.«restart/1», hr, restart_safe,
      Elixir.HoldLedger.Spec.«authorized_only_on_result?/3», Erlang.erlang.«element/2», bind, Except.bind]
    all_goals repeat' split_conjunction
    all_goals subst_vars
    all_goals try simp_all [change_safe, change_approved, Elixir.HoldLedger.Spec.«authorized_only_on_result?/3», same, Erlang.erlang.«element/2», bind, Except.bind, Lynx.Term.true, Lynx.Term.false]
    all_goals try solve_by_elim (maxDepth := 20)
    all_goals try grind only [change_safe, change_approved]
  case h_8 ev k =>
    cases k <;> simp [Elixir.HoldLedger.Ledger.«transport_ack/2»,
      Elixir.HoldLedger.Spec.«authorized_only_on_result?/3», same,
      Erlang.erlang.«element/2», Erlang.erlang.«is_integer/1»,
      Lynx.Except.guard, Lynx.Except.tryWith, bind, Except.bind]
    all_goals repeat' split_conjunction
    all_goals subst_vars
    all_goals try simp_all [change_safe, change_approved, Elixir.HoldLedger.Spec.«authorized_only_on_result?/3», same, Erlang.erlang.«element/2», bind, Except.bind, Lynx.Term.true, Lynx.Term.false]
    all_goals try solve_by_elim (maxDepth := 20)
    all_goals try grind only [change_safe, change_approved]
  case h_9 =>
    simp [Elixir.HoldLedger.Spec.«authorized_only_on_result?/3», same,
      Erlang.erlang.«element/2», bind, Except.bind]

end Elixir.HoldLedger.ProofContracts
