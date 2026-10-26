module
public import Elixir.HoldLedger.ProofContracts
public import HoldLedgerProof.CoreShape
public import HoldLedgerProof.CoreLookup
public import HoldLedgerProof.CorePreservation
import all Lynx.Term.Compare

public section
set_option maxHeartbeats 16000000
namespace HoldLedgerProof

theorem retained_lookup (al hl ua uh k a : Int) (es old event : Lynx.Term)
    (proper : Elixir.HoldLedger.Spec.«proper_entries?/1» es = Except.ok Lynx.Term.true)
    (initial : Elixir.HoldLedger.Spec.«lookup/2» es (Lynx.Term.integer k) =
      Except.ok (Lynx.Term.tuple #[Lynx.Term.atom "ok", Lynx.Term.tuple #[Lynx.Term.integer k,Lynx.Term.integer a,old]]))
    (old_status : old = Lynx.Term.atom "sent" ∨ old = Lynx.Term.atom "unknown" ∨
      old = Lynx.Term.atom "authorized" ∨ old = Lynx.Term.atom "voiding")
    (no_decline : event ≠ Lynx.Term.tuple #[Lynx.Term.atom "processor_result", Lynx.Term.integer k, Lynx.Term.atom "declined"])
    (no_confirmation : event ≠ Lynx.Term.tuple #[Lynx.Term.atom "void_confirmed", Lynx.Term.integer k]) :
    (do let out ← Elixir.HoldLedger.Ledger.«step/2»
          (Lynx.Term.tuple #[.integer al,.integer hl,.integer ua,.integer uh,es]) event
        let next ← Erlang.erlang.«element/2» (.integer 1) out
        Elixir.HoldLedger.Spec.«exposed_entry?/3» next (.integer k) (.integer a)) = Except.ok Lynx.Term.true := by
  have find_eq (query : Lynx.Term) : Elixir.HoldLedger.Ledger.«find/2» es query =
      Elixir.HoldLedger.Spec.«lookup/2» es query := by
    obtain ⟨value,hf,hs⟩ := compatible_1 es query proper
    exact hf.trans hs.symm
  let changed (n : Int) (status : Lynx.Term) := Classical.choose (replaced_3 es n status proper)
  have change_eq (n : Int) (status : Lynx.Term) :
      Elixir.HoldLedger.Ledger.«set_status/3» es (.integer n) status = Except.ok (changed n status) :=
    (Classical.choose_spec (replaced_3 es n status proper)).1
  have change_lookup (n : Int) (status : Lynx.Term) : ∃ newer,
      Elixir.HoldLedger.Spec.«lookup/2» (changed n status) (.integer k) =
        Except.ok (.tuple #[.atom "ok",.tuple #[.integer k,.integer a,newer]]) ∧
      (newer = old ∨ newer = status ∧ (.integer n : Lynx.Term).compare (.integer k) = Ordering.eq) :=
    (Classical.choose_spec (replaced_3 es n status proper)).2 (.integer k) (.integer k) (.integer a) old initial
  obtain ⟨restarted,hr,hrmap⟩ := marked_3 es proper
  obtain ⟨restarted_status, restart_lookup, restart_cases⟩ := hrmap (.integer k) (.integer k) (.integer a) old initial
  have safe_old : old ≠ Lynx.Term.atom "reserved" := by
    rcases old_status with rfl | rfl | rfl | rfl <;> simp
  have same (x y : Lynx.Term) : Elixir.HoldLedger.Spec.«exposed_entry?/3»
      (Lynx.Term.tuple #[.integer al,.integer hl,x,y,es]) (.integer k) (.integer a) = Except.ok Lynx.Term.true := by
    rcases old_status with rfl | rfl | rfl | rfl <;>
      simp [Elixir.HoldLedger.Spec.«exposed_entry?/3», initial, Erlang.erlang.«=:=/2»,Erlang.erlang.«and/2»]
  have changed_safe (n : Int) (status : Lynx.Term)
      (safe : n ≠ k ∨ status = Lynx.Term.atom "sent" ∨ status = Lynx.Term.atom "unknown" ∨
        status = Lynx.Term.atom "authorized" ∨ status = Lynx.Term.atom "voiding") (x y : Lynx.Term) :
      Elixir.HoldLedger.Spec.«exposed_entry?/3»
        (Lynx.Term.tuple #[.integer al,.integer hl,x,y,changed n status]) (.integer k) (.integer a) = Except.ok Lynx.Term.true := by
    obtain ⟨newer, look, unchanged | ⟨new_status, equal⟩⟩ := change_lookup n status
    · rcases old_status with rfl | rfl | rfl | rfl <;>
        simp [Elixir.HoldLedger.Spec.«exposed_entry?/3»,look,unchanged,Erlang.erlang.«=:=/2»,Erlang.erlang.«and/2»]
    · have nk : n = k := by simpa [Lynx.Term.compare_integers,Int.compare_eq_eq] using equal
      rcases safe with different | rfl | rfl | rfl | rfl
      · exact False.elim (different nk)
      all_goals simp [Elixir.HoldLedger.Spec.«exposed_entry?/3»,look,new_status,
        Erlang.erlang.«=:=/2»,Erlang.erlang.«and/2»]
  have fresh_safe (n b : Int) (different : n ≠ k) (x y : Lynx.Term) :
      Elixir.HoldLedger.Spec.«exposed_entry?/3»
        (Lynx.Term.tuple #[.integer al,.integer hl,x,y,
          .cons (.tuple #[.integer n,.integer b,.atom "reserved"]) es]) (.integer k) (.integer a) = Except.ok Lynx.Term.true := by
    have unequal : (.integer n : Lynx.Term).compare (.integer k) ≠ Ordering.eq := by
      simpa [Lynx.Term.compare_integers,Int.compare_eq_eq] using different
    rcases old_status with rfl | rfl | rfl | rfl <;>
      simp [Elixir.HoldLedger.Spec.«exposed_entry?/3»,Elixir.HoldLedger.Spec.«lookup/2»,
        initial,different,Erlang.erlang.«==/2»,Erlang.erlang.«=:=/2»,Erlang.erlang.«and/2»]
  have restart_safe : Elixir.HoldLedger.Spec.«exposed_entry?/3»
      (Lynx.Term.tuple #[.integer al,.integer hl,.integer ua,.integer uh,restarted]) (.integer k) (.integer a) = Except.ok Lynx.Term.true := by
    rcases restart_cases with unchanged | ⟨was_sent,became_unknown⟩
    · rcases old_status with rfl | rfl | rfl | rfl <;>
        simp [Elixir.HoldLedger.Spec.«exposed_entry?/3»,restart_lookup,unchanged,
          Erlang.erlang.«=:=/2»,Erlang.erlang.«and/2»]
    · simp [Elixir.HoldLedger.Spec.«exposed_entry?/3»,restart_lookup,became_unknown,
        Erlang.erlang.«=:=/2»,Erlang.erlang.«and/2»]
  clear_value changed
  simp only [Elixir.HoldLedger.Ledger.«step/2»]
  split
  case h_1 ev query amount =>
    cases query <;> try simp [Elixir.HoldLedger.Ledger.«request/3», same, Erlang.erlang.«element/2»,Erlang.erlang.«is_integer/1»,Erlang.erlang.«=:=/2»,
        Erlang.erlang.«>/2»,Erlang.erlang.«>=/2»,
        Lynx.Except.guard,Lynx.Except.tryWith,bind,Except.bind,Lynx.Term.true,Lynx.Term.false]
    cases amount <;> try simp [ same,

        Lynx.Term.true]
    rename_i n b
    by_cases nk : n = k
    · subst n
      simp_all [

        Lynx.Term.true]
      all_goals rcases old_status with rfl | rfl | rfl | rfl <;> simp_all []
      all_goals repeat' (split at * <;> (repeat' split_conjunction) <;> subst_vars <;> try simp_all [])
      all_goals subst_vars
      all_goals try simp_all []
    · rcases lookup_shape_1 es (.integer n) proper with absent | ⟨stored,amt,status,found,known⟩
      all_goals simp_all [

        Lynx.Term.true]
      all_goals repeat' (split at * <;> (repeat' split_conjunction) <;> subst_vars <;> try simp_all [])
      all_goals subst_vars
      all_goals try simp_all []
  case h_2 ev query =>
    cases query <;> try simp [Elixir.HoldLedger.Ledger.«dispatch/2», same, Erlang.erlang.«element/2»,

        bind,Except.bind,Lynx.Term.true]
    rename_i n
    by_cases nk : n = k
    · subst n
      simp_all [

        Lynx.Term.true]
      all_goals rcases old_status with rfl | rfl | rfl | rfl <;> simp_all [Erlang.erlang.«element/2»,Erlang.erlang.«is_integer/1»,Erlang.erlang.«=:=/2»,Erlang.erlang.«and/2»,Erlang.erlang.«or/2»,
        Erlang.erlang.«==/2»,Erlang.erlang.«>/2»,Erlang.erlang.«>=/2»,
        Lynx.Except.guard,Lynx.Except.tryWith,bind,Except.bind,Lynx.Term.true,Lynx.Term.false]
      all_goals repeat' (split at * <;> (repeat' split_conjunction) <;> subst_vars <;> try simp_all [same, changed_safe, fresh_safe, Erlang.erlang.«element/2», bind, Except.bind, Lynx.Term.true, Lynx.Term.false])
      all_goals subst_vars
      all_goals try simp_all [same]
    · rcases lookup_shape_1 es (.integer n) proper with absent | ⟨stored,amt,status,found,known⟩
      all_goals simp_all [

        Lynx.Term.true]
      all_goals repeat' (split at * <;> (repeat' split_conjunction) <;> subst_vars <;> try simp_all [])
      all_goals subst_vars
      all_goals try simp_all []
  case h_3 ev query =>
    cases query <;> try simp [Elixir.HoldLedger.Ledger.«timeout/2», same, Erlang.erlang.«element/2»,

        bind,Except.bind,Lynx.Term.true]
    rename_i n
    by_cases nk : n = k
    · subst n
      simp_all [

        Lynx.Term.true]
      all_goals rcases old_status with rfl | rfl | rfl | rfl <;> simp_all []
      all_goals repeat' (split at * <;> (repeat' split_conjunction) <;> subst_vars <;> try simp_all [same, changed_safe, fresh_safe, Erlang.erlang.«element/2», bind, Except.bind, Lynx.Term.true, Lynx.Term.false])
      all_goals subst_vars
      all_goals try simp_all [same]
    · rcases lookup_shape_1 es (.integer n) proper with absent | ⟨stored,amt,status,found,known⟩
      all_goals simp_all [

        Lynx.Term.true]
      all_goals repeat' (split at * <;> (repeat' split_conjunction) <;> subst_vars <;> try simp_all [])
      all_goals subst_vars
      all_goals try simp_all []
  case h_5 ev query =>
    cases query <;> try simp [Elixir.HoldLedger.Ledger.«retry/2», same, Erlang.erlang.«element/2»,

        bind,Except.bind,Lynx.Term.true]
    rename_i n
    by_cases nk : n = k
    · subst n
      simp_all [

        Lynx.Term.true]
      all_goals rcases old_status with rfl | rfl | rfl | rfl <;> simp_all []
      all_goals repeat' (split at * <;> (repeat' split_conjunction) <;> subst_vars <;> try simp_all [same, changed_safe, fresh_safe, Erlang.erlang.«element/2», bind, Except.bind, Lynx.Term.true, Lynx.Term.false])
      all_goals subst_vars
      all_goals try simp_all [same]
    · rcases lookup_shape_1 es (.integer n) proper with absent | ⟨stored,amt,status,found,known⟩
      all_goals simp_all [

        Lynx.Term.true]
      all_goals repeat' (split at * <;> (repeat' split_conjunction) <;> subst_vars <;> try simp_all [])
      all_goals subst_vars
      all_goals try simp_all []
  case h_6 ev query outcome =>
    cases query <;> try simp [Elixir.HoldLedger.Ledger.«processor_result/3», same, Erlang.erlang.«element/2»,Erlang.erlang.«is_integer/1»,

        bind,Except.bind,Lynx.Term.true,Lynx.Term.false]
    rename_i n
    by_cases nk : n = k
    · subst n
      simp_all [

        Lynx.Term.true]
      all_goals rcases old_status with rfl | rfl | rfl | rfl <;> simp_all []
      all_goals repeat' (split at * <;> (repeat' split_conjunction) <;> subst_vars <;> try simp_all [])
      all_goals subst_vars
      all_goals try simp_all []
    · rcases lookup_shape_1 es (.integer n) proper with absent | ⟨stored,amt,status,found,known⟩
      all_goals simp_all [

        Lynx.Term.true]
      all_goals repeat' (split at * <;> (repeat' split_conjunction) <;> subst_vars <;> try simp_all [])
      all_goals subst_vars
      all_goals try simp_all []
  case h_7 ev query =>
    cases query <;> try simp [Elixir.HoldLedger.Ledger.«void/2», same, Erlang.erlang.«element/2»,

        bind,Except.bind,Lynx.Term.true]
    rename_i n
    by_cases nk : n = k
    · subst n
      simp_all [

        Lynx.Term.true]
      all_goals rcases old_status with rfl | rfl | rfl | rfl <;> simp_all []
      all_goals repeat' (split at * <;> (repeat' split_conjunction) <;> subst_vars <;> try simp_all [same, changed_safe, fresh_safe, Erlang.erlang.«element/2», bind, Except.bind, Lynx.Term.true, Lynx.Term.false])
      all_goals subst_vars
      all_goals try simp_all [same]
    · rcases lookup_shape_1 es (.integer n) proper with absent | ⟨stored,amt,status,found,known⟩
      all_goals simp_all [

        Lynx.Term.true]
      all_goals repeat' (split at * <;> (repeat' split_conjunction) <;> subst_vars <;> try simp_all [])
      all_goals subst_vars
      all_goals try simp_all []
  case h_8 ev query =>
    cases query <;> try simp [Elixir.HoldLedger.Ledger.«void_confirmed/2», same, Erlang.erlang.«element/2»,

        bind,Except.bind,Lynx.Term.true]
    rename_i n
    by_cases nk : n = k
    · subst n
      simp_all [

        Lynx.Term.true]
      all_goals rcases old_status with rfl | rfl | rfl | rfl <;> simp_all [Erlang.erlang.«element/2»,Erlang.erlang.«is_integer/1»,Erlang.erlang.«=:=/2»,Erlang.erlang.«and/2»,Erlang.erlang.«or/2»,
        Erlang.erlang.«==/2»,Erlang.erlang.«>/2»,Erlang.erlang.«>=/2»,
        Lynx.Except.guard,Lynx.Except.tryWith,bind,Except.bind,Lynx.Term.true,Lynx.Term.false]
      all_goals repeat' (split at * <;> (repeat' split_conjunction) <;> subst_vars <;> try simp_all [same, changed_safe, fresh_safe, Erlang.erlang.«element/2», bind, Except.bind, Lynx.Term.true, Lynx.Term.false])
      all_goals subst_vars
      all_goals try simp_all [same]
    · rcases lookup_shape_1 es (.integer n) proper with absent | ⟨stored,amt,status,found,known⟩
      all_goals simp_all [

        Lynx.Term.true]
      all_goals repeat' (split at * <;> (repeat' split_conjunction) <;> subst_vars <;> try simp_all [])
      all_goals subst_vars
      all_goals try simp_all []
  case h_4 => simp [Elixir.HoldLedger.Ledger.«restart/1»,hr,restart_safe,Erlang.erlang.«element/2»,

        Lynx.Term.true]
  case h_9 ev query =>
    cases query <;> simp [Elixir.HoldLedger.Ledger.«transport_ack/2»,same,Erlang.erlang.«element/2»,

        Lynx.Term.true]
  case h_10 => simp [same,Erlang.erlang.«element/2»,

        Lynx.Term.true]
