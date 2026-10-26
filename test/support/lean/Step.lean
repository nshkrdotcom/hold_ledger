module

public import Elixir.HoldLedger.ProofContracts
public import HoldLedgerProof.Induction
public import HoldLedgerProof.Request
public import HoldLedgerProof.Lifecycle

public section
set_option maxHeartbeats 16000000
namespace Elixir.HoldLedger.ProofContracts

theorem «po_s/2» (s event : Lynx.Term)
    (requires : «po_s:requires/2» s event = Except.ok Lynx.Term.true) :
    «po_s:ensures/2» s event = Except.ok Lynx.Term.true := by
  have request_valid : ∀ s key amount, Elixir.HoldLedger.Spec.«valid?/1» s = Except.ok Lynx.Term.true →
      (do let output ← Elixir.HoldLedger.Ledger.«request/3» s key amount
          let next ← Erlang.erlang.«element/2» (Lynx.Term.integer 1) output
          Elixir.HoldLedger.Spec.«valid?/1» next) = Except.ok Lynx.Term.true := by
    intro s key amount requires
    exact «po_a1/3» s key amount requires
  have dispatch_valid : ∀ s key, Elixir.HoldLedger.Spec.«valid?/1» s = Except.ok Lynx.Term.true →
      (do let output ← Elixir.HoldLedger.Ledger.«dispatch/2» s key
          let next ← Erlang.erlang.«element/2» (Lynx.Term.integer 1) output
          Elixir.HoldLedger.Spec.«valid?/1» next) = Except.ok Lynx.Term.true := by
    intro s key requires
    exact «po_b1_dispatch/2» s key requires
  have timeout_valid : ∀ s key, Elixir.HoldLedger.Spec.«valid?/1» s = Except.ok Lynx.Term.true →
      (do let output ← Elixir.HoldLedger.Ledger.«timeout/2» s key
          let next ← Erlang.erlang.«element/2» (Lynx.Term.integer 1) output
          Elixir.HoldLedger.Spec.«valid?/1» next) = Except.ok Lynx.Term.true := by
    intro s key requires
    exact «po_b1_timeout/2» s key requires
  have restart_valid : ∀ s, Elixir.HoldLedger.Spec.«valid?/1» s = Except.ok Lynx.Term.true →
      (do let output ← Elixir.HoldLedger.Ledger.«restart/1» s
          let next ← Erlang.erlang.«element/2» (Lynx.Term.integer 1) output
          Elixir.HoldLedger.Spec.«valid?/1» next) = Except.ok Lynx.Term.true := by
    intro s requires
    exact «po_b1_restart/1» s requires
  have retry_valid : ∀ s key, Elixir.HoldLedger.Spec.«valid?/1» s = Except.ok Lynx.Term.true →
      (do let output ← Elixir.HoldLedger.Ledger.«retry/2» s key
          let next ← Erlang.erlang.«element/2» (Lynx.Term.integer 1) output
          Elixir.HoldLedger.Spec.«valid?/1» next) = Except.ok Lynx.Term.true := by
    intro s key requires
    exact «po_b1_retry/2» s key requires
  have processor_result_valid : ∀ s key outcome, Elixir.HoldLedger.Spec.«valid?/1» s = Except.ok Lynx.Term.true →
      (do let output ← Elixir.HoldLedger.Ledger.«processor_result/3» s key outcome
          let next ← Erlang.erlang.«element/2» (Lynx.Term.integer 1) output
          Elixir.HoldLedger.Spec.«valid?/1» next) = Except.ok Lynx.Term.true := by
    intro s key outcome requires
    exact «po_b1_processor_result/3» s key outcome requires
  have void_valid : ∀ s key, Elixir.HoldLedger.Spec.«valid?/1» s = Except.ok Lynx.Term.true →
      (do let output ← Elixir.HoldLedger.Ledger.«void/2» s key
          let next ← Erlang.erlang.«element/2» (Lynx.Term.integer 1) output
          Elixir.HoldLedger.Spec.«valid?/1» next) = Except.ok Lynx.Term.true := by
    intro s key requires
    exact «po_b1_void/2» s key requires
  have confirmation_valid : ∀ s key, Elixir.HoldLedger.Spec.«valid?/1» s = Except.ok Lynx.Term.true →
      (do let output ← Elixir.HoldLedger.Ledger.«void_confirmed/2» s key
          let next ← Erlang.erlang.«element/2» (Lynx.Term.integer 1) output
          Elixir.HoldLedger.Spec.«valid?/1» next) = Except.ok Lynx.Term.true := by
    intro s key requires
    exact «po_b1_void_confirmed/2» s key requires
  change Elixir.HoldLedger.Spec.«valid?/1» s = Except.ok Lynx.Term.true at requires
  simp only [«po_s:ensures/2», Elixir.HoldLedger.Ledger.«step/2»]
  split
  case h_1 ev k amount => exact request_valid s k amount requires
  case h_2 ev k => exact dispatch_valid s k requires
  case h_3 ev k => exact timeout_valid s k requires
  case h_4 => exact restart_valid s requires
  case h_5 ev k => exact retry_valid s k requires
  case h_6 ev k outcome => exact processor_result_valid s k outcome requires
  case h_7 ev k => exact void_valid s k requires
  case h_8 ev k => exact confirmation_valid s k requires
  case h_9 ev k =>
    cases k <;> simp [Elixir.HoldLedger.Ledger.«transport_ack/2»,
      Erlang.erlang.«element/2»,     requires]
  case h_10 => simp [Erlang.erlang.«element/2»,   requires]

end Elixir.HoldLedger.ProofContracts
