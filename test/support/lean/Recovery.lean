module
public import Elixir.HoldLedger.Composite
public import Lynx

public section
namespace HoldLedgerProof.Recovery

/-- A finite live execution whose individual transitions have committed.
    This relation records successful applications of the actual translated fold;
    it neither assumes replay equality nor asserts disk synchronization. -/
inductive Committed : Lynx.Term → List Lynx.Term → Lynx.Term → Prop where
  | empty (state) : Committed state [] state
  | next {state event next result effects events final} :
      Elixir.HoldLedger.Composite.«step/2» state event =
        Except.ok (.tuple #[next,result,effects]) →
      Committed next events final →
      Committed state (event :: events) final

/-- Folding the same accepted durable events reconstructs the complete composite
    state, including outstanding obligations and durable attempt metadata. -/
theorem committed_replay {state final : Lynx.Term} {events : List Lynx.Term}
    (live : Committed state events final) :
    Elixir.HoldLedger.Composite.«run/2» state (Lynx.Term.list events) = Except.ok final := by
  induction live with
  | empty state => rfl
  | @next state event next result effects events final applied tail ih =>
      simpa [Lynx.Term.list,Elixir.HoldLedger.Composite.«run/2»,applied,
        bind,Except.bind] using ih

end HoldLedgerProof.Recovery
