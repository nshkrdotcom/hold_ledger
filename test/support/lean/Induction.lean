module

public import Elixir.HoldLedger.ProofContracts
public import HoldLedgerProof.Tactics

public section
namespace HoldLedgerProof.Induction

-- Materialize functional induction support once, before sibling proof modules.
-- Otherwise their independent imports can declare the same generated helper.

theorem prepare_0 (x0 x1 : Lynx.Term) : True := by
  fun_induction Elixir.HoldLedger.Ledger.«find/2» x0 x1 <;> trivial

theorem prepare_1 (x0 : Lynx.Term) : True := by
  fun_induction Elixir.HoldLedger.Ledger.«mark_unknown/1» x0 <;> trivial

theorem prepare_2 (x0 x1 x2 : Lynx.Term) : True := by
  fun_induction Elixir.HoldLedger.Ledger.«set_status/3» x0 x1 x2 <;> trivial

theorem prepare_3 (x0 : Lynx.Term) : True := by
  fun_induction Elixir.HoldLedger.Spec.«hold_amount/1» x0 <;> trivial

theorem prepare_4 (x0 x1 : Lynx.Term) : True := by
  fun_induction Elixir.HoldLedger.Spec.«lookup/2» x0 x1 <;> trivial

theorem prepare_5 (x0 : Lynx.Term) : True := by
  fun_induction Elixir.HoldLedger.Spec.«proper_entries?/1» x0 <;> trivial

theorem prepare_6 (x0 : Lynx.Term) : True := by
  fun_induction Elixir.HoldLedger.Spec.«proper_events?/1» x0 <;> trivial

theorem prepare_7 (x0 x1 : Lynx.Term) : True := by
  fun_induction Elixir.HoldLedger.Spec.«unique_keys_seen?/2» x0 x1 <;> trivial

end HoldLedgerProof.Induction
