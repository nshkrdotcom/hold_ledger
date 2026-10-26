module

public import Elixir.HoldLedger.ProofContracts
public import HoldLedgerProof.Induction
public import HoldLedgerProof.Step
public import HoldLedgerProof.Request

public section
set_option maxHeartbeats 16000000
namespace Elixir.HoldLedger.ProofContracts

theorem «po_c1/2» (s events : Lynx.Term)
    (requires : «po_c1:requires/2» s events = Except.ok Lynx.Term.true) :
    «po_c1:ensures/2» s events = Except.ok Lynx.Term.true := by
  have step_valid : ∀ s event, Elixir.HoldLedger.Spec.«valid?/1» s = Except.ok Lynx.Term.true →
      (do let output ← Elixir.HoldLedger.Ledger.«step/2» s event
          let next ← Erlang.erlang.«element/2» (Lynx.Term.integer 1) output
          Elixir.HoldLedger.Spec.«valid?/1» next) = Except.ok Lynx.Term.true := by
    intro s event requires
    exact «po_s/2» s event requires
  have replay : (∀ state ev, Elixir.HoldLedger.Spec.«valid?/1» state = Except.ok Lynx.Term.true →
      (do let output ← Elixir.HoldLedger.Ledger.«step/2» state ev
          let next ← Erlang.erlang.«element/2» (Lynx.Term.integer 1) output
          Elixir.HoldLedger.Spec.«valid?/1» next) = Except.ok Lynx.Term.true) →
      ∀ events state, Elixir.HoldLedger.Spec.«proper_events?/1» events = Except.ok Lynx.Term.true →
      Elixir.HoldLedger.Spec.«valid?/1» state = Except.ok Lynx.Term.true →
      ∃ out, Elixir.HoldLedger.Ledger.«run/2» state events = Except.ok out ∧
        Elixir.HoldLedger.Spec.«valid?/1» out = Except.ok Lynx.Term.true := by
    clear requires s events step_valid
    intro step_valid
    have step_shape : ∀ state ev out,
        Elixir.HoldLedger.Ledger.«step/2» state ev = Except.ok out →
        ∃ next result effects, out = Lynx.Term.tuple #[next,result,effects] := by
      clear step_valid
      intro state ev out hs
      simp only [Elixir.HoldLedger.Ledger.«step/2», Elixir.HoldLedger.Ledger.«request/3»,
        Elixir.HoldLedger.Ledger.«dispatch/2», Elixir.HoldLedger.Ledger.«timeout/2»,
        Elixir.HoldLedger.Ledger.«restart/1», Elixir.HoldLedger.Ledger.«retry/2»,
        Elixir.HoldLedger.Ledger.«processor_result/3», Elixir.HoldLedger.Ledger.«void/2», Elixir.HoldLedger.Ledger.«void_confirmed/2»,
        Elixir.HoldLedger.Ledger.«transport_ack/2»,
        Lynx.Except.guard, Lynx.Except.tryWith, bind, Except.bind] at hs
      all_goals repeat' (split at hs <;> try simp_all [])
      all_goals subst_vars
      all_goals first | exact ⟨_,_,_,rfl⟩ | exact ⟨_,_,_,by assumption⟩
    intro events state hp hv
    fun_induction Elixir.HoldLedger.Spec.«proper_events?/1» events generalizing state
    case case1 => exact ⟨state, rfl, hv⟩
    case case2 ev rest ih =>
      have htail : Elixir.HoldLedger.Spec.«proper_events?/1» rest = Except.ok Lynx.Term.true := hp
      have hsvalid := step_valid state ev hv
      cases hs : Elixir.HoldLedger.Ledger.«step/2» state ev with
      | error err => simp [hs, bind, Except.bind] at hsvalid
      | ok out =>
        obtain ⟨next, result, effects, rfl⟩ := step_shape state ev out hs
        have hvnext : Elixir.HoldLedger.Spec.«valid?/1» next = Except.ok Lynx.Term.true := by
          simpa [hs, Erlang.erlang.«element/2», bind, Except.bind] using hsvalid
        obtain ⟨final, hr, hfinal⟩ := ih next htail hvnext
        refine ⟨final, ?_, hfinal⟩
        simpa [Elixir.HoldLedger.Ledger.«run/2», hs, bind, Except.bind] using hr
    case case3 => simp [ Lynx.Term.true] at hp
  have replay_valid := replay step_valid
  clear replay step_valid
  simp only [«po_c1:requires/2», bind, Except.bind] at requires
  all_goals repeat' (split at requires <;> try simp_all [Lynx.Term.true])
  all_goals obtain ⟨out, hr, hv⟩ := replay_valid events s (by assumption) (by assumption)
  all_goals simp [«po_c1:ensures/2», hr, hv]

