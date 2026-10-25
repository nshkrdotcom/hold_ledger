module
public import Lynx
import Lean
import all Lynx.Term.Compare
public section

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
   (h : (Lynx.Term.integer n).compare q = Ordering.eq) :
   (Lynx.Term.integer m).compare q = Ordering.eq ↔ m = n := by
 cases q <;> simp_all [Lynx.Term.compare_eq_step, Lynx.Term.Compare.compareStep,
   Lynx.Term.Compare.ratCompare_eq_iff]
 rw [← h]
 exact Rat.intCast_inj

theorem HoldLedgerProof.atom_compare (x : Lynx.Term) (a : String) :
    x.compare (Lynx.Term.atom a) = Ordering.eq ↔ x = Lynx.Term.atom a := by
  cases x <;> simp [Lynx.Term.compare_eq_step, Lynx.Term.Compare.compareStep, Std.compare_eq_iff_eq]
theorem HoldLedgerProof.lookup_compare (stored a st key amount : Lynx.Term) :
    (Lynx.Term.tuple #[Lynx.Term.atom "ok", Lynx.Term.tuple #[stored,a,st]]).compare
      (Lynx.Term.tuple #[Lynx.Term.atom "ok", Lynx.Term.tuple #[key,amount,Lynx.Term.atom "unknown"]]) = Ordering.eq ↔
    stored.compare key = Ordering.eq ∧ a.compare amount = Ordering.eq ∧ st = Lynx.Term.atom "unknown" := by
  rw [← HoldLedgerProof.atom_compare st "unknown"]
  simp only [Lynx.Term.compare_tuple, List.compareLex, Ordering.then_eq_eq]
  cases hk : stored.compare key <;> cases ha : a.compare amount <;> cases hs : st.compare (Lynx.Term.atom "unknown") <;>
    simp_all [Lynx.Term.compare_tuple, List.compareLex, HoldLedgerProof.atom_compare]

theorem HoldLedgerProof.atom_compare_left (a : String) (x : Lynx.Term) :
    (Lynx.Term.atom a).compare x = Ordering.eq ↔ x = Lynx.Term.atom a := by
  cases x <;> simp [Lynx.Term.compare_eq_step, Lynx.Term.Compare.compareStep, Std.compare_eq_iff_eq]
  all_goals exact eq_comm

theorem HoldLedgerProof.atom_tuple (a : String) (xs : Array Lynx.Term) :
    (Lynx.Term.atom a).compare (Lynx.Term.tuple xs) = Ordering.lt := by
  rw [Lynx.Term.compare_eq_step]
  rfl
theorem HoldLedgerProof.compare_atoms (a b : String) :
    Lynx.Term.compare (Lynx.Term.atom a) (Lynx.Term.atom b) = compare a b := by
  rw [Lynx.Term.compare]
  rfl
