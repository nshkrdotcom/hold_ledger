module
public import Lynx
public import Init.Data.List.Int.Sum
import Lean

public section
namespace HoldLedgerProof.Capacity

@[expose] def amount : List (Int × Int) → Int
  | [] => 0
  | entry :: rest => entry.2 + amount rest

theorem amount_append (a b : List (Int × Int)) : amount (a ++ b) = amount a + amount b := by
  induction a with
  | nil => simp [amount]
  | cons entry rest ih => simp [amount,ih,Int.add_assoc]

theorem amount_nonnegative {entries : List (Int × Int)}
    (positive : ∀ entry ∈ entries, 0 ≤ entry.2) : 0 ≤ amount entries := by
  induction entries with
  | nil => simp [amount]
  | cons entry rest ih =>
      have first := positive entry (by simp)
      have tail := ih (by intro e h; exact positive e (by simp [h]))
      simp only [amount]
      omega

/-- Deduplicated remote identities inject into the holdings holding entries.
    The proof counts each matching contribution once; negative holdings amounts
    are explicitly excluded rather than silently discarded. -/
theorem subset_bounds {remote holdings : List (Int × Int)}
    (deduplicated : remote.Nodup)
    (covered : ∀ entry ∈ remote, entry ∈ holdings)
    (nonnegative : ∀ entry ∈ holdings, 0 ≤ entry.2) :
    amount remote ≤ amount holdings ∧ remote.length ≤ holdings.length := by
  induction remote generalizing holdings with
  | nil => exact ⟨amount_nonnegative nonnegative,by simp⟩
  | cons entry rest ih =>
      obtain ⟨not_in_tail,tail_unique⟩ := List.nodup_cons.mp deduplicated
      obtain ⟨front,back,shape⟩ := List.mem_iff_append.mp (covered entry (by simp))
      subst holdings
      have tail_covered : ∀ e ∈ rest, e ∈ front ++ back := by
        intro e member
        have found := covered e (by simp [member])
        simp only [List.mem_append,List.mem_cons] at found ⊢
        rcases found with left | same | right
        · exact Or.inl left
        · exact False.elim (not_in_tail (by simpa [same] using member))
        · exact Or.inr right
      have tail_positive : ∀ e ∈ front ++ back, 0 ≤ e.2 := by
        intro e member
        apply nonnegative e
        simpa only [List.mem_append,List.mem_cons] using
          (by
            rcases List.mem_append.mp member with left | right
            · exact Or.inl left
            · exact Or.inr (Or.inr right) : e ∈ front ∨ e = entry ∨ e ∈ back)
      obtain ⟨used,slots⟩ := ih tail_unique tail_covered tail_positive
      simp only [amount,amount_append,List.length_cons,List.length_append] at *
      omega

end HoldLedgerProof.Capacity