theorem «po_c2/3» (amount_limit hold_limit events : Lynx.Term)
    (requires : «po_c2:requires/3» amount_limit hold_limit events = Except.ok Lynx.Term.true) :
    «po_c2:ensures/3» amount_limit hold_limit events = Except.ok Lynx.Term.true := by
  have step_valid : ∀ s event, Elixir.HoldLedger.Spec.«valid?/1» s = Except.ok Lynx.Term.true →
      (do let output ← Elixir.HoldLedger.Ledger.«step/2» s event
          let next ← Erlang.erlang.«element/2» (Lynx.Term.integer 1) output
          Elixir.HoldLedger.Spec.«valid?/1» next) = Except.ok Lynx.Term.true := by
    intro s event requires
    exact «po_s/2» s event requires
  have replay : (∀ state ev, Elixir.HoldLedger.Spec.«valid?/1» state = Except.ok Lynx.Term.true →
      (do let output ← Elixir.HoldLedger.Ledger.«step/2» state ev
          let next ← Erlang.erlang.«element/2» (Lynx.Term.integer 1) output
          Elixir.HoldLedger.Spec.«valid?/1» next) = Except.ok Lynx.Term.true) →
      ∀ events state, Elixir.HoldLedger.Spec.«proper_events?/1» events = Except.ok Lynx.Term.true →
      Elixir.HoldLedger.Spec.«valid?/1» state = Except.ok Lynx.Term.true →
      ∃ out, Elixir.HoldLedger.Ledger.«run/2» state events = Except.ok out ∧
        Elixir.HoldLedger.Spec.«valid?/1» out = Except.ok Lynx.Term.true := by
    clear requires amount_limit hold_limit events step_valid
    intro step_valid
    have step_shape : ∀ state ev out,
        Elixir.HoldLedger.Ledger.«step/2» state ev = Except.ok out →
        ∃ next result effects, out = Lynx.Term.tuple #[next,result,effects] := by
      clear step_valid
      intro state ev out hs
      simp only [Elixir.HoldLedger.Ledger.«step/2», Elixir.HoldLedger.Ledger.«request/3»,
        Elixir.HoldLedger.Ledger.«dispatch/2», Elixir.HoldLedger.Ledger.«timeout/2»,
        Elixir.HoldLedger.Ledger.«restart/1», Elixir.HoldLedger.Ledger.«retry/2»,
        Elixir.HoldLedger.Ledger.«processor_result/3», Elixir.HoldLedger.Ledger.«void/2», Elixir.HoldLedger.Ledger.«void_confirmed/2»,
        Elixir.HoldLedger.Ledger.«transport_ack/2»,
        Lynx.Except.guard, Lynx.Except.tryWith, bind, Except.bind] at hs
      all_goals repeat' (split at hs <;> try simp_all [])
      all_goals subst_vars
      all_goals first | exact ⟨_,_,_,rfl⟩ | exact ⟨_,_,_,by assumption⟩
    intro events state hp hv
    fun_induction Elixir.HoldLedger.Spec.«proper_events?/1» events generalizing state
    case case1 => exact ⟨state, rfl, hv⟩
    case case2 ev rest ih =>
      have htail : Elixir.HoldLedger.Spec.«proper_events?/1» rest = Except.ok Lynx.Term.true := hp
      have hsvalid := step_valid state ev hv
      cases hs : Elixir.HoldLedger.Ledger.«step/2» state ev with
      | error err => simp [hs, bind, Except.bind] at hsvalid
      | ok out =>
        obtain ⟨next, result, effects, rfl⟩ := step_shape state ev out hs
        have hvnext : Elixir.HoldLedger.Spec.«valid?/1» next = Except.ok Lynx.Term.true := by
          simpa [hs, Erlang.erlang.«element/2», bind, Except.bind] using hsvalid
        obtain ⟨final, hr, hfinal⟩ := ih next htail hvnext
        refine ⟨final, ?_, hfinal⟩
        simpa [Elixir.HoldLedger.Ledger.«run/2», hs, bind, Except.bind] using hr
    case case3 => simp [ Lynx.Term.true] at hp
  have replay_valid := replay step_valid
  clear replay step_valid
  cases amount_limit <;> cases hold_limit
  all_goals try solve | simp_all [«po_c2:requires/3», Erlang.erlang.«is_integer/1», Lynx.Term.true, Lynx.Term.false] <;>
    repeat' (split at requires <;> simp_all [])
  rename_i al hl
  simp only [«po_c2:requires/3», Erlang.erlang.«is_integer/1», bind, Except.bind] at requires
  all_goals repeat' (split at requires <;> try simp_all [Lynx.Term.true, Lynx.Term.false])
  all_goals repeat' (split at * <;> try simp_all [])
  all_goals
    have hinit : Elixir.HoldLedger.Spec.«valid?/1»
      (Lynx.Term.tuple #[Lynx.Term.integer al, Lynx.Term.integer hl, Lynx.Term.integer 0, Lynx.Term.integer 0, Lynx.Term.nil]) =
      Except.ok Lynx.Term.true := by
      clear replay_valid
      simp_all [Elixir.HoldLedger.Spec.«valid?/1», Elixir.HoldLedger.Spec.«nonnegative_state_valid?/5», Elixir.HoldLedger.Spec.«proper_entries?/1»,
        Elixir.HoldLedger.Spec.«unique_keys?/1», Elixir.HoldLedger.Spec.«unique_keys_seen?/2»,
        Elixir.HoldLedger.Spec.«hold_amount/1», Elixir.HoldLedger.Spec.«hold_count/1»,
        Erlang.erlang.«is_integer/1», Erlang.erlang.«is_list/1», Erlang.erlang.«==/2»,
            Lynx.Term.true]
  all_goals
    obtain ⟨out, hr, hv⟩ := replay_valid events
      (Lynx.Term.tuple #[Lynx.Term.integer al, Lynx.Term.integer hl, Lynx.Term.integer 0, Lynx.Term.integer 0, Lynx.Term.nil])
      (by assumption) hinit
  all_goals simp_all [«po_c2:ensures/3», Elixir.HoldLedger.Ledger.«init/2»,
    Erlang.erlang.«is_integer/1»]

end Elixir.HoldLedger.ProofContracts
