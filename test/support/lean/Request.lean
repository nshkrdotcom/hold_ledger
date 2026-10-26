module

public import Elixir.HoldLedger.ProofContracts
public import HoldLedgerProof.Induction
public import HoldLedgerProof.CoreAccounting
public import HoldLedgerProof.CoreLookup
public import HoldLedgerProof.CoreShape
public import HoldLedgerProof.CoreStructure

public section
set_option maxHeartbeats 16000000
namespace Elixir.HoldLedger.ProofContracts

theorem «po_i/2» (amount_limit hold_limit : Lynx.Term)
    (requires : «po_i:requires/2» amount_limit hold_limit = Except.ok Lynx.Term.true) :
    «po_i:ensures/2» amount_limit hold_limit = Except.ok Lynx.Term.true := by
  cases amount_limit <;> cases hold_limit <;>
    simp_all [«po_i:requires/2», Erlang.erlang.«is_integer/1»,
      Lynx.Term.true, Lynx.Term.false]
  all_goals repeat' (split at requires <;> simp_all [])
  all_goals simp_all [«po_i:ensures/2», Elixir.HoldLedger.Ledger.«init/2»,
    Elixir.HoldLedger.Spec.«valid?/1», Elixir.HoldLedger.Spec.«nonnegative_state_valid?/5»,
    Elixir.HoldLedger.Spec.«proper_entries?/1»,
    Elixir.HoldLedger.Spec.«unique_keys?/1»,
    Elixir.HoldLedger.Spec.«unique_keys_seen?/2»,
    Elixir.HoldLedger.Spec.«hold_amount/1», Elixir.HoldLedger.Spec.«hold_count/1»,
    Erlang.erlang.«is_integer/1», Erlang.erlang.«is_list/1»,
    Erlang.erlang.«==/2», Lynx.Term.true]

theorem «po_a1/3» (s key amount : Lynx.Term)
    (requires : «po_a1:requires/3» s key amount = Except.ok Lynx.Term.true) :
    «po_a1:ensures/3» s key amount = Except.ok Lynx.Term.true := by
  have compatible := HoldLedgerProof.compatible_3
  have totals := HoldLedgerProof.totals_1
  have seen_append := HoldLedgerProof.seen_append_1
  have fresh := HoldLedgerProof.fresh_4
  have valid_view := HoldLedgerProof.valid_view_1
  have insert_unique := HoldLedgerProof.insert_unique_1
  have hvalid : Elixir.HoldLedger.Spec.«valid?/1» s = Except.ok Lynx.Term.true := requires
  obtain ⟨al, hl, ua, uh, es, rfl, hp, hu, ha, hc, hal, hhl, hua, huh, hacap, hhcap⟩ := valid_view s hvalid
  obtain ⟨v, hf, _, hs⟩ := compatible es key hp
  clear requires compatible totals valid_view seen_append fresh
  rcases hs with rfl | ⟨ek, n, st, rfl⟩
  all_goals cases key <;>
    simp_all [«po_a1:ensures/3», Elixir.HoldLedger.Ledger.«request/3»,
      Erlang.erlang.«is_integer/1», Erlang.erlang.«element/2»,
      Erlang.erlang.«>/2», Ordering.isGT_iff_eq_gt,
      Lynx.Term.true, Lynx.Term.false]
  all_goals cases amount <;>
    simp_all [
       Int.compare_eq_gt]
  all_goals repeat' (split at * <;> try simp_all [])
  all_goals try simp_all [Erlang.erlang.«=:=/2»,
    Lynx.Term.true, Lynx.Term.false]
  all_goals repeat' (split at * <;> try simp_all [])
  all_goals simp_all [Elixir.HoldLedger.Spec.«valid?/1», Elixir.HoldLedger.Spec.«nonnegative_state_valid?/5»,
    Elixir.HoldLedger.Spec.«proper_entries?/1», Elixir.HoldLedger.Spec.«known_status?/1»,
    Elixir.HoldLedger.Spec.«holding?/1», Elixir.HoldLedger.Spec.«hold_amount/1»,
    Elixir.HoldLedger.Spec.«hold_count/1», Erlang.erlang.«is_integer/1»,
    Erlang.erlang.«==/2», Erlang.erlang.«>/2», Ordering.isGT_iff_eq_gt, Int.compare_eq_gt,
    Int.add_comm, Lynx.Term.true, Lynx.Term.false]
  all_goals repeat' (split at * <;> try simp_all [])
  all_goals omega

