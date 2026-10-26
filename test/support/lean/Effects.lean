module

public import Elixir.HoldLedger.ProofContracts
public import HoldLedgerProof.Induction
public import HoldLedgerProof.Step

public section
set_option maxHeartbeats 16000000
namespace Elixir.HoldLedger.ProofContracts

theorem «po_b3/2» (s event : Lynx.Term)
    (requires : «po_b3:requires/2» s event = Except.ok Lynx.Term.true) :
    «po_b3:ensures/2» s event = Except.ok Lynx.Term.true := by
  have effects_correct : (∀ state ev, Elixir.HoldLedger.Spec.«valid?/1» state = Except.ok Lynx.Term.true →
      (do let output ← Elixir.HoldLedger.Ledger.«step/2» state ev
          let next ← Erlang.erlang.«element/2» (Lynx.Term.integer 1) output
          Elixir.HoldLedger.Spec.«valid?/1» next) = Except.ok Lynx.Term.true) →
      ∀ s event, Elixir.HoldLedger.Spec.«valid?/1» s = Except.ok Lynx.Term.true →
      «po_b3:ensures/2» s event = Except.ok Lynx.Term.true := by
    clear requires s event
    intro step_valid s event hv
    have lookup_shape : ∀ es (k : Int), Elixir.HoldLedger.Spec.«proper_entries?/1» es = Except.ok Lynx.Term.true →
        (Elixir.HoldLedger.Ledger.«find/2» es (Lynx.Term.integer k) = Except.ok (Lynx.Term.atom "not_found") ∧
          Elixir.HoldLedger.Spec.«lookup/2» es (Lynx.Term.integer k) = Except.ok (Lynx.Term.atom "not_found")) ∨
        ∃ (a : Int) (st : Lynx.Term),
          Elixir.HoldLedger.Ledger.«find/2» es (Lynx.Term.integer k) =
            Except.ok (Lynx.Term.tuple #[Lynx.Term.atom "ok", Lynx.Term.tuple #[Lynx.Term.integer k, Lynx.Term.integer a, st]]) ∧
          Elixir.HoldLedger.Spec.«lookup/2» es (Lynx.Term.integer k) =
            Except.ok (Lynx.Term.tuple #[Lynx.Term.atom "ok", Lynx.Term.tuple #[Lynx.Term.integer k, Lynx.Term.integer a, st]]) ∧
          Elixir.HoldLedger.Spec.«known_status?/1» st = Except.ok Lynx.Term.true := by
      clear hv s event step_valid
      intro es k h
      fun_induction Elixir.HoldLedger.Ledger.«find/2» es (Lynx.Term.integer k)
      all_goals simp only [Elixir.HoldLedger.Spec.«proper_entries?/1»,
        Lynx.Except.guard, Lynx.Except.tryWith, Lynx.Except.andAlso,  bind, Except.bind] at h
      all_goals repeat' (split at h <;> try simp_all [Lynx.Term.true])
      all_goals simp_all [ Elixir.HoldLedger.Spec.«lookup/2»,
        Erlang.erlang.«is_integer/1», Erlang.erlang.«==/2»,  Lynx.Term.true, Lynx.Term.false]
      all_goals repeat' (split at * <;> subst_vars <;> try simp_all [])
      all_goals first | assumption | exact ⟨_, _, ⟨rfl, rfl⟩, by assumption⟩
    have changed_lookup : ∀ es k a old to,
        Elixir.HoldLedger.Spec.«proper_entries?/1» es = Except.ok Lynx.Term.true →
        Elixir.HoldLedger.Spec.«lookup/2» es k =
          Except.ok (Lynx.Term.tuple #[Lynx.Term.atom "ok", Lynx.Term.tuple #[k,a,old]]) →
        ∃ out, Elixir.HoldLedger.Ledger.«set_status/3» es k to = Except.ok out ∧
          Elixir.HoldLedger.Spec.«lookup/2» out k =
            Except.ok (Lynx.Term.tuple #[Lynx.Term.atom "ok", Lynx.Term.tuple #[k,a,to]]) := by
      clear hv s event step_valid lookup_shape
      intro es k a old to hp hf
      fun_induction Elixir.HoldLedger.Spec.«lookup/2» es k generalizing a old to
      case case1 => simp [] at hf
      case case3 => simp [] at hf
      case case2 ek av st rest ih =>
        have recur := ih a old to
        all_goals simp only [Elixir.HoldLedger.Spec.«proper_entries?/1»,
          Lynx.Except.guard, Lynx.Except.tryWith, Lynx.Except.andAlso,  bind, Except.bind] at hp
        all_goals repeat' (split at hp <;> try simp_all [Lynx.Term.true])
        all_goals simp_all [Erlang.erlang.«==/2», Erlang.erlang.«is_integer/1», Lynx.Term.true, Lynx.Term.false]
        all_goals repeat' (split at * <;> subst_vars <;> try simp_all [])
        all_goals try obtain ⟨out, hm, hl⟩ := recur
        all_goals try obtain ⟨out, hm, hl⟩ := recur rfl rfl
        all_goals try obtain ⟨out, hm, hl⟩ := ih a old to rfl rfl
        all_goals simp_all [Elixir.HoldLedger.Ledger.«set_status/3», Elixir.HoldLedger.Spec.«lookup/2»,
          Erlang.erlang.«==/2»,
          Lynx.Term.true, Lynx.Term.false]
        all_goals repeat' (split <;> try simp_all [Lynx.Term.true, Lynx.Term.false])
        all_goals try first | rfl | exact ⟨_,rfl,rfl⟩ | solve_by_elim
    have shaped : ∃ (al hl ua uh : Int) (es : Lynx.Term),
        s = Lynx.Term.tuple #[Lynx.Term.integer al, Lynx.Term.integer hl,
          Lynx.Term.integer ua, Lynx.Term.integer uh, es] ∧
        Elixir.HoldLedger.Spec.«proper_entries?/1» es = Except.ok Lynx.Term.true ∧
        Elixir.HoldLedger.Spec.«unique_keys_seen?/2» es Lynx.Term.nil = Except.ok Lynx.Term.true := by
      clear lookup_shape changed_lookup step_valid
      simp only [Elixir.HoldLedger.Spec.«valid?/1», Elixir.HoldLedger.Spec.«nonnegative_state_valid?/5»,
        Lynx.Except.guard, Lynx.Except.tryWith, Lynx.Except.andAlso,  bind, Except.bind] at hv
      all_goals repeat' (split at hv <;> try simp_all [Lynx.Term.true])
      all_goals repeat' (split at * <;> try simp_all [])
      all_goals simp only [Erlang.erlang.«is_integer/1», Elixir.HoldLedger.Spec.«unique_keys?/1»,
        Lynx.Except.guard, Lynx.Except.tryWith] at *
      all_goals repeat' (split at * <;> try simp_all [Lynx.Term.true, Lynx.Term.false])
      all_goals exact ⟨_, _, _, _, _, by exact ⟨rfl, rfl, rfl, rfl, rfl⟩, by assumption, by assumption⟩
    obtain ⟨al, hl, ua, uh, es, rfl, hp, hu⟩ := shaped
    have hafter := step_valid _ event hv
    clear step_valid
    cases hs : Elixir.HoldLedger.Ledger.«step/2» (Lynx.Term.tuple #[Lynx.Term.integer al, Lynx.Term.integer hl, Lynx.Term.integer ua, Lynx.Term.integer uh, es]) event with
    | error err => simp [hs, bind, Except.bind] at hafter
    | ok out =>
      simp only [hs, bind, Except.bind] at hafter
      simp only [«po_b3:ensures/2», hs, bind, Except.bind]
      simp only [Elixir.HoldLedger.Ledger.«step/2»] at hs
      split at hs
      case h_1 ev k amount =>
        cases k <;> try simp [Elixir.HoldLedger.Ledger.«request/3», Erlang.erlang.«is_integer/1», Lynx.Except.guard, Lynx.Except.tryWith, Lynx.Except.andAlso,  bind, Except.bind, Lynx.Term.true, Lynx.Term.false] at hs
        all_goals try (subst out; solve | simp_all [Elixir.HoldLedger.Spec.«effects_valid?/5», Elixir.HoldLedger.Spec.«consistent_effects?/5»,

            Elixir.HoldLedger.Spec.«not_applied_result?/1»,
            Erlang.erlang.«element/2»,   Erlang.erlang.«==/2», Erlang.erlang.«/=/2», HoldLedgerProof.atom_compare,

              Lynx.Except.andAlso,    Lynx.Term.true])
        all_goals cases amount <;> try simp [] at hs
        all_goals try (subst out; solve | simp_all [Elixir.HoldLedger.Spec.«effects_valid?/5», Elixir.HoldLedger.Spec.«consistent_effects?/5»,

            Elixir.HoldLedger.Spec.«not_applied_result?/1»,
            Erlang.erlang.«element/2»,   Erlang.erlang.«==/2», Erlang.erlang.«/=/2», HoldLedgerProof.atom_compare,

              Lynx.Except.andAlso,    Lynx.Term.true])
        rename_i n amountn
        rcases lookup_shape es n hp with ⟨hn, hl⟩ | ⟨a, st, hf, hl, hst⟩
        · try simp [hn] at hs
          all_goals subst_vars
          all_goals try simp_all [Elixir.HoldLedger.Spec.«effects_valid?/5», Elixir.HoldLedger.Spec.«consistent_effects?/5»,
            Elixir.HoldLedger.Spec.«authorize_intent?/6», Elixir.HoldLedger.Spec.«void_intent?/4»,
            Elixir.HoldLedger.Spec.«not_applied_result?/1», Elixir.HoldLedger.Spec.«applied_result?/1»,
            Erlang.erlang.«element/2»,   Erlang.erlang.«==/2», Erlang.erlang.«/=/2», HoldLedgerProof.atom_compare,
            Erlang.erlang.«>/2», Ordering.isGT_iff_eq_gt, Int.compare_eq_gt,
            Lynx.Except.guard, Lynx.Except.tryWith, Lynx.Except.andAlso,  bind, Except.bind, Lynx.Term.true, Lynx.Term.false]
          all_goals repeat' (split at * <;> (repeat' split_conjunction) <;> subst_vars <;> try simp_all [

                 HoldLedgerProof.atom_compare])
          all_goals repeat' split_conjunction
          all_goals subst_vars
          all_goals try simp_all [Elixir.HoldLedger.Spec.«effects_valid?/5», Elixir.HoldLedger.Spec.«consistent_effects?/5», Elixir.HoldLedger.Spec.«effect_valid?/2»,
            Elixir.HoldLedger.Spec.«authorize_intent?/6», Elixir.HoldLedger.Spec.«void_intent?/4»,
            Elixir.HoldLedger.Spec.«not_applied_result?/1», Elixir.HoldLedger.Spec.«applied_result?/1»,
            Erlang.erlang.«element/2», Erlang.erlang.«is_integer/1», Erlang.erlang.«=:=/2», Erlang.erlang.«==/2», Erlang.erlang.«/=/2», HoldLedgerProof.atom_compare, Erlang.erlang.«and/2», Erlang.erlang.«or/2», Erlang.erlang.«not/1»,
            Erlang.erlang.«>/2», Ordering.isGT_iff_eq_gt, Int.compare_eq_gt,
            Lynx.Except.guard, Lynx.Except.tryWith, Lynx.Except.andAlso, Lynx.Except.orElse, bind, Except.bind, Lynx.Term.true, Lynx.Term.false]
          all_goals try solve_by_elim (maxDepth := 20)
        · skip
          obtain ⟨pending, hpending, lpending⟩ := changed_lookup es (Lynx.Term.integer n) (Lynx.Term.integer a) st (Lynx.Term.atom "voiding") hp hl
          simp only [Elixir.HoldLedger.Spec.«known_status?/1», Elixir.HoldLedger.Spec.«holding?/1», Elixir.HoldLedger.Spec.«terminal?/1»] at hst
          repeat' (split at hst <;> try simp_all [Lynx.Term.true])
          all_goals subst_vars
          all_goals try simp_all [Elixir.HoldLedger.Spec.«effects_valid?/5», Elixir.HoldLedger.Spec.«consistent_effects?/5»,
            Elixir.HoldLedger.Spec.«authorize_intent?/6», Elixir.HoldLedger.Spec.«void_intent?/4»,
            Elixir.HoldLedger.Spec.«not_applied_result?/1», Elixir.HoldLedger.Spec.«applied_result?/1»,
            Erlang.erlang.«element/2»,  Erlang.erlang.«=:=/2», Erlang.erlang.«==/2», Erlang.erlang.«/=/2», HoldLedgerProof.atom_compare,
            Erlang.erlang.«>/2», Ordering.isGT_iff_eq_gt, Int.compare_eq_gt,
            Lynx.Except.guard, Lynx.Except.tryWith, Lynx.Except.andAlso,  bind, Except.bind, Lynx.Term.true, Lynx.Term.false]
          all_goals repeat' (split at * <;> (repeat' split_conjunction) <;> subst_vars <;> try simp_all [

                 HoldLedgerProof.atom_compare])
          all_goals repeat' split_conjunction
          all_goals subst_vars
          all_goals try simp_all [Elixir.HoldLedger.Spec.«effects_valid?/5», Elixir.HoldLedger.Spec.«consistent_effects?/5», Elixir.HoldLedger.Spec.«effect_valid?/2»,
            Elixir.HoldLedger.Spec.«authorize_intent?/6», Elixir.HoldLedger.Spec.«void_intent?/4»,
            Elixir.HoldLedger.Spec.«not_applied_result?/1», Elixir.HoldLedger.Spec.«applied_result?/1»,
            Erlang.erlang.«element/2», Erlang.erlang.«is_integer/1», Erlang.erlang.«=:=/2», Erlang.erlang.«==/2», Erlang.erlang.«/=/2», HoldLedgerProof.atom_compare, Erlang.erlang.«and/2», Erlang.erlang.«or/2», Erlang.erlang.«not/1»,
            Erlang.erlang.«>/2», Ordering.isGT_iff_eq_gt, Int.compare_eq_gt,
            Lynx.Except.guard, Lynx.Except.tryWith, Lynx.Except.andAlso, Lynx.Except.orElse, bind, Except.bind, Lynx.Term.true, Lynx.Term.false]
          all_goals try solve_by_elim (maxDepth := 20)
      case h_2 ev k =>
        cases k <;> try simp [Elixir.HoldLedger.Ledger.«dispatch/2»,      bind, Except.bind] at hs
        all_goals try (subst out; solve | simp_all [Elixir.HoldLedger.Spec.«effects_valid?/5», Elixir.HoldLedger.Spec.«consistent_effects?/5»,

            Elixir.HoldLedger.Spec.«not_applied_result?/1»,
            Erlang.erlang.«element/2»,   Erlang.erlang.«==/2», Erlang.erlang.«/=/2», HoldLedgerProof.atom_compare,

              Lynx.Except.andAlso,    Lynx.Term.true])
        rename_i n
        rcases lookup_shape es n hp with ⟨hn, hl⟩ | ⟨a, st, hf, hl, hst⟩
        · try simp [hn] at hs
          all_goals subst_vars
          all_goals try simp_all [Elixir.HoldLedger.Spec.«effects_valid?/5», Elixir.HoldLedger.Spec.«consistent_effects?/5»,

            Elixir.HoldLedger.Spec.«not_applied_result?/1»,
            Erlang.erlang.«element/2»,   Erlang.erlang.«==/2», Erlang.erlang.«/=/2», HoldLedgerProof.atom_compare,

              Lynx.Except.andAlso,    Lynx.Term.true]
          all_goals repeat' (split at * <;> (repeat' split_conjunction) <;> subst_vars <;> try simp_all [Elixir.HoldLedger.Spec.«effects_valid?/5», Elixir.HoldLedger.Spec.«consistent_effects?/5», Elixir.HoldLedger.Spec.«effect_valid?/2»,
            Elixir.HoldLedger.Spec.«authorize_intent?/6», Elixir.HoldLedger.Spec.«void_intent?/4»,
            Elixir.HoldLedger.Spec.«not_applied_result?/1», Elixir.HoldLedger.Spec.«applied_result?/1»,
            Erlang.erlang.«element/2», Erlang.erlang.«is_integer/1», Erlang.erlang.«=:=/2», Erlang.erlang.«==/2», Erlang.erlang.«/=/2», HoldLedgerProof.atom_compare, Erlang.erlang.«and/2», Erlang.erlang.«or/2», Erlang.erlang.«not/1»,
            Erlang.erlang.«>/2», Ordering.isGT_iff_eq_gt, Int.compare_eq_gt,
            Lynx.Except.guard, Lynx.Except.tryWith, Lynx.Except.andAlso, Lynx.Except.orElse, bind, Except.bind, Lynx.Term.true, Lynx.Term.false])
          all_goals repeat' split_conjunction
          all_goals subst_vars
          all_goals try simp_all [Elixir.HoldLedger.Spec.«effects_valid?/5», Elixir.HoldLedger.Spec.«consistent_effects?/5», Elixir.HoldLedger.Spec.«effect_valid?/2»,
            Elixir.HoldLedger.Spec.«authorize_intent?/6», Elixir.HoldLedger.Spec.«void_intent?/4»,
            Elixir.HoldLedger.Spec.«not_applied_result?/1», Elixir.HoldLedger.Spec.«applied_result?/1»,
            Erlang.erlang.«element/2», Erlang.erlang.«is_integer/1», Erlang.erlang.«=:=/2», Erlang.erlang.«==/2», Erlang.erlang.«/=/2», HoldLedgerProof.atom_compare, Erlang.erlang.«and/2», Erlang.erlang.«or/2», Erlang.erlang.«not/1»,
            Erlang.erlang.«>/2», Ordering.isGT_iff_eq_gt, Int.compare_eq_gt,
            Lynx.Except.guard, Lynx.Except.tryWith, Lynx.Except.andAlso, Lynx.Except.orElse, bind, Except.bind, Lynx.Term.true, Lynx.Term.false]
          all_goals try solve_by_elim (maxDepth := 20)
        · obtain ⟨changed, hm, hlook⟩ := changed_lookup es (Lynx.Term.integer n) (Lynx.Term.integer a) st (Lynx.Term.atom "sent") hp hl
          obtain ⟨pending, hpending, lpending⟩ := changed_lookup es (Lynx.Term.integer n) (Lynx.Term.integer a) st (Lynx.Term.atom "voiding") hp hl
          simp only [Elixir.HoldLedger.Spec.«known_status?/1», Elixir.HoldLedger.Spec.«holding?/1», Elixir.HoldLedger.Spec.«terminal?/1»] at hst
          repeat' (split at hst <;> try simp_all [Lynx.Term.true])
          all_goals subst_vars
          all_goals try simp_all [Elixir.HoldLedger.Spec.«effects_valid?/5», Elixir.HoldLedger.Spec.«consistent_effects?/5», Elixir.HoldLedger.Spec.«effect_valid?/2»,
            Elixir.HoldLedger.Spec.«authorize_intent?/6»,
            Elixir.HoldLedger.Spec.«not_applied_result?/1»,
            Erlang.erlang.«element/2»,  Erlang.erlang.«=:=/2», Erlang.erlang.«==/2», Erlang.erlang.«/=/2», HoldLedgerProof.atom_compare, Erlang.erlang.«and/2»,

              Lynx.Except.andAlso,    Lynx.Term.true, Lynx.Term.false]
          all_goals repeat' (split at * <;> (repeat' split_conjunction) <;> subst_vars <;> try simp_all [Elixir.HoldLedger.Spec.«effects_valid?/5», Elixir.HoldLedger.Spec.«consistent_effects?/5», Elixir.HoldLedger.Spec.«effect_valid?/2»,
            Elixir.HoldLedger.Spec.«authorize_intent?/6», Elixir.HoldLedger.Spec.«void_intent?/4»,
            Elixir.HoldLedger.Spec.«not_applied_result?/1», Elixir.HoldLedger.Spec.«applied_result?/1»,
            Erlang.erlang.«element/2», Erlang.erlang.«is_integer/1», Erlang.erlang.«=:=/2», Erlang.erlang.«==/2», Erlang.erlang.«/=/2», HoldLedgerProof.atom_compare, Erlang.erlang.«and/2», Erlang.erlang.«or/2», Erlang.erlang.«not/1»,
            Erlang.erlang.«>/2», Ordering.isGT_iff_eq_gt, Int.compare_eq_gt,
            Lynx.Except.guard, Lynx.Except.tryWith, Lynx.Except.andAlso, Lynx.Except.orElse, bind, Except.bind, Lynx.Term.true, Lynx.Term.false])
          all_goals repeat' split_conjunction
          all_goals subst_vars
          all_goals try simp_all [Elixir.HoldLedger.Spec.«effects_valid?/5», Elixir.HoldLedger.Spec.«consistent_effects?/5», Elixir.HoldLedger.Spec.«effect_valid?/2»,
            Elixir.HoldLedger.Spec.«authorize_intent?/6», Elixir.HoldLedger.Spec.«void_intent?/4»,
            Elixir.HoldLedger.Spec.«not_applied_result?/1», Elixir.HoldLedger.Spec.«applied_result?/1»,
            Erlang.erlang.«element/2», Erlang.erlang.«is_integer/1», Erlang.erlang.«=:=/2», Erlang.erlang.«==/2», Erlang.erlang.«/=/2», HoldLedgerProof.atom_compare, Erlang.erlang.«and/2», Erlang.erlang.«or/2», Erlang.erlang.«not/1»,
            Erlang.erlang.«>/2», Ordering.isGT_iff_eq_gt, Int.compare_eq_gt,
            Lynx.Except.guard, Lynx.Except.tryWith, Lynx.Except.andAlso, Lynx.Except.orElse, bind, Except.bind, Lynx.Term.true, Lynx.Term.false]
          all_goals try solve_by_elim (maxDepth := 20)
      case h_3 ev k =>
        cases k <;> try simp [Elixir.HoldLedger.Ledger.«timeout/2»,      bind, Except.bind] at hs
        all_goals try (subst out; solve | simp_all [Elixir.HoldLedger.Spec.«effects_valid?/5», Elixir.HoldLedger.Spec.«consistent_effects?/5»,

            Elixir.HoldLedger.Spec.«not_applied_result?/1»,
            Erlang.erlang.«element/2»,   Erlang.erlang.«==/2», Erlang.erlang.«/=/2», HoldLedgerProof.atom_compare,

              Lynx.Except.andAlso,    Lynx.Term.true])
        rename_i n
        rcases lookup_shape es n hp with ⟨hn, hl⟩ | ⟨a, st, hf, hl, hst⟩
        · try simp [hn] at hs
          all_goals subst_vars
          all_goals try simp_all [Elixir.HoldLedger.Spec.«effects_valid?/5», Elixir.HoldLedger.Spec.«consistent_effects?/5»,

            Elixir.HoldLedger.Spec.«not_applied_result?/1»,
            Erlang.erlang.«element/2»,   Erlang.erlang.«==/2», Erlang.erlang.«/=/2», HoldLedgerProof.atom_compare,

              Lynx.Except.andAlso,    Lynx.Term.true]
          all_goals repeat' (split at * <;> (repeat' split_conjunction) <;> subst_vars <;> try simp_all [Elixir.HoldLedger.Spec.«effects_valid?/5», Elixir.HoldLedger.Spec.«consistent_effects?/5», Elixir.HoldLedger.Spec.«effect_valid?/2»,
            Elixir.HoldLedger.Spec.«authorize_intent?/6», Elixir.HoldLedger.Spec.«void_intent?/4»,
            Elixir.HoldLedger.Spec.«not_applied_result?/1», Elixir.HoldLedger.Spec.«applied_result?/1»,
            Erlang.erlang.«element/2», Erlang.erlang.«is_integer/1», Erlang.erlang.«=:=/2», Erlang.erlang.«==/2», Erlang.erlang.«/=/2», HoldLedgerProof.atom_compare, Erlang.erlang.«and/2», Erlang.erlang.«or/2», Erlang.erlang.«not/1»,
            Erlang.erlang.«>/2», Ordering.isGT_iff_eq_gt, Int.compare_eq_gt,
            Lynx.Except.guard, Lynx.Except.tryWith, Lynx.Except.andAlso, Lynx.Except.orElse, bind, Except.bind, Lynx.Term.true, Lynx.Term.false])
          all_goals repeat' split_conjunction
          all_goals subst_vars
          all_goals try simp_all [Elixir.HoldLedger.Spec.«effects_valid?/5», Elixir.HoldLedger.Spec.«consistent_effects?/5», Elixir.HoldLedger.Spec.«effect_valid?/2»,
            Elixir.HoldLedger.Spec.«authorize_intent?/6», Elixir.HoldLedger.Spec.«void_intent?/4»,
            Elixir.HoldLedger.Spec.«not_applied_result?/1», Elixir.HoldLedger.Spec.«applied_result?/1»,
            Erlang.erlang.«element/2», Erlang.erlang.«is_integer/1», Erlang.erlang.«=:=/2», Erlang.erlang.«==/2», Erlang.erlang.«/=/2», HoldLedgerProof.atom_compare, Erlang.erlang.«and/2», Erlang.erlang.«or/2», Erlang.erlang.«not/1»,
            Erlang.erlang.«>/2», Ordering.isGT_iff_eq_gt, Int.compare_eq_gt,
            Lynx.Except.guard, Lynx.Except.tryWith, Lynx.Except.andAlso, Lynx.Except.orElse, bind, Except.bind, Lynx.Term.true, Lynx.Term.false]
          all_goals try solve_by_elim (maxDepth := 20)
        · obtain ⟨changed, hm, hlook⟩ := changed_lookup es (Lynx.Term.integer n) (Lynx.Term.integer a) st (Lynx.Term.atom "unknown") hp hl
          obtain ⟨pending, hpending, lpending⟩ := changed_lookup es (Lynx.Term.integer n) (Lynx.Term.integer a) st (Lynx.Term.atom "voiding") hp hl
          simp only [Elixir.HoldLedger.Spec.«known_status?/1», Elixir.HoldLedger.Spec.«holding?/1», Elixir.HoldLedger.Spec.«terminal?/1»] at hst
          repeat' (split at hst <;> try simp_all [Lynx.Term.true])
          all_goals subst_vars
          all_goals try simp_all [Elixir.HoldLedger.Spec.«effects_valid?/5», Elixir.HoldLedger.Spec.«consistent_effects?/5»,

            Elixir.HoldLedger.Spec.«not_applied_result?/1», Elixir.HoldLedger.Spec.«applied_result?/1»,
            Erlang.erlang.«element/2»,   Erlang.erlang.«==/2», Erlang.erlang.«/=/2», HoldLedgerProof.atom_compare,

              Lynx.Except.andAlso,    Lynx.Term.true, Lynx.Term.false]
          all_goals repeat' (split at * <;> (repeat' split_conjunction) <;> subst_vars <;> try simp_all [Elixir.HoldLedger.Spec.«effects_valid?/5», Elixir.HoldLedger.Spec.«consistent_effects?/5», Elixir.HoldLedger.Spec.«effect_valid?/2»,
            Elixir.HoldLedger.Spec.«authorize_intent?/6», Elixir.HoldLedger.Spec.«void_intent?/4»,
            Elixir.HoldLedger.Spec.«not_applied_result?/1», Elixir.HoldLedger.Spec.«applied_result?/1»,
            Erlang.erlang.«element/2», Erlang.erlang.«is_integer/1», Erlang.erlang.«=:=/2», Erlang.erlang.«==/2», Erlang.erlang.«/=/2», HoldLedgerProof.atom_compare, Erlang.erlang.«and/2», Erlang.erlang.«or/2», Erlang.erlang.«not/1»,
            Erlang.erlang.«>/2», Ordering.isGT_iff_eq_gt, Int.compare_eq_gt,
            Lynx.Except.guard, Lynx.Except.tryWith, Lynx.Except.andAlso, Lynx.Except.orElse, bind, Except.bind, Lynx.Term.true, Lynx.Term.false])
          all_goals repeat' split_conjunction
          all_goals subst_vars
          all_goals try simp_all [Elixir.HoldLedger.Spec.«effects_valid?/5», Elixir.HoldLedger.Spec.«consistent_effects?/5», Elixir.HoldLedger.Spec.«effect_valid?/2»,
            Elixir.HoldLedger.Spec.«authorize_intent?/6», Elixir.HoldLedger.Spec.«void_intent?/4»,
            Elixir.HoldLedger.Spec.«not_applied_result?/1», Elixir.HoldLedger.Spec.«applied_result?/1»,
            Erlang.erlang.«element/2», Erlang.erlang.«is_integer/1», Erlang.erlang.«=:=/2», Erlang.erlang.«==/2», Erlang.erlang.«/=/2», HoldLedgerProof.atom_compare, Erlang.erlang.«and/2», Erlang.erlang.«or/2», Erlang.erlang.«not/1»,
            Erlang.erlang.«>/2», Ordering.isGT_iff_eq_gt, Int.compare_eq_gt,
            Lynx.Except.guard, Lynx.Except.tryWith, Lynx.Except.andAlso, Lynx.Except.orElse, bind, Except.bind, Lynx.Term.true, Lynx.Term.false]
          all_goals try solve_by_elim (maxDepth := 20)
      case h_5 ev k =>
        cases k <;> try simp [Elixir.HoldLedger.Ledger.«retry/2»,      bind, Except.bind] at hs
        all_goals try (subst out; solve | simp_all [Elixir.HoldLedger.Spec.«effects_valid?/5», Elixir.HoldLedger.Spec.«consistent_effects?/5»,

            Elixir.HoldLedger.Spec.«not_applied_result?/1»,
            Erlang.erlang.«element/2»,   Erlang.erlang.«==/2», Erlang.erlang.«/=/2», HoldLedgerProof.atom_compare,

              Lynx.Except.andAlso,    Lynx.Term.true])
        rename_i n
        rcases lookup_shape es n hp with ⟨hn, hl⟩ | ⟨a, st, hf, hl, hst⟩
        · try simp [hn] at hs
          all_goals subst_vars
          all_goals try simp_all [Elixir.HoldLedger.Spec.«effects_valid?/5», Elixir.HoldLedger.Spec.«consistent_effects?/5»,

            Elixir.HoldLedger.Spec.«not_applied_result?/1»,
            Erlang.erlang.«element/2»,   Erlang.erlang.«==/2», Erlang.erlang.«/=/2», HoldLedgerProof.atom_compare,

              Lynx.Except.andAlso,    Lynx.Term.true]
          all_goals repeat' (split at * <;> (repeat' split_conjunction) <;> subst_vars <;> try simp_all [Elixir.HoldLedger.Spec.«effects_valid?/5», Elixir.HoldLedger.Spec.«consistent_effects?/5», Elixir.HoldLedger.Spec.«effect_valid?/2»,
            Elixir.HoldLedger.Spec.«authorize_intent?/6», Elixir.HoldLedger.Spec.«void_intent?/4»,
            Elixir.HoldLedger.Spec.«not_applied_result?/1», Elixir.HoldLedger.Spec.«applied_result?/1»,
            Erlang.erlang.«element/2», Erlang.erlang.«is_integer/1», Erlang.erlang.«=:=/2», Erlang.erlang.«==/2», Erlang.erlang.«/=/2», HoldLedgerProof.atom_compare, Erlang.erlang.«and/2», Erlang.erlang.«or/2», Erlang.erlang.«not/1»,
            Erlang.erlang.«>/2», Ordering.isGT_iff_eq_gt, Int.compare_eq_gt,
            Lynx.Except.guard, Lynx.Except.tryWith, Lynx.Except.andAlso, Lynx.Except.orElse, bind, Except.bind, Lynx.Term.true, Lynx.Term.false])
          all_goals repeat' split_conjunction
          all_goals subst_vars
          all_goals try simp_all [Elixir.HoldLedger.Spec.«effects_valid?/5», Elixir.HoldLedger.Spec.«consistent_effects?/5», Elixir.HoldLedger.Spec.«effect_valid?/2»,
            Elixir.HoldLedger.Spec.«authorize_intent?/6», Elixir.HoldLedger.Spec.«void_intent?/4»,
            Elixir.HoldLedger.Spec.«not_applied_result?/1», Elixir.HoldLedger.Spec.«applied_result?/1»,
            Erlang.erlang.«element/2», Erlang.erlang.«is_integer/1», Erlang.erlang.«=:=/2», Erlang.erlang.«==/2», Erlang.erlang.«/=/2», HoldLedgerProof.atom_compare, Erlang.erlang.«and/2», Erlang.erlang.«or/2», Erlang.erlang.«not/1»,
            Erlang.erlang.«>/2», Ordering.isGT_iff_eq_gt, Int.compare_eq_gt,
            Lynx.Except.guard, Lynx.Except.tryWith, Lynx.Except.andAlso, Lynx.Except.orElse, bind, Except.bind, Lynx.Term.true, Lynx.Term.false]
          all_goals try solve_by_elim (maxDepth := 20)
        · obtain ⟨changed, hm, hlook⟩ := changed_lookup es (Lynx.Term.integer n) (Lynx.Term.integer a) st (Lynx.Term.atom "sent") hp hl
          obtain ⟨pending, hpending, lpending⟩ := changed_lookup es (Lynx.Term.integer n) (Lynx.Term.integer a) st (Lynx.Term.atom "voiding") hp hl
          simp only [Elixir.HoldLedger.Spec.«known_status?/1», Elixir.HoldLedger.Spec.«holding?/1», Elixir.HoldLedger.Spec.«terminal?/1»] at hst
          repeat' (split at hst <;> try simp_all [Lynx.Term.true])
          all_goals subst_vars
          all_goals try simp_all [Elixir.HoldLedger.Spec.«effects_valid?/5», Elixir.HoldLedger.Spec.«consistent_effects?/5», Elixir.HoldLedger.Spec.«effect_valid?/2»,
            Elixir.HoldLedger.Spec.«authorize_intent?/6»,
            Elixir.HoldLedger.Spec.«not_applied_result?/1»,
            Erlang.erlang.«element/2»,  Erlang.erlang.«=:=/2», Erlang.erlang.«==/2», Erlang.erlang.«/=/2», HoldLedgerProof.atom_compare, Erlang.erlang.«and/2»,

              Lynx.Except.andAlso,    Lynx.Term.true, Lynx.Term.false]
          all_goals repeat' (split at * <;> (repeat' split_conjunction) <;> subst_vars <;> try simp_all [Elixir.HoldLedger.Spec.«effects_valid?/5», Elixir.HoldLedger.Spec.«consistent_effects?/5», Elixir.HoldLedger.Spec.«effect_valid?/2»,
            Elixir.HoldLedger.Spec.«authorize_intent?/6», Elixir.HoldLedger.Spec.«void_intent?/4»,
            Elixir.HoldLedger.Spec.«not_applied_result?/1», Elixir.HoldLedger.Spec.«applied_result?/1»,
            Erlang.erlang.«element/2», Erlang.erlang.«is_integer/1», Erlang.erlang.«=:=/2», Erlang.erlang.«==/2», Erlang.erlang.«/=/2», HoldLedgerProof.atom_compare, Erlang.erlang.«and/2», Erlang.erlang.«or/2», Erlang.erlang.«not/1»,
            Erlang.erlang.«>/2», Ordering.isGT_iff_eq_gt, Int.compare_eq_gt,
            Lynx.Except.guard, Lynx.Except.tryWith, Lynx.Except.andAlso, Lynx.Except.orElse, bind, Except.bind, Lynx.Term.true, Lynx.Term.false])
          all_goals repeat' split_conjunction
          all_goals subst_vars
          all_goals try simp_all [Elixir.HoldLedger.Spec.«effects_valid?/5», Elixir.HoldLedger.Spec.«consistent_effects?/5», Elixir.HoldLedger.Spec.«effect_valid?/2»,
            Elixir.HoldLedger.Spec.«authorize_intent?/6», Elixir.HoldLedger.Spec.«void_intent?/4»,
            Elixir.HoldLedger.Spec.«not_applied_result?/1», Elixir.HoldLedger.Spec.«applied_result?/1»,
            Erlang.erlang.«element/2», Erlang.erlang.«is_integer/1», Erlang.erlang.«=:=/2», Erlang.erlang.«==/2», Erlang.erlang.«/=/2», HoldLedgerProof.atom_compare, Erlang.erlang.«and/2», Erlang.erlang.«or/2», Erlang.erlang.«not/1»,
            Erlang.erlang.«>/2», Ordering.isGT_iff_eq_gt, Int.compare_eq_gt,
            Lynx.Except.guard, Lynx.Except.tryWith, Lynx.Except.andAlso, Lynx.Except.orElse, bind, Except.bind, Lynx.Term.true, Lynx.Term.false]
          all_goals try solve_by_elim (maxDepth := 20)
      case h_6 ev k outcome =>
        cases k <;> try simp [Elixir.HoldLedger.Ledger.«processor_result/3», Erlang.erlang.«is_integer/1»,   Lynx.Except.andAlso,  bind, Except.bind, Lynx.Term.true, Lynx.Term.false] at hs
        all_goals try (subst out; solve | simp_all [Elixir.HoldLedger.Spec.«effects_valid?/5», Elixir.HoldLedger.Spec.«consistent_effects?/5»,

            Elixir.HoldLedger.Spec.«not_applied_result?/1»,
            Erlang.erlang.«element/2»,   Erlang.erlang.«==/2», Erlang.erlang.«/=/2», HoldLedgerProof.atom_compare,

              Lynx.Except.andAlso,    Lynx.Term.true])
        rename_i n
        rcases lookup_shape es n hp with ⟨hn, hl⟩ | ⟨a, st, hf, hl, hst⟩
        · try simp [hn] at hs
          all_goals subst_vars
          all_goals try simp_all [Elixir.HoldLedger.Spec.«effects_valid?/5», Elixir.HoldLedger.Spec.«consistent_effects?/5»,
            Elixir.HoldLedger.Spec.«authorize_intent?/6», Elixir.HoldLedger.Spec.«void_intent?/4»,
            Elixir.HoldLedger.Spec.«not_applied_result?/1», Elixir.HoldLedger.Spec.«applied_result?/1»,
            Erlang.erlang.«element/2»,   Erlang.erlang.«==/2», Erlang.erlang.«/=/2», HoldLedgerProof.atom_compare,

            Lynx.Except.guard, Lynx.Except.tryWith, Lynx.Except.andAlso,  bind, Except.bind, Lynx.Term.true, Lynx.Term.false]
          all_goals repeat' (split at * <;> (repeat' split_conjunction) <;> subst_vars <;> try simp_all [

                 HoldLedgerProof.atom_compare])
          all_goals repeat' split_conjunction
          all_goals subst_vars
          all_goals try simp_all [Elixir.HoldLedger.Spec.«effects_valid?/5», Elixir.HoldLedger.Spec.«consistent_effects?/5», Elixir.HoldLedger.Spec.«effect_valid?/2»,
            Elixir.HoldLedger.Spec.«authorize_intent?/6», Elixir.HoldLedger.Spec.«void_intent?/4»,
            Elixir.HoldLedger.Spec.«not_applied_result?/1», Elixir.HoldLedger.Spec.«applied_result?/1»,
            Erlang.erlang.«element/2», Erlang.erlang.«is_integer/1», Erlang.erlang.«=:=/2», Erlang.erlang.«==/2», Erlang.erlang.«/=/2», HoldLedgerProof.atom_compare, Erlang.erlang.«and/2», Erlang.erlang.«or/2», Erlang.erlang.«not/1»,
            Erlang.erlang.«>/2», Ordering.isGT_iff_eq_gt, Int.compare_eq_gt,
            Lynx.Except.guard, Lynx.Except.tryWith, Lynx.Except.andAlso, Lynx.Except.orElse, bind, Except.bind, Lynx.Term.true, Lynx.Term.false]
          all_goals try solve_by_elim (maxDepth := 20)
        · obtain ⟨approved, hma, hla⟩ := changed_lookup es (Lynx.Term.integer n) (Lynx.Term.integer a) st (Lynx.Term.atom "authorized") hp hl
          obtain ⟨declined, hmd, hld⟩ := changed_lookup es (Lynx.Term.integer n) (Lynx.Term.integer a) st (Lynx.Term.atom "declined") hp hl
          obtain ⟨pending, hpending, lpending⟩ := changed_lookup es (Lynx.Term.integer n) (Lynx.Term.integer a) st (Lynx.Term.atom "voiding") hp hl
          simp only [Elixir.HoldLedger.Spec.«known_status?/1», Elixir.HoldLedger.Spec.«holding?/1», Elixir.HoldLedger.Spec.«terminal?/1»] at hst
          repeat' (split at hst <;> try simp_all [Lynx.Term.true])
          all_goals subst_vars
          all_goals try simp_all [Elixir.HoldLedger.Spec.«effects_valid?/5», Elixir.HoldLedger.Spec.«consistent_effects?/5»,
            Elixir.HoldLedger.Spec.«authorize_intent?/6», Elixir.HoldLedger.Spec.«void_intent?/4»,
            Elixir.HoldLedger.Spec.«not_applied_result?/1», Elixir.HoldLedger.Spec.«applied_result?/1»,
            Erlang.erlang.«element/2»,   Erlang.erlang.«==/2», Erlang.erlang.«/=/2», HoldLedgerProof.atom_compare,

            Lynx.Except.guard, Lynx.Except.tryWith, Lynx.Except.andAlso,  bind, Except.bind, Lynx.Term.true, Lynx.Term.false]
          all_goals repeat' (split at * <;> (repeat' split_conjunction) <;> subst_vars <;> try simp_all [

                 HoldLedgerProof.atom_compare])
          all_goals repeat' split_conjunction
          all_goals subst_vars
          all_goals try simp_all [Elixir.HoldLedger.Spec.«effects_valid?/5», Elixir.HoldLedger.Spec.«consistent_effects?/5», Elixir.HoldLedger.Spec.«effect_valid?/2»,
            Elixir.HoldLedger.Spec.«authorize_intent?/6», Elixir.HoldLedger.Spec.«void_intent?/4»,
            Elixir.HoldLedger.Spec.«not_applied_result?/1», Elixir.HoldLedger.Spec.«applied_result?/1»,
            Erlang.erlang.«element/2», Erlang.erlang.«is_integer/1», Erlang.erlang.«=:=/2», Erlang.erlang.«==/2», Erlang.erlang.«/=/2», HoldLedgerProof.atom_compare, Erlang.erlang.«and/2», Erlang.erlang.«or/2», Erlang.erlang.«not/1»,
            Erlang.erlang.«>/2», Ordering.isGT_iff_eq_gt, Int.compare_eq_gt,
            Lynx.Except.guard, Lynx.Except.tryWith, Lynx.Except.andAlso, Lynx.Except.orElse, bind, Except.bind, Lynx.Term.true, Lynx.Term.false]
          all_goals try solve_by_elim (maxDepth := 20)
      case h_7 ev k =>
        cases k <;> try simp [Elixir.HoldLedger.Ledger.«void/2»,       bind, Except.bind] at hs
        all_goals try (subst out; solve | simp_all [Elixir.HoldLedger.Spec.«effects_valid?/5», Elixir.HoldLedger.Spec.«consistent_effects?/5»,

            Elixir.HoldLedger.Spec.«not_applied_result?/1»,
            Erlang.erlang.«element/2»,   Erlang.erlang.«==/2», Erlang.erlang.«/=/2», HoldLedgerProof.atom_compare,

              Lynx.Except.andAlso,    Lynx.Term.true])
        rename_i n
        rcases lookup_shape es n hp with ⟨hn, hl⟩ | ⟨a, st, hf, hl, hst⟩
        · try simp [hn] at hs
          all_goals subst_vars
          all_goals try simp_all [Elixir.HoldLedger.Spec.«effects_valid?/5», Elixir.HoldLedger.Spec.«consistent_effects?/5»,

            Elixir.HoldLedger.Spec.«not_applied_result?/1»,
            Erlang.erlang.«element/2»,   Erlang.erlang.«==/2», Erlang.erlang.«/=/2», HoldLedgerProof.atom_compare,

              Lynx.Except.andAlso,    Lynx.Term.true]
          all_goals repeat' (split at * <;> (repeat' split_conjunction) <;> subst_vars <;> try simp_all [Elixir.HoldLedger.Spec.«effects_valid?/5», Elixir.HoldLedger.Spec.«consistent_effects?/5», Elixir.HoldLedger.Spec.«effect_valid?/2»,
            Elixir.HoldLedger.Spec.«authorize_intent?/6», Elixir.HoldLedger.Spec.«void_intent?/4»,
            Elixir.HoldLedger.Spec.«not_applied_result?/1», Elixir.HoldLedger.Spec.«applied_result?/1»,
            Erlang.erlang.«element/2», Erlang.erlang.«is_integer/1», Erlang.erlang.«=:=/2», Erlang.erlang.«==/2», Erlang.erlang.«/=/2», HoldLedgerProof.atom_compare, Erlang.erlang.«and/2», Erlang.erlang.«or/2», Erlang.erlang.«not/1»,
            Erlang.erlang.«>/2», Ordering.isGT_iff_eq_gt, Int.compare_eq_gt,
            Lynx.Except.guard, Lynx.Except.tryWith, Lynx.Except.andAlso, Lynx.Except.orElse, bind, Except.bind, Lynx.Term.true, Lynx.Term.false])
          all_goals repeat' split_conjunction
          all_goals subst_vars
          all_goals try simp_all [Elixir.HoldLedger.Spec.«effects_valid?/5», Elixir.HoldLedger.Spec.«consistent_effects?/5», Elixir.HoldLedger.Spec.«effect_valid?/2»,
            Elixir.HoldLedger.Spec.«authorize_intent?/6», Elixir.HoldLedger.Spec.«void_intent?/4»,
            Elixir.HoldLedger.Spec.«not_applied_result?/1», Elixir.HoldLedger.Spec.«applied_result?/1»,
            Erlang.erlang.«element/2», Erlang.erlang.«is_integer/1», Erlang.erlang.«=:=/2», Erlang.erlang.«==/2», Erlang.erlang.«/=/2», HoldLedgerProof.atom_compare, Erlang.erlang.«and/2», Erlang.erlang.«or/2», Erlang.erlang.«not/1»,
            Erlang.erlang.«>/2», Ordering.isGT_iff_eq_gt, Int.compare_eq_gt,
            Lynx.Except.guard, Lynx.Except.tryWith, Lynx.Except.andAlso, Lynx.Except.orElse, bind, Except.bind, Lynx.Term.true, Lynx.Term.false]
          all_goals try solve_by_elim (maxDepth := 20)
        · obtain ⟨changed, hm, hlook⟩ := changed_lookup es (Lynx.Term.integer n) (Lynx.Term.integer a) st (Lynx.Term.atom "voided") hp hl
          obtain ⟨pending, hpending, lpending⟩ := changed_lookup es (Lynx.Term.integer n) (Lynx.Term.integer a) st (Lynx.Term.atom "voiding") hp hl
          simp only [Elixir.HoldLedger.Spec.«known_status?/1», Elixir.HoldLedger.Spec.«holding?/1», Elixir.HoldLedger.Spec.«terminal?/1»] at hst
          repeat' (split at hst <;> try simp_all [Lynx.Term.true])
          all_goals subst_vars
          all_goals try simp_all [Elixir.HoldLedger.Spec.«effects_valid?/5», Elixir.HoldLedger.Spec.«consistent_effects?/5»,
             Elixir.HoldLedger.Spec.«void_intent?/4»,
            Elixir.HoldLedger.Spec.«not_applied_result?/1», Elixir.HoldLedger.Spec.«applied_result?/1»,
            Erlang.erlang.«element/2»,  Erlang.erlang.«=:=/2», Erlang.erlang.«==/2», Erlang.erlang.«/=/2», HoldLedgerProof.atom_compare,

              Lynx.Except.andAlso,    Lynx.Term.true, Lynx.Term.false]
          all_goals repeat' (split at * <;> (repeat' split_conjunction) <;> subst_vars <;> try simp_all [Elixir.HoldLedger.Spec.«effects_valid?/5», Elixir.HoldLedger.Spec.«consistent_effects?/5», Elixir.HoldLedger.Spec.«effect_valid?/2»,
            Elixir.HoldLedger.Spec.«authorize_intent?/6», Elixir.HoldLedger.Spec.«void_intent?/4»,
            Elixir.HoldLedger.Spec.«not_applied_result?/1», Elixir.HoldLedger.Spec.«applied_result?/1»,
            Erlang.erlang.«element/2», Erlang.erlang.«is_integer/1», Erlang.erlang.«=:=/2», Erlang.erlang.«==/2», Erlang.erlang.«/=/2», HoldLedgerProof.atom_compare, Erlang.erlang.«and/2», Erlang.erlang.«or/2», Erlang.erlang.«not/1»,
            Erlang.erlang.«>/2», Ordering.isGT_iff_eq_gt, Int.compare_eq_gt,
            Lynx.Except.guard, Lynx.Except.tryWith, Lynx.Except.andAlso, Lynx.Except.orElse, bind, Except.bind, Lynx.Term.true, Lynx.Term.false])
          all_goals repeat' split_conjunction
          all_goals subst_vars
          all_goals try simp_all [Elixir.HoldLedger.Spec.«effects_valid?/5», Elixir.HoldLedger.Spec.«consistent_effects?/5», Elixir.HoldLedger.Spec.«effect_valid?/2»,
            Elixir.HoldLedger.Spec.«authorize_intent?/6», Elixir.HoldLedger.Spec.«void_intent?/4»,
            Elixir.HoldLedger.Spec.«not_applied_result?/1», Elixir.HoldLedger.Spec.«applied_result?/1»,
            Erlang.erlang.«element/2», Erlang.erlang.«is_integer/1», Erlang.erlang.«=:=/2», Erlang.erlang.«==/2», Erlang.erlang.«/=/2», HoldLedgerProof.atom_compare, Erlang.erlang.«and/2», Erlang.erlang.«or/2», Erlang.erlang.«not/1»,
            Erlang.erlang.«>/2», Ordering.isGT_iff_eq_gt, Int.compare_eq_gt,
            Lynx.Except.guard, Lynx.Except.tryWith, Lynx.Except.andAlso, Lynx.Except.orElse, bind, Except.bind, Lynx.Term.true, Lynx.Term.false]
          all_goals try solve_by_elim (maxDepth := 20)
      case h_8 ev k =>
        cases k <;> try simp [Elixir.HoldLedger.Ledger.«void_confirmed/2»,      bind, Except.bind] at hs
        all_goals try (subst out; solve | simp_all [Elixir.HoldLedger.Spec.«effects_valid?/5», Elixir.HoldLedger.Spec.«consistent_effects?/5»,

            Elixir.HoldLedger.Spec.«not_applied_result?/1»,
            Erlang.erlang.«element/2»,   Erlang.erlang.«==/2», Erlang.erlang.«/=/2», HoldLedgerProof.atom_compare,

              Lynx.Except.andAlso,    Lynx.Term.true])
        rename_i n
        rcases lookup_shape es n hp with ⟨hn, hl⟩ | ⟨a, st, hf, hl, hst⟩
        · try simp [hn] at hs
          all_goals subst_vars
          all_goals try simp_all [Elixir.HoldLedger.Spec.«effects_valid?/5», Elixir.HoldLedger.Spec.«consistent_effects?/5»,

            Elixir.HoldLedger.Spec.«not_applied_result?/1»,
            Erlang.erlang.«element/2»,   Erlang.erlang.«==/2», Erlang.erlang.«/=/2», HoldLedgerProof.atom_compare,

              Lynx.Except.andAlso,    Lynx.Term.true]
          all_goals repeat' (split at * <;> (repeat' split_conjunction) <;> subst_vars <;> try simp_all [Elixir.HoldLedger.Spec.«effects_valid?/5», Elixir.HoldLedger.Spec.«consistent_effects?/5», Elixir.HoldLedger.Spec.«effect_valid?/2»,
            Elixir.HoldLedger.Spec.«authorize_intent?/6», Elixir.HoldLedger.Spec.«void_intent?/4»,
            Elixir.HoldLedger.Spec.«not_applied_result?/1», Elixir.HoldLedger.Spec.«applied_result?/1»,
            Erlang.erlang.«element/2», Erlang.erlang.«is_integer/1», Erlang.erlang.«=:=/2», Erlang.erlang.«==/2», Erlang.erlang.«/=/2», HoldLedgerProof.atom_compare, Erlang.erlang.«and/2», Erlang.erlang.«or/2», Erlang.erlang.«not/1»,
            Erlang.erlang.«>/2», Ordering.isGT_iff_eq_gt, Int.compare_eq_gt,
            Lynx.Except.guard, Lynx.Except.tryWith, Lynx.Except.andAlso, Lynx.Except.orElse, bind, Except.bind, Lynx.Term.true, Lynx.Term.false])
          all_goals repeat' split_conjunction
          all_goals subst_vars
          all_goals try simp_all [Elixir.HoldLedger.Spec.«effects_valid?/5», Elixir.HoldLedger.Spec.«consistent_effects?/5», Elixir.HoldLedger.Spec.«effect_valid?/2»,
            Elixir.HoldLedger.Spec.«authorize_intent?/6», Elixir.HoldLedger.Spec.«void_intent?/4»,
            Elixir.HoldLedger.Spec.«not_applied_result?/1», Elixir.HoldLedger.Spec.«applied_result?/1»,
            Erlang.erlang.«element/2», Erlang.erlang.«is_integer/1», Erlang.erlang.«=:=/2», Erlang.erlang.«==/2», Erlang.erlang.«/=/2», HoldLedgerProof.atom_compare, Erlang.erlang.«and/2», Erlang.erlang.«or/2», Erlang.erlang.«not/1»,
            Erlang.erlang.«>/2», Ordering.isGT_iff_eq_gt, Int.compare_eq_gt,
            Lynx.Except.guard, Lynx.Except.tryWith, Lynx.Except.andAlso, Lynx.Except.orElse, bind, Except.bind, Lynx.Term.true, Lynx.Term.false]
          all_goals try solve_by_elim (maxDepth := 20)
        · obtain ⟨changed, hm, hlook⟩ := changed_lookup es (Lynx.Term.integer n) (Lynx.Term.integer a) st (Lynx.Term.atom "voided") hp hl
          obtain ⟨pending, hpending, lpending⟩ := changed_lookup es (Lynx.Term.integer n) (Lynx.Term.integer a) st (Lynx.Term.atom "voiding") hp hl
          simp only [Elixir.HoldLedger.Spec.«known_status?/1», Elixir.HoldLedger.Spec.«holding?/1», Elixir.HoldLedger.Spec.«terminal?/1»] at hst
          repeat' (split at hst <;> try simp_all [Lynx.Term.true])
          all_goals subst_vars
          all_goals try simp_all [Elixir.HoldLedger.Spec.«effects_valid?/5», Elixir.HoldLedger.Spec.«consistent_effects?/5»,

            Elixir.HoldLedger.Spec.«not_applied_result?/1», Elixir.HoldLedger.Spec.«applied_result?/1»,
            Erlang.erlang.«element/2»,   Erlang.erlang.«==/2», Erlang.erlang.«/=/2», HoldLedgerProof.atom_compare,

              Lynx.Except.andAlso,    Lynx.Term.true, Lynx.Term.false]
          all_goals repeat' (split at * <;> (repeat' split_conjunction) <;> subst_vars <;> try simp_all [Elixir.HoldLedger.Spec.«effects_valid?/5», Elixir.HoldLedger.Spec.«consistent_effects?/5», Elixir.HoldLedger.Spec.«effect_valid?/2»,
            Elixir.HoldLedger.Spec.«authorize_intent?/6», Elixir.HoldLedger.Spec.«void_intent?/4»,
            Elixir.HoldLedger.Spec.«not_applied_result?/1», Elixir.HoldLedger.Spec.«applied_result?/1»,
            Erlang.erlang.«element/2», Erlang.erlang.«is_integer/1», Erlang.erlang.«=:=/2», Erlang.erlang.«==/2», Erlang.erlang.«/=/2», HoldLedgerProof.atom_compare, Erlang.erlang.«and/2», Erlang.erlang.«or/2», Erlang.erlang.«not/1»,
            Erlang.erlang.«>/2», Ordering.isGT_iff_eq_gt, Int.compare_eq_gt,
            Lynx.Except.guard, Lynx.Except.tryWith, Lynx.Except.andAlso, Lynx.Except.orElse, bind, Except.bind, Lynx.Term.true, Lynx.Term.false])
          all_goals repeat' split_conjunction
          all_goals subst_vars
          all_goals try simp_all [Elixir.HoldLedger.Spec.«effects_valid?/5», Elixir.HoldLedger.Spec.«consistent_effects?/5», Elixir.HoldLedger.Spec.«effect_valid?/2»,
            Elixir.HoldLedger.Spec.«authorize_intent?/6», Elixir.HoldLedger.Spec.«void_intent?/4»,
            Elixir.HoldLedger.Spec.«not_applied_result?/1», Elixir.HoldLedger.Spec.«applied_result?/1»,
            Erlang.erlang.«element/2», Erlang.erlang.«is_integer/1», Erlang.erlang.«=:=/2», Erlang.erlang.«==/2», Erlang.erlang.«/=/2», HoldLedgerProof.atom_compare, Erlang.erlang.«and/2», Erlang.erlang.«or/2», Erlang.erlang.«not/1»,
            Erlang.erlang.«>/2», Ordering.isGT_iff_eq_gt, Int.compare_eq_gt,
            Lynx.Except.guard, Lynx.Except.tryWith, Lynx.Except.andAlso, Lynx.Except.orElse, bind, Except.bind, Lynx.Term.true, Lynx.Term.false]
          all_goals try solve_by_elim (maxDepth := 20)
      case h_4  =>
        simp only [Elixir.HoldLedger.Ledger.«restart/1»,     bind, Except.bind] at hs
        all_goals subst_vars
        all_goals try simp_all [Elixir.HoldLedger.Spec.«effects_valid?/5», Elixir.HoldLedger.Spec.«consistent_effects?/5»,
          Elixir.HoldLedger.Spec.«authorize_intent?/6», Elixir.HoldLedger.Spec.«void_intent?/4»,
          Elixir.HoldLedger.Spec.«not_applied_result?/1», Elixir.HoldLedger.Spec.«applied_result?/1»,
          Erlang.erlang.«element/2»,   Erlang.erlang.«==/2», Erlang.erlang.«/=/2», HoldLedgerProof.atom_compare,

          Lynx.Except.guard, Lynx.Except.tryWith, Lynx.Except.andAlso,  bind, Except.bind, Lynx.Term.true, Lynx.Term.false]
        all_goals repeat' (split at * <;> (repeat' split_conjunction) <;> subst_vars <;> try simp_all [

               HoldLedgerProof.atom_compare])
        all_goals repeat' split_conjunction
        all_goals subst_vars
        all_goals try simp_all [Elixir.HoldLedger.Spec.«effects_valid?/5», Elixir.HoldLedger.Spec.«consistent_effects?/5», Elixir.HoldLedger.Spec.«effect_valid?/2»,
          Elixir.HoldLedger.Spec.«authorize_intent?/6», Elixir.HoldLedger.Spec.«void_intent?/4»,
          Elixir.HoldLedger.Spec.«not_applied_result?/1», Elixir.HoldLedger.Spec.«applied_result?/1»,
          Erlang.erlang.«element/2», Erlang.erlang.«is_integer/1», Erlang.erlang.«=:=/2», Erlang.erlang.«==/2», Erlang.erlang.«/=/2», HoldLedgerProof.atom_compare, Erlang.erlang.«and/2», Erlang.erlang.«or/2», Erlang.erlang.«not/1»,
          Erlang.erlang.«>/2», Ordering.isGT_iff_eq_gt, Int.compare_eq_gt,
          Lynx.Except.guard, Lynx.Except.tryWith, Lynx.Except.andAlso, Lynx.Except.orElse, bind, Except.bind, Lynx.Term.true, Lynx.Term.false]
        all_goals try solve_by_elim (maxDepth := 20)
      case h_9 ev k =>
        simp only [Elixir.HoldLedger.Ledger.«transport_ack/2»] at hs
        all_goals subst_vars
        all_goals try simp_all [Elixir.HoldLedger.Spec.«effects_valid?/5», Elixir.HoldLedger.Spec.«consistent_effects?/5»,
          Elixir.HoldLedger.Spec.«authorize_intent?/6», Elixir.HoldLedger.Spec.«void_intent?/4»,
          Elixir.HoldLedger.Spec.«not_applied_result?/1», Elixir.HoldLedger.Spec.«applied_result?/1»,
          Erlang.erlang.«element/2»,   Erlang.erlang.«==/2», Erlang.erlang.«/=/2», HoldLedgerProof.atom_compare,

          Lynx.Except.guard, Lynx.Except.tryWith, Lynx.Except.andAlso,  bind, Except.bind, Lynx.Term.true, Lynx.Term.false]
        all_goals repeat' (split at * <;> (repeat' split_conjunction) <;> subst_vars <;> try simp_all [

               HoldLedgerProof.atom_compare])
        all_goals repeat' split_conjunction
        all_goals subst_vars
        all_goals try simp_all [Elixir.HoldLedger.Spec.«effects_valid?/5», Elixir.HoldLedger.Spec.«consistent_effects?/5», Elixir.HoldLedger.Spec.«effect_valid?/2»,
          Elixir.HoldLedger.Spec.«authorize_intent?/6», Elixir.HoldLedger.Spec.«void_intent?/4»,
          Elixir.HoldLedger.Spec.«not_applied_result?/1», Elixir.HoldLedger.Spec.«applied_result?/1»,
          Erlang.erlang.«element/2», Erlang.erlang.«is_integer/1», Erlang.erlang.«=:=/2», Erlang.erlang.«==/2», Erlang.erlang.«/=/2», HoldLedgerProof.atom_compare, Erlang.erlang.«and/2», Erlang.erlang.«or/2», Erlang.erlang.«not/1»,
          Erlang.erlang.«>/2», Ordering.isGT_iff_eq_gt, Int.compare_eq_gt,
          Lynx.Except.guard, Lynx.Except.tryWith, Lynx.Except.andAlso, Lynx.Except.orElse, bind, Except.bind, Lynx.Term.true, Lynx.Term.false]
        all_goals try solve_by_elim (maxDepth := 20)
      case h_10 =>
        all_goals subst_vars
        all_goals try simp_all [Elixir.HoldLedger.Spec.«effects_valid?/5», Elixir.HoldLedger.Spec.«consistent_effects?/5», Elixir.HoldLedger.Spec.«effect_valid?/2»,
          Elixir.HoldLedger.Spec.«authorize_intent?/6», Elixir.HoldLedger.Spec.«void_intent?/4»,
          Elixir.HoldLedger.Spec.«not_applied_result?/1», Elixir.HoldLedger.Spec.«applied_result?/1»,
          Erlang.erlang.«element/2», Erlang.erlang.«is_integer/1», Erlang.erlang.«=:=/2», Erlang.erlang.«==/2», Erlang.erlang.«/=/2», HoldLedgerProof.atom_compare, Erlang.erlang.«and/2», Erlang.erlang.«or/2», Erlang.erlang.«not/1»,
          Erlang.erlang.«>/2», Ordering.isGT_iff_eq_gt, Int.compare_eq_gt,
          Lynx.Except.guard, Lynx.Except.tryWith, Lynx.Except.andAlso, Lynx.Except.orElse, bind, Except.bind, Lynx.Term.true, Lynx.Term.false]
        all_goals repeat' (split at * <;> (repeat' split_conjunction) <;> subst_vars <;> try simp_all [Elixir.HoldLedger.Spec.«effects_valid?/5», Elixir.HoldLedger.Spec.«consistent_effects?/5», Elixir.HoldLedger.Spec.«effect_valid?/2»,
          Elixir.HoldLedger.Spec.«authorize_intent?/6», Elixir.HoldLedger.Spec.«void_intent?/4»,
          Elixir.HoldLedger.Spec.«not_applied_result?/1», Elixir.HoldLedger.Spec.«applied_result?/1»,
          Erlang.erlang.«element/2»,  Erlang.erlang.«=:=/2», Erlang.erlang.«==/2», Erlang.erlang.«/=/2», HoldLedgerProof.atom_compare, Erlang.erlang.«and/2»,

          Lynx.Except.guard, Lynx.Except.tryWith, Lynx.Except.andAlso,  bind, Except.bind, Lynx.Term.true, Lynx.Term.false])
        all_goals repeat' split_conjunction
        all_goals subst_vars
        all_goals try simp_all [Elixir.HoldLedger.Spec.«effects_valid?/5», Elixir.HoldLedger.Spec.«consistent_effects?/5», Elixir.HoldLedger.Spec.«effect_valid?/2»,
          Elixir.HoldLedger.Spec.«authorize_intent?/6», Elixir.HoldLedger.Spec.«void_intent?/4»,
          Elixir.HoldLedger.Spec.«not_applied_result?/1», Elixir.HoldLedger.Spec.«applied_result?/1»,
          Erlang.erlang.«element/2», Erlang.erlang.«is_integer/1», Erlang.erlang.«=:=/2», Erlang.erlang.«==/2», Erlang.erlang.«/=/2», HoldLedgerProof.atom_compare, Erlang.erlang.«and/2», Erlang.erlang.«or/2», Erlang.erlang.«not/1»,
          Erlang.erlang.«>/2», Ordering.isGT_iff_eq_gt, Int.compare_eq_gt,
          Lynx.Except.guard, Lynx.Except.tryWith, Lynx.Except.andAlso, Lynx.Except.orElse, bind, Except.bind, Lynx.Term.true, Lynx.Term.false]
        all_goals try solve_by_elim (maxDepth := 20)
  have step_valid : ∀ s event, Elixir.HoldLedger.Spec.«valid?/1» s = Except.ok Lynx.Term.true →
      (do let output ← Elixir.HoldLedger.Ledger.«step/2» s event
          let next ← Erlang.erlang.«element/2» (Lynx.Term.integer 1) output
          Elixir.HoldLedger.Spec.«valid?/1» next) = Except.ok Lynx.Term.true := by
    intro s event requires
    exact «po_s/2» s event requires
  exact effects_correct step_valid s event requires

end Elixir.HoldLedger.ProofContracts
