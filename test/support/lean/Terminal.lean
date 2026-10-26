module

public import Elixir.HoldLedger.ProofContracts
public import HoldLedgerProof.CoreShape
public import HoldLedgerProof.CoreLookup
public import HoldLedgerProof.CorePreservation

public section
set_option maxHeartbeats 4000000
namespace HoldLedgerProof

theorem terminal_lookup (al hl ua uh : Int) (es event key stored amount frozen : Lynx.Term)
    (proper : Elixir.HoldLedger.Spec.«proper_entries?/1» es = Except.ok Lynx.Term.true)
    (terminal : frozen = Lynx.Term.atom "declined" ∨ frozen = Lynx.Term.atom "voided")
    (lookup : Elixir.HoldLedger.Spec.«lookup/2» es key =
      Except.ok (Lynx.Term.tuple #[Lynx.Term.atom "ok", Lynx.Term.tuple #[stored,amount,frozen]])) :
    (do let output ← Elixir.HoldLedger.Ledger.«step/2»
          (Lynx.Term.tuple #[Lynx.Term.integer al,Lynx.Term.integer hl,Lynx.Term.integer ua,Lynx.Term.integer uh,es]) event
        let next ← Erlang.erlang.«element/2» (Lynx.Term.integer 1) output
        let entries ← Erlang.erlang.«element/2» (Lynx.Term.integer 5) next
        Elixir.HoldLedger.Spec.«lookup/2» entries key) =
      Except.ok (Lynx.Term.tuple #[Lynx.Term.atom "ok", Lynx.Term.tuple #[stored,amount,frozen]]) := by
  have excluded : frozen ≠ Lynx.Term.atom "reserved" ∧ frozen ≠ Lynx.Term.atom "sent" ∧
      frozen ≠ Lynx.Term.atom "unknown" ∧ frozen ≠ Lynx.Term.atom "authorized" ∧ frozen ≠ Lynx.Term.atom "voiding" := by
    rcases terminal with rfl | rfl <;> simp
  obtain ⟨not_reserved, not_sent, not_unknown, not_authorized, not_voiding⟩ := excluded
  have find_eq (query : Lynx.Term) : Elixir.HoldLedger.Ledger.«find/2» es query = Elixir.HoldLedger.Spec.«lookup/2» es query := by
    obtain ⟨value,hf,hl⟩ := compatible_1 es query proper
    exact hf.trans hl.symm
  have alias_lookup (n : Int) (equal : (Lynx.Term.integer n).compare key = Ordering.eq) :
      Elixir.HoldLedger.Spec.«lookup/2» es (Lynx.Term.integer n) =
        Except.ok (Lynx.Term.tuple #[Lynx.Term.atom "ok", Lynx.Term.tuple #[stored,amount,frozen]]) := by
    rw [← lookup_equiv_1 es n key proper equal]
    exact lookup
  let changed (n : Int) (status : Lynx.Term) := Classical.choose (replaced_3 es n status proper)
  have change_eq (n : Int) (status : Lynx.Term) :
      Elixir.HoldLedger.Ledger.«set_status/3» es (Lynx.Term.integer n) status = Except.ok (changed n status) :=
    (Classical.choose_spec (replaced_3 es n status proper)).1
  have change_unrelated (n : Int) (status : Lynx.Term)
      (different : (Lynx.Term.integer n).compare key ≠ Ordering.eq) :
      Elixir.HoldLedger.Spec.«lookup/2» (changed n status) key =
        Except.ok (Lynx.Term.tuple #[Lynx.Term.atom "ok", Lynx.Term.tuple #[stored,amount,frozen]]) := by
    obtain ⟨newer,hl,unchanged | ⟨_,equal⟩⟩ :=
      (Classical.choose_spec (replaced_3 es n status proper)).2 key stored amount frozen lookup
    · simpa [unchanged] using hl
    · exact False.elim (different equal)
  have fresh_lookup (n : Int) (a : Lynx.Term)
      (different : (Lynx.Term.integer n).compare key ≠ Ordering.eq) :
      Elixir.HoldLedger.Spec.«lookup/2»
        (Lynx.Term.cons (Lynx.Term.tuple #[Lynx.Term.integer n,a,Lynx.Term.atom "reserved"]) es) key =
          Elixir.HoldLedger.Spec.«lookup/2» es key := by
    simp [Elixir.HoldLedger.Spec.«lookup/2», Erlang.erlang.«==/2», different]
  obtain ⟨restarted,hr,hm⟩ := marked_3 es proper
  obtain ⟨newer,hrestart,unchanged | ⟨bad,_⟩⟩ := hm key stored amount frozen lookup
  · have restart_lookup : Elixir.HoldLedger.Spec.«lookup/2» restarted key =
        Except.ok (Lynx.Term.tuple #[Lynx.Term.atom "ok", Lynx.Term.tuple #[stored,amount,frozen]]) := by
      simpa [unchanged] using hrestart
    clear_value changed
    clear hm hrestart unchanged terminal
    simp only [Elixir.HoldLedger.Ledger.«step/2»]
    split
    case h_1 ev query requested =>
      cases query <;> try simp [Elixir.HoldLedger.Ledger.«request/3», Erlang.erlang.«>=/2», Erlang.erlang.«>/2», Ordering.isGT_iff_eq_gt,  Erlang.erlang.«is_integer/1»,
        Erlang.erlang.«element/2», lookup, Lynx.Except.guard, Lynx.Except.tryWith, bind, Except.bind]
      rename_i n
      by_cases equal : (Lynx.Term.integer n).compare key = Ordering.eq
      · have same := alias_lookup n equal
        cases requested
        all_goals try simp_all [  Erlang.erlang.«=:=/2»]
        simp_all [    Int.compare_eq_gt]
        all_goals repeat' (split at * <;> (repeat' split_conjunction) <;> subst_vars <;> try simp_all [])
      · rcases lookup_shape_1 es (Lynx.Term.integer n) proper with absent | ⟨ek,av,status,found,known⟩
        all_goals simp_all [

               Erlang.erlang.«=:=/2»,
              Lynx.Term.true, Lynx.Term.false]
        all_goals repeat' (split at * <;> (repeat' split_conjunction) <;> subst_vars <;> try simp_all [])
        all_goals repeat' split_conjunction
        all_goals subst_vars
        all_goals try exact change_unrelated n _ equal
        all_goals try simp_all []
    case h_2 ev query =>
      cases query <;> try simp [Elixir.HoldLedger.Ledger.«dispatch/2»,
        Erlang.erlang.«element/2», lookup,   bind, Except.bind]
      rename_i n
      by_cases equal : (Lynx.Term.integer n).compare key = Ordering.eq
      · have same := alias_lookup n equal
        simp_all [
              Lynx.Term.true]
        all_goals repeat' (split <;> try simp_all [lookup, Erlang.erlang.«element/2», bind, Except.bind, Lynx.Term.true, Lynx.Term.false])
      · rcases lookup_shape_1 es (Lynx.Term.integer n) proper with absent | ⟨ek,av,status,found,known⟩
        all_goals simp_all [

              Lynx.Term.true]
        all_goals repeat' (split at * <;> (repeat' split_conjunction) <;> subst_vars <;> try simp_all [])
        all_goals repeat' split_conjunction
        all_goals subst_vars
        all_goals try exact change_unrelated n _ equal
        all_goals try simp_all [change_unrelated, fresh_lookup, lookup, Erlang.erlang.«element/2», bind, Except.bind]
    case h_3 ev query =>
      cases query <;> try simp [Elixir.HoldLedger.Ledger.«timeout/2»,
        Erlang.erlang.«element/2», lookup,   bind, Except.bind]
      rename_i n
      by_cases equal : (Lynx.Term.integer n).compare key = Ordering.eq
      · have same := alias_lookup n equal
        simp_all [
              Lynx.Term.true]
        all_goals repeat' (split <;> try simp_all [lookup, Erlang.erlang.«element/2», bind, Except.bind, Lynx.Term.true, Lynx.Term.false])
      · rcases lookup_shape_1 es (Lynx.Term.integer n) proper with absent | ⟨ek,av,status,found,known⟩
        all_goals simp_all [

              Lynx.Term.true]
        all_goals repeat' (split at * <;> (repeat' split_conjunction) <;> subst_vars <;> try simp_all [])
        all_goals repeat' split_conjunction
        all_goals subst_vars
        all_goals try exact change_unrelated n _ equal
        all_goals try simp_all [change_unrelated, fresh_lookup, lookup, Erlang.erlang.«element/2», bind, Except.bind]
    case h_5 ev query =>
      cases query <;> try simp [Elixir.HoldLedger.Ledger.«retry/2»,
        Erlang.erlang.«element/2», lookup,   bind, Except.bind]
      rename_i n
      by_cases equal : (Lynx.Term.integer n).compare key = Ordering.eq
      · have same := alias_lookup n equal
        simp_all [
              Lynx.Term.true]
        all_goals repeat' (split <;> try simp_all [lookup, Erlang.erlang.«element/2», bind, Except.bind, Lynx.Term.true, Lynx.Term.false])
      · rcases lookup_shape_1 es (Lynx.Term.integer n) proper with absent | ⟨ek,av,status,found,known⟩
        all_goals simp_all [

              Lynx.Term.true]
        all_goals repeat' (split at * <;> (repeat' split_conjunction) <;> subst_vars <;> try simp_all [])
        all_goals repeat' split_conjunction
        all_goals subst_vars
        all_goals try exact change_unrelated n _ equal
        all_goals try simp_all [change_unrelated, fresh_lookup, lookup, Erlang.erlang.«element/2», bind, Except.bind]
    case h_6 ev query outcome =>
      cases query <;> try simp [Elixir.HoldLedger.Ledger.«processor_result/3»,     Erlang.erlang.«is_integer/1»,
        Erlang.erlang.«element/2», lookup,   bind, Except.bind]
      rename_i n
      by_cases equal : (Lynx.Term.integer n).compare key = Ordering.eq
      · have same := alias_lookup n equal
        simp_all [
              Lynx.Term.true]
        all_goals repeat' (split at * <;> (repeat' split_conjunction) <;> subst_vars <;> try simp_all [])
      · rcases lookup_shape_1 es (Lynx.Term.integer n) proper with absent | ⟨ek,av,status,found,known⟩
        all_goals simp_all [

              Lynx.Term.true]
        all_goals repeat' (split at * <;> (repeat' split_conjunction) <;> subst_vars <;> try simp_all [])
        all_goals repeat' split_conjunction
        all_goals subst_vars
        all_goals try exact change_unrelated n _ equal
        all_goals try simp_all [change_unrelated, fresh_lookup, lookup, Erlang.erlang.«element/2», bind, Except.bind]
    case h_7 ev query =>
      cases query <;> try simp [Elixir.HoldLedger.Ledger.«void/2»,
        Erlang.erlang.«element/2», lookup,   bind, Except.bind]
      rename_i n
      by_cases equal : (Lynx.Term.integer n).compare key = Ordering.eq
      · have same := alias_lookup n equal
        simp_all [
              Lynx.Term.true]
        all_goals repeat' (split <;> try simp_all [lookup, Erlang.erlang.«element/2», bind, Except.bind, Lynx.Term.true, Lynx.Term.false])
      · rcases lookup_shape_1 es (Lynx.Term.integer n) proper with absent | ⟨ek,av,status,found,known⟩
        all_goals simp_all [

              Lynx.Term.true]
        all_goals repeat' (split at * <;> (repeat' split_conjunction) <;> subst_vars <;> try simp_all [])
        all_goals repeat' split_conjunction
        all_goals subst_vars
        all_goals try exact change_unrelated n _ equal
        all_goals try simp_all [change_unrelated, fresh_lookup, lookup, Erlang.erlang.«element/2», bind, Except.bind]
    case h_8 ev query =>
      cases query <;> try simp [Elixir.HoldLedger.Ledger.«void_confirmed/2»,
        Erlang.erlang.«element/2», lookup,   bind, Except.bind]
      rename_i n
      by_cases equal : (Lynx.Term.integer n).compare key = Ordering.eq
      · have same := alias_lookup n equal
        simp_all [
              Lynx.Term.true]
        all_goals repeat' (split <;> try simp_all [lookup, Erlang.erlang.«element/2», bind, Except.bind, Lynx.Term.true, Lynx.Term.false])
      · rcases lookup_shape_1 es (Lynx.Term.integer n) proper with absent | ⟨ek,av,status,found,known⟩
        all_goals simp_all [

              Lynx.Term.true]
        all_goals repeat' (split at * <;> (repeat' split_conjunction) <;> subst_vars <;> try simp_all [])
        all_goals repeat' split_conjunction
        all_goals subst_vars
        all_goals try exact change_unrelated n _ equal
        all_goals try simp_all [change_unrelated, fresh_lookup, lookup, Erlang.erlang.«element/2», bind, Except.bind]
    case h_4 =>
      simp [Elixir.HoldLedger.Ledger.«restart/1», hr, restart_lookup, Erlang.erlang.«element/2»]
    case h_9 ev query =>
      cases query <;> simp [Elixir.HoldLedger.Ledger.«transport_ack/2», lookup,
        Erlang.erlang.«element/2»]
    case h_10 => simp [lookup, Erlang.erlang.«element/2»]
  · exact False.elim (not_sent bad)