end HoldLedgerProof

namespace Elixir.HoldLedger.ProofContracts

theorem «po_exposure_retain/5» (state event key amount status : Lynx.Term)
    (requires : «po_exposure_retain:requires/5» state event key amount status = Except.ok Lynx.Term.true) :
    «po_exposure_retain:ensures/5» state event key amount status = Except.ok Lynx.Term.true := by
  have valid : Elixir.HoldLedger.Spec.«valid?/1» state = Except.ok Lynx.Term.true := by
    simp only [«po_exposure_retain:requires/5»,bind,Except.bind] at requires
    repeat' (split at * <;> try simp_all [Erlang.erlang.«not/1», Lynx.Term.true,Lynx.Term.false])
  obtain ⟨al,hl,ua,uh,es,rfl,hp,hu,ha,hc,hal,hhl,hua,huh,hacap,hhcap⟩ := HoldLedgerProof.valid_view_1 state valid
  have shape := HoldLedgerProof.lookup_shape_1 es key hp
  rcases shape with absent | ⟨stored,amt,old,found,known⟩
  · have absent_compare : (Lynx.Term.atom "not_found").exactCompare
        (Lynx.Term.tuple #[Lynx.Term.atom "ok",Lynx.Term.tuple #[key,amount,status]]) = Ordering.lt := by
      rw [Lynx.Term.exactCompare_eq_step]
      rfl
    simp [«po_exposure_retain:requires/5»,valid,absent,absent_compare,Erlang.erlang.«element/2»,
      Erlang.erlang.«=:=/2»,bind,Except.bind,Lynx.Term.true,Lynx.Term.false] at requires
    all_goals repeat' (split at * <;> try simp_all [Erlang.erlang.«not/1», Lynx.Term.true,Lynx.Term.false])
  · simp only [«po_exposure_retain:requires/5»,Erlang.erlang.«element/2»,valid,bind,Except.bind] at requires
    repeat' (split at * <;> try simp_all [Erlang.erlang.«not/1», Lynx.Term.true,Lynx.Term.false])
    all_goals
      have equal : Erlang.erlang.«=:=/2»
        (Lynx.Term.tuple #[Lynx.Term.atom "ok",Lynx.Term.tuple #[Lynx.Term.integer stored,Lynx.Term.integer amt,old]])
        (Lynx.Term.tuple #[Lynx.Term.atom "ok",Lynx.Term.tuple #[key,amount,status]]) = Except.ok Lynx.Term.true := by assumption
      simp [Erlang.erlang.«=:=/2»,Lynx.Term.exactCompare_tuple,List.compareLex,
        Lynx.Term.true,Lynx.Term.false] at equal
      cases hk : (Lynx.Term.integer stored).exactCompare key <;> try simp only [hk] at equal
      all_goals try contradiction
      all_goals cases ham : (Lynx.Term.integer amt).exactCompare amount <;> try simp only [ham] at equal
      all_goals try contradiction
      all_goals cases hst : old.exactCompare status <;> try simp only [hst] at equal
      all_goals try contradiction
      all_goals have hkey := (Lynx.Term.integer_exactCompare_eq stored key).mp hk
      all_goals have hamount := (Lynx.Term.integer_exactCompare_eq amt amount).mp ham
      all_goals have hstatus := HoldLedgerProof.known_exact_1 old status known hst
      all_goals subst key
      all_goals subst amount
      all_goals subst status
      all_goals
        have protected_status : old = Lynx.Term.atom "sent" ∨ old = Lynx.Term.atom "unknown" ∨ old = Lynx.Term.atom "authorized" ∨ old = Lynx.Term.atom "voiding" := by
          simp_all [Erlang.erlang.«=:=/2»,Lynx.Term.true]
          all_goals by_cases hsent : old = Lynx.Term.atom "sent"
          all_goals by_cases hunknown : old = Lynx.Term.atom "unknown"
          all_goals by_cases hauth : old = Lynx.Term.atom "authorized"
          all_goals simp_all
        have no_decline : event ≠ Lynx.Term.tuple #[.atom "processor_result",.integer stored,.atom "declined"] := by
          intro bad
          subst event
          simp_all [Elixir.HoldLedger.Spec.«release_evidence?/2»,Erlang.erlang.«=:=/2»,
            Lynx.Term.true]
        have no_confirmation : event ≠ Lynx.Term.tuple #[.atom "void_confirmed",.integer stored] := by
          intro bad
          subst event
          simp_all [Elixir.HoldLedger.Spec.«release_evidence?/2»,Erlang.erlang.«=:=/2»,
            Lynx.Term.exactCompare_tuple,List.compareLex,Lynx.Term.true,Lynx.Term.false]
        exact HoldLedgerProof.retained_lookup al hl ua uh stored amt es old event hp found protected_status no_decline no_confirmation

end Elixir.HoldLedger.ProofContracts
