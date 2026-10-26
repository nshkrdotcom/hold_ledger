module

public import Elixir.HoldLedger.ProofContracts
public import HoldLedgerProof.Induction
public import HoldLedgerProof.CoreAccounting
public import HoldLedgerProof.CoreLookup
public import HoldLedgerProof.CoreStructure

public section
set_option maxHeartbeats 16000000
namespace Elixir.HoldLedger.ProofContracts

theorem «l3_accounting/5» (entries key amount «from» to : Lynx.Term)
    (requires : «l3_accounting:requires/5» entries key amount «from» to = Except.ok Lynx.Term.true) :
    «l3_accounting:ensures/5» entries key amount «from» to = Except.ok Lynx.Term.true := by
  have totals := HoldLedgerProof.totals_1
  have delta := HoldLedgerProof.delta_1
  have atom_exact (n : String) (x : Lynx.Term) :
      (Lynx.Term.atom n).exactCompare x = Ordering.eq ↔ x = Lynx.Term.atom n := by
    rw [Std.OrientedCmp.eq_swap (cmp := Lynx.Term.exactCompare), Ordering.swap_eq_eq]
    exact Lynx.Term.exactCompare_eq_atom x n
  have known_exact := HoldLedgerProof.known_exact_1
  have lookup_shape := HoldLedgerProof.lookup_shape_1
  simp only [«l3_accounting:requires/5», bind, Except.bind] at requires
  all_goals repeat' (split at * <;> try simp_all [Lynx.Term.true])
  all_goals obtain hshape := lookup_shape entries key (by assumption)
  all_goals rcases hshape with hn | ⟨ek, a, st, hl, hs⟩
  all_goals try { solve | simp_all [Erlang.erlang.«=:=/2»,  Lynx.Term.true, Lynx.Term.false] <;>
    subst_vars <;> simp_all [] }
  all_goals
    have he : Erlang.erlang.«=:=/2»
      (Lynx.Term.tuple #[Lynx.Term.atom "ok", Lynx.Term.tuple #[Lynx.Term.integer ek, Lynx.Term.integer a, st]])
      (Lynx.Term.tuple #[Lynx.Term.atom "ok", Lynx.Term.tuple #[key, amount, «from»]]) = Except.ok Lynx.Term.true := by simp_all
  all_goals simp [Erlang.erlang.«=:=/2», Lynx.Term.exactCompare_tuple,
    List.compareLex,  Lynx.Term.true, Lynx.Term.false] at he
  all_goals cases hkeycmp : (Lynx.Term.integer ek).exactCompare key <;> try simp only [hkeycmp] at he
  all_goals try contradiction
  all_goals cases hamtcmp : (Lynx.Term.integer a).exactCompare amount <;> try simp only [hamtcmp] at he
  all_goals try contradiction
  all_goals cases hfrom : st.exactCompare «from» <;> try simp only [hfrom] at he
  all_goals try contradiction
  all_goals have hkey := (Lynx.Term.integer_exactCompare_eq ek key).mp hkeycmp
  all_goals have hamt := (Lynx.Term.integer_exactCompare_eq a amount).mp hamtcmp
  all_goals subst key
  all_goals subst amount
  all_goals have same := known_exact st «from» hs hfrom
  all_goals subst «from»
  all_goals
    obtain ⟨out, hm, ba, hba, bc, hbc, haa, hac⟩ :=
      delta entries (Lynx.Term.integer ek) a st to (by assumption) hl
  all_goals cases ho : HoldLedgerProof.held st <;> cases ht : HoldLedgerProof.held to <;>
    simp_all [«l3_accounting:ensures/5», HoldLedgerProof.holding_model, Erlang.erlang.«==/2»,
      Lynx.Term.true, Lynx.Term.false]

theorem «l5_fresh/3» (entries key amount : Lynx.Term)
    (requires : «l5_fresh:requires/3» entries key amount = Except.ok Lynx.Term.true) :
    «l5_fresh:ensures/3» entries key amount = Except.ok Lynx.Term.true := by
  have seen_append := HoldLedgerProof.seen_append_1
  have fresh := HoldLedgerProof.fresh_1
  have totals := HoldLedgerProof.totals_1
  simp only [«l5_fresh:requires/3», bind, Except.bind] at requires
  all_goals repeat' (split at * <;> try simp_all [Lynx.Term.true])
  all_goals simp only [Elixir.HoldLedger.Spec.«unique_keys?/1», Elixir.HoldLedger.Spec.«has_key?/2»,
    Erlang.erlang.«not/1», Lynx.Except.guard, Lynx.Except.tryWith, bind, Except.bind] at *
  all_goals repeat' (split at * <;> try simp_all [Lynx.Term.true, Lynx.Term.false])
  all_goals have hnew := fresh entries [] key (by assumption) (by assumption) (by assumption)
  all_goals obtain ⟨⟨a, ha⟩, c, hc⟩ := totals entries (by assumption)
  all_goals cases key <;> cases amount <;>
    simp_all [Erlang.erlang.«is_integer/1», Lynx.Term.true, Lynx.Term.false]
  all_goals simp_all [«l5_fresh:ensures/3», Elixir.HoldLedger.Spec.«proper_entries?/1»,
    Elixir.HoldLedger.Spec.«unique_keys?/1», Elixir.HoldLedger.Spec.«unique_keys_seen?/2»,
    Elixir.HoldLedger.Spec.«seen?/2», Elixir.HoldLedger.Spec.«known_status?/1»,
    Elixir.HoldLedger.Spec.«holding?/1», Elixir.HoldLedger.Spec.«hold_amount/1»,
    Elixir.HoldLedger.Spec.«hold_count/1», Erlang.erlang.«is_integer/1»,
    Erlang.erlang.«is_list/1», Erlang.erlang.«==/2», Int.add_comm,
    Lynx.Term.true, Lynx.Term.false]

theorem «l6_restart/1» (entries : Lynx.Term)
    (requires : «l6_restart:requires/1» entries = Except.ok Lynx.Term.true) :
    «l6_restart:ensures/1» entries = Except.ok Lynx.Term.true := by
  have accounting := HoldLedgerProof.accounting_1
  unfold «l6_restart:requires/1» at requires
  cases hp : Elixir.HoldLedger.Spec.«proper_entries?/1» entries <;>
    simp_all [Lynx.Term.true]
  all_goals repeat' (split at requires <;> try simp_all [])
  all_goals obtain ⟨out, hm, a, ha, hb, c, hc, hd⟩ := accounting entries (by assumption)
  all_goals simp [«l6_restart:ensures/1», hm, ha, hb, hc, hd,
    Erlang.erlang.«==/2», Lynx.Term.true]

end Elixir.HoldLedger.ProofContracts