end HoldLedgerProof

namespace HoldLedgerProof

theorem lookup_compare_status (stored a st key amount : Lynx.Term) (tag : String) :
    (Lynx.Term.tuple #[Lynx.Term.atom "ok", Lynx.Term.tuple #[stored,a,st]]).compare
      (Lynx.Term.tuple #[Lynx.Term.atom "ok", Lynx.Term.tuple #[key,amount,Lynx.Term.atom tag]]) = Ordering.eq ↔
    stored.compare key = Ordering.eq ∧ a.compare amount = Ordering.eq ∧ st = Lynx.Term.atom tag := by
  rw [← atom_compare st tag]
  simp only [Lynx.Term.compare_tuple, List.compareLex, Ordering.then_eq_eq]
  cases hk : stored.compare key <;> cases ha : a.compare amount <;> cases hs : st.compare (Lynx.Term.atom tag) <;>
    simp_all [  atom_compare]

theorem terminal_comparison (s event key amount : Lynx.Term) (tag : String)
    (terminal : tag = "declined" ∨ tag = "voided")
    (valid : Elixir.HoldLedger.Spec.«valid?/1» s = Except.ok Lynx.Term.true)
    (before : (do let entries ← Erlang.erlang.«element/2» (Lynx.Term.integer 5) s
                  let found ← Elixir.HoldLedger.Spec.«lookup/2» entries key
                  Erlang.erlang.«==/2» found
                    (Lynx.Term.tuple #[Lynx.Term.atom "ok", Lynx.Term.tuple #[key,amount,Lynx.Term.atom tag]])) =
                Except.ok Lynx.Term.true) :
    (do let output ← Elixir.HoldLedger.Ledger.«step/2» s event
        let next ← Erlang.erlang.«element/2» (Lynx.Term.integer 1) output
        let entries ← Erlang.erlang.«element/2» (Lynx.Term.integer 5) next
        let found ← Elixir.HoldLedger.Spec.«lookup/2» entries key
        Erlang.erlang.«==/2» found
          (Lynx.Term.tuple #[Lynx.Term.atom "ok", Lynx.Term.tuple #[key,amount,Lynx.Term.atom tag]])) =
      Except.ok Lynx.Term.true := by
  obtain ⟨al,hl,ua,uh,es,rfl,hp,hu,ha,hc,hals,hhls,huas,huhs,hacap,hhcap⟩ := valid_view_1 s valid
  rcases lookup_shape_1 es key hp with absent | ⟨storedn,storedamt,old,found,known⟩
  · simp [Erlang.erlang.«element/2», absent, Erlang.erlang.«==/2», atom_tuple] at before
  · by_cases hkey : (Lynx.Term.integer storedn).compare key = Ordering.eq
    all_goals by_cases hamount : (Lynx.Term.integer storedamt).compare amount = Ordering.eq
    all_goals by_cases hold : old = Lynx.Term.atom tag
    all_goals simp [Erlang.erlang.«element/2», found, Erlang.erlang.«==/2», lookup_compare_status,
      hkey,hamount,hold,Lynx.Term.true,Lynx.Term.false] at before
    all_goals subst old
    all_goals
      have frozen : Lynx.Term.atom tag = Lynx.Term.atom "declined" ∨ Lynx.Term.atom tag = Lynx.Term.atom "voided" := by
        rcases terminal with rfl | rfl <;> simp
      have preserved := terminal_lookup al hl ua uh es event key (Lynx.Term.integer storedn)
        (Lynx.Term.integer storedamt) (Lynx.Term.atom tag) hp frozen found
      cases step : Elixir.HoldLedger.Ledger.«step/2»
          (Lynx.Term.tuple #[Lynx.Term.integer al,Lynx.Term.integer hl,Lynx.Term.integer ua,Lynx.Term.integer uh,es]) event with
      | error err => simp [step, bind, Except.bind] at preserved
      | ok output =>
        cases first : Erlang.erlang.«element/2» (Lynx.Term.integer 1) output with
        | error err => simp [step, first, bind, Except.bind] at preserved
        | ok next =>
          cases fifth : Erlang.erlang.«element/2» (Lynx.Term.integer 5) next with
          | error err => simp [step, first, fifth, bind, Except.bind] at preserved
          | ok entries =>
            have final_lookup : Elixir.HoldLedger.Spec.«lookup/2» entries key =
                Except.ok (Lynx.Term.tuple #[Lynx.Term.atom "ok", Lynx.Term.tuple #[Lynx.Term.integer storedn,Lynx.Term.integer storedamt,Lynx.Term.atom tag]]) := by
              simpa [step, first, fifth, bind, Except.bind] using preserved
            simp [first,fifth,final_lookup,Erlang.erlang.«==/2»,lookup_compare_status,hkey,hamount]

end HoldLedgerProof
