module

public import Elixir.HoldLedger.ProofContracts
public import HoldLedgerProof.Induction
public import HoldLedgerProof.CoreLookup
public import HoldLedgerProof.CorePreservation
public import HoldLedgerProof.Identity

public section
set_option maxHeartbeats 16000000
namespace Elixir.HoldLedger.ProofContracts

theorem «po_b2/4» (s event key amount : Lynx.Term)
    (requires : «po_b2:requires/4» s event key amount = Except.ok Lynx.Term.true) :
    «po_b2:ensures/4» s event key amount = Except.ok Lynx.Term.true := by
  have replaced := HoldLedgerProof.replaced_3
  have lookup_equiv := HoldLedgerProof.lookup_equiv_1
  have marked := HoldLedgerProof.marked_3
  have shape_lookup := HoldLedgerProof.lookup_shape_1
  have compatible := HoldLedgerProof.compatible_1
  have guarded : (∀ state ev, Elixir.HoldLedger.Spec.«valid?/1» state = Except.ok Lynx.Term.true →
      (do let output ← Elixir.HoldLedger.Ledger.«step/2» state ev
          let next ← Erlang.erlang.«element/2» (Lynx.Term.integer 1) output
          Elixir.HoldLedger.Spec.«identity_preserved?/2» state next) = Except.ok Lynx.Term.true) →
      «po_b2:ensures/4» s event key amount = Except.ok Lynx.Term.true := by
    intro identity_all
    have initial : Elixir.HoldLedger.Spec.«valid?/1» s = Except.ok Lynx.Term.true := by
      clear replaced lookup_equiv marked shape_lookup identity_all compatible
      simp only [«po_b2:requires/4», bind, Except.bind] at requires
      all_goals repeat' (split at * <;> try simp_all [Lynx.Term.true])
    have shaped : ∃ (al hl ua uh : Int) (es : Lynx.Term),
        s = Lynx.Term.tuple #[Lynx.Term.integer al, Lynx.Term.integer hl,
          Lynx.Term.integer ua, Lynx.Term.integer uh, es] ∧
        Elixir.HoldLedger.Spec.«proper_entries?/1» es = Except.ok Lynx.Term.true ∧
        Elixir.HoldLedger.Spec.«unique_keys_seen?/2» es Lynx.Term.nil = Except.ok Lynx.Term.true := by
      clear requires replaced lookup_equiv marked shape_lookup identity_all compatible key amount event
      simp only [Elixir.HoldLedger.Spec.«valid?/1», Elixir.HoldLedger.Spec.«nonnegative_state_valid?/5»,
        Lynx.Except.guard, Lynx.Except.tryWith, bind, Except.bind] at initial
      all_goals repeat' (split at initial <;> try simp_all [Lynx.Term.true])
      all_goals repeat' (split at * <;> try simp_all [])
      all_goals simp only [Erlang.erlang.«is_integer/1», Elixir.HoldLedger.Spec.«unique_keys?/1»,
        Lynx.Except.guard, Lynx.Except.tryWith, bind, Except.bind] at *
      all_goals repeat' (split at * <;> try simp_all [Lynx.Term.true, Lynx.Term.false])
      all_goals exact ⟨_, _, _, _, _, by exact ⟨rfl, rfl, rfl, rfl, rfl⟩, by assumption, by assumption⟩
    obtain ⟨al, hl, ua, uh, es, rfl, hp, hu⟩ := shaped
    have hidentity := identity_all _ event initial
    clear identity_all
    rcases shape_lookup es key hp with hn | ⟨storedn, storedamt, old, hlookup, hknown⟩
    · simp [«po_b2:requires/4», Erlang.erlang.«element/2», initial, hn,
        Erlang.erlang.«==/2», HoldLedgerProof.atom_tuple,
        Lynx.Term.true, Lynx.Term.false] at requires
    · by_cases hkey : (Lynx.Term.integer storedn).compare key = Ordering.eq
      all_goals by_cases hamount : (Lynx.Term.integer storedamt).compare amount = Ordering.eq
      all_goals by_cases hold : old = Lynx.Term.atom "unknown"
      all_goals by_cases happ : event.compare (Lynx.Term.tuple #[Lynx.Term.atom "processor_result",key,Lynx.Term.atom "approved"]) = Ordering.eq
      all_goals by_cases hdecl : event.compare (Lynx.Term.tuple #[Lynx.Term.atom "processor_result",key,Lynx.Term.atom "declined"]) = Ordering.eq
      all_goals simp [«po_b2:requires/4», Erlang.erlang.«element/2», initial, hlookup,
        Erlang.erlang.«==/2», Erlang.erlang.«/=/2», HoldLedgerProof.lookup_compare,
        hkey,hamount,hold,happ,hdecl,   Lynx.Term.true,Lynx.Term.false] at requires
      all_goals subst old
      all_goals
        have find_eq : ∀ k, Elixir.HoldLedger.Ledger.«find/2» es k = Elixir.HoldLedger.Spec.«lookup/2» es k := by
          intro k
          obtain ⟨v,hf,hl⟩ := compatible es k hp
          exact hf.trans hl.symm
        have alias_lookup : ∀ n : Int, (Lynx.Term.integer n).compare key = Ordering.eq →
            Elixir.HoldLedger.Spec.«lookup/2» es (Lynx.Term.integer n) =
              Except.ok (Lynx.Term.tuple #[Lynx.Term.atom "ok", Lynx.Term.tuple #[Lynx.Term.integer storedn,Lynx.Term.integer storedamt,Lynx.Term.atom "unknown"]]) := by
          intro n hc
          rw [← lookup_equiv es n key hp hc]
          exact hlookup
        let changed (n : Int) (st : Lynx.Term) := Classical.choose (replaced es n st hp)
        have change_eq (n : Int) (st : Lynx.Term) : Elixir.HoldLedger.Ledger.«set_status/3» es (Lynx.Term.integer n) st = Except.ok (changed n st) :=
          (Classical.choose_spec (replaced es n st hp)).1
        have change_lookup (n : Int) (st : Lynx.Term) : ∃ newer,
            Elixir.HoldLedger.Spec.«lookup/2» (changed n st) key = Except.ok
              (Lynx.Term.tuple #[Lynx.Term.atom "ok", Lynx.Term.tuple #[Lynx.Term.integer storedn,Lynx.Term.integer storedamt,newer]]) ∧
            (newer = Lynx.Term.atom "unknown" ∨ newer = st ∧ (Lynx.Term.integer n).compare key = Ordering.eq) :=
          (Classical.choose_spec (replaced es n st hp)).2 key _ _ _ hlookup
        have change_unrelated (n : Int) (st : Lynx.Term) (hne : (Lynx.Term.integer n).compare key ≠ Ordering.eq) :
            Elixir.HoldLedger.Spec.«lookup/2» (changed n st) key = Except.ok
              (Lynx.Term.tuple #[Lynx.Term.atom "ok", Lynx.Term.tuple #[Lynx.Term.integer storedn,Lynx.Term.integer storedamt,Lynx.Term.atom "unknown"]]) := by
          obtain ⟨newer,hl,hold | ⟨rfl,hc⟩⟩ := change_lookup n st
          · simpa [hold] using hl
          · exact False.elim (hne hc)
        have fresh_lookup (n a : Int) (hne : (Lynx.Term.integer n).compare key ≠ Ordering.eq) :
            Elixir.HoldLedger.Spec.«lookup/2»
              (Lynx.Term.cons (Lynx.Term.tuple #[Lynx.Term.integer n,Lynx.Term.integer a,Lynx.Term.atom "reserved"]) es) key =
                Elixir.HoldLedger.Spec.«lookup/2» es key := by
          simp [Elixir.HoldLedger.Spec.«lookup/2», Erlang.erlang.«==/2», hne]
        obtain ⟨restarted, hr, hmap⟩ := marked es hp
        obtain ⟨newer,hrestart,hrstatus⟩ := hmap key _ _ _ hlookup
        have restart_lookup : Elixir.HoldLedger.Spec.«lookup/2» restarted key = Except.ok
            (Lynx.Term.tuple #[Lynx.Term.atom "ok", Lynx.Term.tuple #[Lynx.Term.integer storedn,Lynx.Term.integer storedamt,Lynx.Term.atom "unknown"]]) := by
          rcases hrstatus with rfl | ⟨bad,_⟩
          · exact hrestart
          · simp at bad
        clear_value changed
        clear compatible replaced lookup_equiv marked hmap hrestart hrstatus
        cases hs : Elixir.HoldLedger.Ledger.«step/2»
            (Lynx.Term.tuple #[Lynx.Term.integer al,Lynx.Term.integer hl,Lynx.Term.integer ua,Lynx.Term.integer uh,es]) event with
        | error err => simp [hs,bind,Except.bind] at hidentity
        | ok out =>
          simp only [hs,bind,Except.bind] at hidentity
          simp only [«po_b2:ensures/4»,hs,bind,Except.bind]
          simp only [Elixir.HoldLedger.Ledger.«step/2»] at hs
          split at hs
          case h_1 ev k amountv =>
            cases k <;> try simp [*, Elixir.HoldLedger.Ledger.«request/3», Erlang.erlang.«is_integer/1»,Lynx.Except.guard,Lynx.Except.tryWith,bind,Except.bind,Lynx.Term.true,Lynx.Term.false] at hs
            all_goals try (subst out; solve | simp_all [
                Erlang.erlang.«element/2»,  Erlang.erlang.«==/2»,

                Lynx.Term.compare_tuple, List.compareLex,
                   Lynx.Term.true])
            all_goals cases amountv <;> try simp [*] at hs
            all_goals try (subst out; solve | simp_all [
                Erlang.erlang.«element/2»,  Erlang.erlang.«==/2»,

                Lynx.Term.compare_tuple, List.compareLex,
                   Lynx.Term.true])
            all_goals rename_i n amountn
            all_goals cases hc : (Lynx.Term.integer n).compare key
            all_goals try have halias := alias_lookup n (by assumption)
            all_goals rcases shape_lookup es (Lynx.Term.integer n) hp with hn | ⟨ek,av,st,hlk,hst⟩
            all_goals try simp [*,
                   Erlang.erlang.«=:=/2»,

                Erlang.erlang.«>/2», Ordering.isGT_iff_eq_gt, Int.compare_eq_gt,

                   Lynx.Term.true,Lynx.Term.false] at hs
            all_goals repeat' (split at hs <;> (repeat' split_conjunction) <;> subst_vars <;> try simp_all [
                Erlang.erlang.«element/2»,  Erlang.erlang.«==/2»,

                Lynx.Term.compare_tuple, List.compareLex,
                   Lynx.Term.true,Lynx.Term.false])
            all_goals try simp only [Except.ok.injEq] at hs
            all_goals subst_vars
            all_goals try simp only [] at hidentity ⊢
            all_goals try simp_all [

                Lynx.Term.compare_tuple, List.compareLex]
            all_goals try solve_by_elim (maxDepth := 20)
            all_goals repeat' split_conjunction
            all_goals subst_vars
            all_goals try simp_all [HoldLedgerProof.atom_compare, HoldLedgerProof.atom_compare_left, Lynx.Term.true,Lynx.Term.false]
            all_goals repeat' (split <;> try simp_all [Lynx.Term.true,Lynx.Term.false])
            all_goals cases hsent : (Lynx.Term.atom "sent").compare (Lynx.Term.atom "unknown") <;>
              try simp_all [Lynx.Term.true,Lynx.Term.false]
            all_goals skip
          case h_2 ev k =>
            cases k <;> try simp [*, Elixir.HoldLedger.Ledger.«dispatch/2», bind,Except.bind] at hs
            all_goals try (subst out; solve | simp_all [
                Erlang.erlang.«element/2»,  Erlang.erlang.«==/2»,

                Lynx.Term.compare_tuple, List.compareLex, Ordering.then_eq_eq,
                   Lynx.Term.true])
            all_goals rename_i n
            all_goals cases hc : (Lynx.Term.integer n).compare key
            all_goals try have halias := alias_lookup n (by assumption)
            all_goals rcases shape_lookup es (Lynx.Term.integer n) hp with hn | ⟨ek,av,st,hlk,hst⟩
            all_goals obtain ⟨newer,hlchange,hclass⟩ := change_lookup n (Lynx.Term.atom "sent")
            all_goals rcases hclass with rfl | ⟨rfl,_⟩
            all_goals try simp [*] at hs
            all_goals repeat' (split at hs <;> (repeat' split_conjunction) <;> subst_vars <;> try simp_all [
                Erlang.erlang.«element/2»,  Erlang.erlang.«==/2»,

                Lynx.Term.compare_tuple, List.compareLex, Ordering.then_eq_eq,
                   Lynx.Term.true,Lynx.Term.false])
            all_goals try simp only [Except.ok.injEq] at hs
            all_goals subst_vars
            all_goals try simp only [Erlang.erlang.«element/2»] at hidentity ⊢
            all_goals try simp_all [
                  Erlang.erlang.«==/2»,

                Lynx.Term.compare_tuple, List.compareLex, Ordering.then_eq_eq,
                   Lynx.Term.true,Lynx.Term.false]
            all_goals try solve_by_elim (maxDepth := 20)
            all_goals repeat' split_conjunction
            all_goals subst_vars
            all_goals try simp_all [HoldLedgerProof.atom_compare, HoldLedgerProof.atom_compare_left, Lynx.Term.true,Lynx.Term.false]
            all_goals repeat' (split <;> try simp_all [Lynx.Term.true,Lynx.Term.false])
            all_goals cases hsent : (Lynx.Term.atom "sent").compare (Lynx.Term.atom "unknown") <;>
              try simp_all [Lynx.Term.true,Lynx.Term.false]
            all_goals skip
          case h_3 ev k =>
            cases k <;> try simp [*, Elixir.HoldLedger.Ledger.«timeout/2», bind,Except.bind] at hs
            all_goals try (subst out; solve | simp_all [
                Erlang.erlang.«element/2»,  Erlang.erlang.«==/2»,

                Lynx.Term.compare_tuple, List.compareLex, Ordering.then_eq_eq,
                   Lynx.Term.true])
            all_goals rename_i n
            all_goals cases hc : (Lynx.Term.integer n).compare key
            all_goals try have halias := alias_lookup n (by assumption)
            all_goals rcases shape_lookup es (Lynx.Term.integer n) hp with hn | ⟨ek,av,st,hlk,hst⟩
            all_goals obtain ⟨newer,hlchange,hclass⟩ := change_lookup n (Lynx.Term.atom "unknown")
            all_goals rcases hclass with rfl | ⟨rfl,_⟩
            all_goals try simp [*] at hs
            all_goals repeat' (split at hs <;> (repeat' split_conjunction) <;> subst_vars <;> try simp_all [
                Erlang.erlang.«element/2»,  Erlang.erlang.«==/2»,

                Lynx.Term.compare_tuple, List.compareLex, Ordering.then_eq_eq,
                   Lynx.Term.true,Lynx.Term.false])
            all_goals try simp only [Except.ok.injEq] at hs
            all_goals subst_vars
            all_goals try simp only [Erlang.erlang.«element/2»] at hidentity ⊢
            all_goals try simp_all [
                  Erlang.erlang.«==/2»,

                Lynx.Term.compare_tuple, List.compareLex, Ordering.then_eq_eq,
                   Lynx.Term.true,Lynx.Term.false]
            all_goals try solve_by_elim (maxDepth := 20)
            all_goals repeat' split_conjunction
            all_goals subst_vars
            all_goals try simp_all [HoldLedgerProof.atom_compare, HoldLedgerProof.atom_compare_left, Lynx.Term.true,Lynx.Term.false]
            all_goals repeat' (split <;> try simp_all [Lynx.Term.true,Lynx.Term.false])
            all_goals cases hsent : (Lynx.Term.atom "sent").compare (Lynx.Term.atom "unknown") <;>
              try simp_all [Lynx.Term.true,Lynx.Term.false]
            all_goals skip
          case h_5 ev k =>
            cases k <;> try simp [*, Elixir.HoldLedger.Ledger.«retry/2», bind,Except.bind] at hs
            all_goals try (subst out; solve | simp_all [
                Erlang.erlang.«element/2»,  Erlang.erlang.«==/2»,

                Lynx.Term.compare_tuple, List.compareLex, Ordering.then_eq_eq,
                   Lynx.Term.true])
            all_goals rename_i n
            all_goals cases hc : (Lynx.Term.integer n).compare key
            all_goals try have halias := alias_lookup n (by assumption)
            all_goals rcases shape_lookup es (Lynx.Term.integer n) hp with hn | ⟨ek,av,st,hlk,hst⟩
            all_goals obtain ⟨newer,hlchange,hclass⟩ := change_lookup n (Lynx.Term.atom "sent")
            all_goals rcases hclass with rfl | ⟨rfl,_⟩
            all_goals try simp [*] at hs
            all_goals repeat' (split at hs <;> (repeat' split_conjunction) <;> subst_vars <;> try simp_all [
                Erlang.erlang.«element/2»,  Erlang.erlang.«==/2»,

                Lynx.Term.compare_tuple, List.compareLex, Ordering.then_eq_eq,
                   Lynx.Term.true,Lynx.Term.false])
            all_goals try simp only [Except.ok.injEq] at hs
            all_goals subst_vars
            all_goals try simp only [Erlang.erlang.«element/2»] at hidentity ⊢
            all_goals try simp_all [
                  Erlang.erlang.«==/2»,

                Lynx.Term.compare_tuple, List.compareLex, Ordering.then_eq_eq,
                   Lynx.Term.true,Lynx.Term.false]
            all_goals try solve_by_elim (maxDepth := 20)
            all_goals repeat' split_conjunction
            all_goals subst_vars
            all_goals try simp_all [HoldLedgerProof.atom_compare, HoldLedgerProof.atom_compare_left, Lynx.Term.true,Lynx.Term.false]
            all_goals repeat' (split <;> try simp_all [])
            all_goals cases hsent : (Lynx.Term.atom "sent").compare (Lynx.Term.atom "unknown") <;>
              try simp_all []
            all_goals skip
          case h_6 ev k outcome =>
            cases k <;> try simp [*, Elixir.HoldLedger.Ledger.«processor_result/3», Erlang.erlang.«is_integer/1»,bind,Except.bind,Lynx.Term.true,Lynx.Term.false] at hs
            all_goals try (subst out; solve | simp_all [
                Erlang.erlang.«element/2»,  Erlang.erlang.«==/2»,

                Lynx.Term.compare_tuple, List.compareLex,
                   Lynx.Term.true])
            all_goals rename_i n
            all_goals cases hc : (Lynx.Term.integer n).compare key
            all_goals try have halias := alias_lookup n (by assumption)
            all_goals rcases shape_lookup es (Lynx.Term.integer n) hp with hn | ⟨ek,av,st,hlk,hst⟩
            all_goals try simp [*] at hs
            all_goals repeat' (split at hs <;> (repeat' split_conjunction) <;> subst_vars <;> try simp_all [
                Erlang.erlang.«element/2»,  Erlang.erlang.«==/2»,

                Lynx.Term.compare_tuple, List.compareLex,
                   Lynx.Term.true,Lynx.Term.false])
            all_goals try simp only [Except.ok.injEq] at hs
            all_goals subst_vars
            all_goals try simp only [] at hidentity ⊢
            all_goals try simp_all [

                Lynx.Term.compare_tuple, List.compareLex]
            all_goals try solve_by_elim (maxDepth := 20)
            all_goals repeat' split_conjunction
            all_goals subst_vars
            all_goals try simp_all [HoldLedgerProof.atom_compare, HoldLedgerProof.atom_compare_left, Lynx.Term.true,Lynx.Term.false]
            all_goals repeat' (split <;> try simp_all [Lynx.Term.true,Lynx.Term.false])
            all_goals cases hsent : (Lynx.Term.atom "sent").compare (Lynx.Term.atom "unknown") <;>
              try simp_all [Lynx.Term.true,Lynx.Term.false]
            all_goals skip
          case h_7 ev k =>
            cases k <;> try simp [*, Elixir.HoldLedger.Ledger.«void/2»,  bind,Except.bind] at hs
            all_goals try (subst out; solve | simp_all [
                Erlang.erlang.«element/2»,  Erlang.erlang.«==/2»,

                Lynx.Term.compare_tuple, List.compareLex, Ordering.then_eq_eq,
                   Lynx.Term.true])
            all_goals rename_i n
            all_goals cases hc : (Lynx.Term.integer n).compare key
            all_goals try have halias := alias_lookup n (by assumption)
            all_goals rcases shape_lookup es (Lynx.Term.integer n) hp with hn | ⟨ek,av,st,hlk,hst⟩
            all_goals try simp [*] at hs
            all_goals repeat' (split at hs <;> (repeat' split_conjunction) <;> subst_vars <;> try simp_all [
                Erlang.erlang.«element/2»,  Erlang.erlang.«==/2»,

                Lynx.Term.compare_tuple, List.compareLex, Ordering.then_eq_eq,
                   Lynx.Term.true,Lynx.Term.false])
            all_goals try simp only [Except.ok.injEq] at hs
            all_goals subst_vars
            all_goals try simp only [Erlang.erlang.«element/2»] at hidentity ⊢
            all_goals try simp_all [
                  Erlang.erlang.«==/2»,

                Lynx.Term.compare_tuple, List.compareLex, Ordering.then_eq_eq,
                   Lynx.Term.true,Lynx.Term.false]
            all_goals try solve_by_elim (maxDepth := 20)
            all_goals repeat' split_conjunction
            all_goals subst_vars
            all_goals try simp_all [HoldLedgerProof.atom_compare, HoldLedgerProof.atom_compare_left, Lynx.Term.true,Lynx.Term.false]
            all_goals repeat' (split <;> try simp_all [Lynx.Term.true,Lynx.Term.false])
            all_goals cases hsent : (Lynx.Term.atom "sent").compare (Lynx.Term.atom "unknown") <;>
              try simp_all [Lynx.Term.true,Lynx.Term.false]
            all_goals skip
          case h_4 =>
            all_goals try simp [*, Elixir.HoldLedger.Ledger.«restart/1»] at hs
            all_goals repeat' (split at hs <;> subst_vars <;> try simp_all [hr,
                Erlang.erlang.«element/2», Erlang.erlang.«is_integer/1», Erlang.erlang.«==/2», Erlang.erlang.«=:=/2», Erlang.erlang.«/=/2»,
                Erlang.erlang.«and/2», Erlang.erlang.«or/2», HoldLedgerProof.lookup_compare,
                HoldLedgerProof.atom_compare, HoldLedgerProof.atom_compare_left,
                Erlang.erlang.«>/2», Ordering.isGT_iff_eq_gt, Int.compare_eq_gt,
                Lynx.Term.compare_tuple, List.compareLex, Ordering.then_eq_eq,
                Lynx.Except.guard, Lynx.Except.tryWith, bind, Except.bind,Lynx.Term.true,Lynx.Term.false])
            all_goals try simp only [Except.ok.injEq] at hs
            all_goals subst_vars
            all_goals try simp only [Erlang.erlang.«element/2»] at hidentity ⊢
            all_goals try simp_all [
                  Erlang.erlang.«==/2»,

                 HoldLedgerProof.atom_compare_left,

                Lynx.Term.compare_tuple, List.compareLex,
                   Lynx.Term.true]
            all_goals try solve_by_elim (maxDepth := 20)
            all_goals repeat' split_conjunction
            all_goals subst_vars
            all_goals try simp_all [HoldLedgerProof.atom_compare, HoldLedgerProof.atom_compare_left, Lynx.Term.true,Lynx.Term.false]
            all_goals repeat' (split <;> try simp_all [Lynx.Term.true,Lynx.Term.false])
            all_goals cases hsent : (Lynx.Term.atom "sent").compare (Lynx.Term.atom "unknown") <;>
              try simp_all [Lynx.Term.true,Lynx.Term.false]
            all_goals skip
          case h_8 ev k =>
            cases k <;> try simp [*, Elixir.HoldLedger.Ledger.«void_confirmed/2»,  bind,Except.bind] at hs
            all_goals try (subst out; solve | simp_all [
                Erlang.erlang.«element/2»,  Erlang.erlang.«==/2»,

                Lynx.Term.compare_tuple, List.compareLex, Ordering.then_eq_eq,
                   Lynx.Term.true])
            all_goals rename_i n
            all_goals cases hc : (Lynx.Term.integer n).compare key
            all_goals try have halias := alias_lookup n (by assumption)
            all_goals have hkeep := change_unrelated n (Lynx.Term.atom "voided")
            all_goals rcases shape_lookup es (Lynx.Term.integer n) hp with hn | ⟨ek,av,st,hlk,hst⟩
            all_goals try simp [*] at hs
            all_goals repeat' (split at hs <;> (repeat' split_conjunction) <;> subst_vars <;> try simp_all [
                Erlang.erlang.«element/2»,  Erlang.erlang.«==/2»,

                Lynx.Term.compare_tuple, List.compareLex, Ordering.then_eq_eq,
                   Lynx.Term.true,Lynx.Term.false])
            all_goals try simp only [Except.ok.injEq] at hs
            all_goals subst_vars
            all_goals try simp only [Erlang.erlang.«element/2»] at hidentity ⊢
            all_goals try simp_all [
                  Erlang.erlang.«==/2»,

                Lynx.Term.compare_tuple, List.compareLex, Ordering.then_eq_eq,
                   Lynx.Term.true,Lynx.Term.false]
            all_goals try solve_by_elim (maxDepth := 20)
            all_goals repeat' split_conjunction
            all_goals subst_vars
            all_goals try simp_all [HoldLedgerProof.atom_compare, HoldLedgerProof.atom_compare_left, Lynx.Term.true,Lynx.Term.false]
            all_goals repeat' (split <;> try simp_all [Lynx.Term.true,Lynx.Term.false])
            all_goals cases hsent : (Lynx.Term.atom "sent").compare (Lynx.Term.atom "unknown") <;>
              try simp_all [Lynx.Term.true,Lynx.Term.false]
            all_goals skip
          case h_9 =>
            all_goals try simp [*, Elixir.HoldLedger.Ledger.«transport_ack/2»] at hs
            all_goals repeat' (split at hs <;> subst_vars <;> try simp_all [
                Erlang.erlang.«element/2»,  Erlang.erlang.«==/2»,

                Lynx.Term.compare_tuple, List.compareLex, Ordering.then_eq_eq,
                   Lynx.Term.true,Lynx.Term.false])
            all_goals try simp only [Except.ok.injEq] at hs
            all_goals subst_vars
            all_goals try simp only [] at hidentity ⊢
            all_goals try simp_all [

                Lynx.Term.compare_tuple, List.compareLex]
            all_goals try solve_by_elim (maxDepth := 20)
            all_goals repeat' split_conjunction
            all_goals subst_vars
            all_goals try simp_all [HoldLedgerProof.atom_compare, HoldLedgerProof.atom_compare_left, Lynx.Term.true,Lynx.Term.false]
            all_goals repeat' (split <;> try simp_all [Lynx.Term.true,Lynx.Term.false])
            all_goals cases hsent : (Lynx.Term.atom "sent").compare (Lynx.Term.atom "unknown") <;>
              try simp_all [Lynx.Term.true,Lynx.Term.false]
            all_goals skip
          case h_10 =>
            simp only [pure,Except.pure,Except.ok.injEq] at hs
            subst out
            simpa [Erlang.erlang.«element/2»,bind,Except.bind,hlookup,hkey,hamount,
              HoldLedgerProof.lookup_compare,Erlang.erlang.«==/2»,Erlang.erlang.«and/2»,
              Lynx.Term.true,Lynx.Term.false] using hidentity
  have identity_all : ∀ s event, Elixir.HoldLedger.Spec.«valid?/1» s = Except.ok Lynx.Term.true →
      (do let output ← Elixir.HoldLedger.Ledger.«step/2» s event
          let next ← Erlang.erlang.«element/2» (Lynx.Term.integer 1) output
          Elixir.HoldLedger.Spec.«identity_preserved?/2» s next) = Except.ok Lynx.Term.true := by
    intro s event requires
    exact «po_b6/2» s event requires
  exact guarded identity_all

end Elixir.HoldLedger.ProofContracts