theorem «po_a2/3» (s key amount : Lynx.Term)
    (requires : «po_a2:requires/3» s key amount = Except.ok Lynx.Term.true) :
    «po_a2:ensures/3» s key amount = Except.ok Lynx.Term.true := by
  have compatible := HoldLedgerProof.compatible_1
  have totals := HoldLedgerProof.totals_1
  cases key <;>
    simp_all [«po_a2:requires/3», Elixir.HoldLedger.Spec.«request_eligible?/3»,
      Erlang.erlang.«is_integer/1», Lynx.Term.true, Lynx.Term.false]
  all_goals cases amount <;>
    simp_all []
  all_goals repeat' (split at requires <;> try simp_all [])
  all_goals simp [Erlang.erlang.«>/2», Ordering.isGT_iff_eq_gt, Int.compare_eq_gt,
      bind, Except.bind] at requires
  all_goals repeat' (split at requires <;> try simp_all [])
  all_goals try simp only [Elixir.HoldLedger.Spec.«valid?/1», Elixir.HoldLedger.Spec.«nonnegative_state_valid?/5»,
    Lynx.Except.guard, Lynx.Except.tryWith, bind, Except.bind] at requires
  all_goals repeat' (split at requires <;> try simp_all [Lynx.Term.true, Lynx.Term.false])
  all_goals repeat' (split at * <;> try simp_all [])
  all_goals simp only [Elixir.HoldLedger.Spec.«valid?/1», Elixir.HoldLedger.Spec.«nonnegative_state_valid?/5»,
    Lynx.Except.guard, Lynx.Except.tryWith, bind, Except.bind] at *
  all_goals repeat' (split at * <;> try simp_all [])
  all_goals simp only [Erlang.erlang.«is_integer/1», bind, Except.bind] at *
  all_goals repeat' (split at * <;> try simp_all [Lynx.Term.true, Lynx.Term.false])
  all_goals obtain ⟨⟨a, ha⟩, c, hc⟩ := totals _ (by assumption)
  all_goals simp_all [Erlang.erlang.«==/2»,
    Lynx.Term.true, Lynx.Term.false]
  all_goals repeat' (split at * <;> try simp_all [Lynx.Term.true, Lynx.Term.false])
  all_goals try simp_all [Lynx.Term.true, Lynx.Term.false]
  all_goals simp only [Elixir.HoldLedger.Spec.«has_key?/2», bind, Except.bind] at *
  all_goals repeat' (split at * <;> try simp_all [])
  all_goals subst_vars
  all_goals try simp_all [ Lynx.Term.true, Lynx.Term.false]
  have find_eq : ∀ es k, Elixir.HoldLedger.Spec.«proper_entries?/1» es = Except.ok Lynx.Term.true →
      Elixir.HoldLedger.Ledger.«find/2» es k = Elixir.HoldLedger.Spec.«lookup/2» es k := by
    intro es k hp
    obtain ⟨v, hf, hl⟩ := compatible es k hp
    exact hf.trans hl.symm
  all_goals simp_all [«po_a2:ensures/3», Elixir.HoldLedger.Ledger.«request/3»,
     Elixir.HoldLedger.Spec.«expected_step/2»,
    Elixir.HoldLedger.Spec.«expect_request/3», Elixir.HoldLedger.Spec.«restated/2»,
    Elixir.HoldLedger.Spec.«hold_amount/1», Elixir.HoldLedger.Spec.«hold_count/1»,
    Elixir.HoldLedger.Spec.«holding?/1», Erlang.erlang.«element/2»,
    Erlang.erlang.«is_integer/1», Erlang.erlang.«==/2», Erlang.erlang.«>/2»,
    Ordering.isGT_iff_eq_gt, Int.compare_eq_gt, Int.add_comm,
    Lynx.Term.true, Lynx.Term.false]
  all_goals repeat' (split at * <;> try simp_all [])
  all_goals omega

theorem «po_a3/2» (s event : Lynx.Term)
    (requires : «po_a3:requires/2» s event = Except.ok Lynx.Term.true) :
    «po_a3:ensures/2» s event = Except.ok Lynx.Term.true := by
  simp only [«po_a3:requires/2», «po_a3:ensures/2», Elixir.HoldLedger.Ledger.«step/2»,
    bind, Except.bind] at requires ⊢
  all_goals repeat' (split at * <;> try simp_all [Lynx.Term.true])
  all_goals simp only [Elixir.HoldLedger.Ledger.«request/3», Elixir.HoldLedger.Ledger.«dispatch/2»,
    Elixir.HoldLedger.Ledger.«timeout/2», Elixir.HoldLedger.Ledger.«restart/1»,
    Elixir.HoldLedger.Ledger.«retry/2», Elixir.HoldLedger.Ledger.«processor_result/3»,
    Elixir.HoldLedger.Ledger.«void/2», Elixir.HoldLedger.Ledger.«void_confirmed/2», Elixir.HoldLedger.Ledger.«transport_ack/2»,
    Elixir.HoldLedger.Spec.«not_applied_result?/1», Erlang.erlang.«element/2»,
    Erlang.erlang.«is_integer/1», Erlang.erlang.«==/2»,
    Lynx.Except.guard, Lynx.Except.tryWith, bind, Except.bind] at *
  all_goals repeat' (split at * <;> subst_vars <;> try simp_all [

        Lynx.Term.true, Lynx.Term.false])
  all_goals subst_vars
  all_goals try simp_all []
  all_goals try solve_by_elim (maxDepth := 20)

end Elixir.HoldLedger.ProofContracts
