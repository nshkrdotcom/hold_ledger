module
public import Lynx
import Lean
import all Lynx.Term.Compare
public section

local notation "numericOrder" => fun a b : Lynx.Term => Lynx.Term.compare (Lynx.Term.fuel a b) a b

open Lean Elab Tactic in
elab "split_conjunction" : tactic => withMainContext do
  let g ← getMainGoal
  for decl in ← getLCtx do
    if decl.type.isAppOfArity ``And 2 then
      let subgoals ← g.cases decl.fvarId
      replaceMainGoal (subgoals.toList.map (·.mvarId))
      return
  throwError "no conjunction"

theorem HoldLedgerProof.integer_query (n : Int) (q : Lynx.Term) (m : Int)
   (h : numericOrder (Lynx.Term.integer n) q = Ordering.eq) :
   numericOrder (Lynx.Term.integer m) q = Ordering.eq ↔ m = n := by
 cases q <;> simp_all [Lynx.Term.compare_step, Lynx.Term.Compare.compareStep,
   Lynx.Term.Compare.ratCompare_eq_iff]
 rw [← h]
 exact Rat.intCast_inj

theorem HoldLedgerProof.atom_compare (x : Lynx.Term) (a : String) :
    numericOrder x (Lynx.Term.atom a) = Ordering.eq ↔ x = Lynx.Term.atom a := by
  cases x <;> simp [Lynx.Term.compare_step, Lynx.Term.Compare.compareStep]
theorem HoldLedgerProof.lookup_compare (stored a st key amount : Lynx.Term) :
    numericOrder (Lynx.Term.tuple #[Lynx.Term.atom "ok", Lynx.Term.tuple #[stored,a,st]])
      (Lynx.Term.tuple #[Lynx.Term.atom "ok", Lynx.Term.tuple #[key,amount,Lynx.Term.atom "unknown"]]) = Ordering.eq ↔
    numericOrder stored key = Ordering.eq ∧ numericOrder a amount = Ordering.eq ∧ st = Lynx.Term.atom "unknown" := by
  rw [← HoldLedgerProof.atom_compare st "unknown"]
  simp only [Lynx.Term.compare_tuple, List.compareLex, Ordering.then_eq_eq]
  cases hk : numericOrder stored key <;> cases ha : numericOrder a amount <;> cases hs : numericOrder st (Lynx.Term.atom "unknown") <;>
    simp_all

theorem HoldLedgerProof.atom_compare_left (a : String) (x : Lynx.Term) :
    numericOrder (Lynx.Term.atom a) x = Ordering.eq ↔ x = Lynx.Term.atom a := by
  cases x <;> simp [Lynx.Term.compare_step, Lynx.Term.Compare.compareStep]
  all_goals exact eq_comm

theorem HoldLedgerProof.atom_tuple (a : String) (xs : Array Lynx.Term) :
    numericOrder (Lynx.Term.atom a) (Lynx.Term.tuple xs) = Ordering.lt := by
  dsimp only
  rw [Lynx.Term.compare_step]
  rfl
theorem HoldLedgerProof.compare_atoms (a b : String) :
    numericOrder (Lynx.Term.atom a) (Lynx.Term.atom b) = compare a b := by
  exact Lynx.Term.compare_atoms a b
