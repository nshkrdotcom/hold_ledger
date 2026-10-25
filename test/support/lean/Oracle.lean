module

public import Elixir.HoldLedger.ProofContracts
public import HoldLedgerProof.CoreShape
public import HoldLedgerProof.CoreLookup
public import HoldLedgerProof.CorePreservation
public import HoldLedgerProof.Step

public section
set_option maxHeartbeats 4000000
namespace HoldLedgerProof

theorem replacement_eq (entries key status : Lynx.Term) :
    Elixir.HoldLedger.Spec.«replacement/3» entries key status =
      Elixir.HoldLedger.Ledger.«set_status/3» entries key status := by
  fun_induction Elixir.HoldLedger.Ledger.«set_status/3» entries key status
  all_goals simp_all [Elixir.HoldLedger.Spec.«replacement/3», Elixir.HoldLedger.Ledger.«set_status/3»,
    Erlang.erlang.«==/2», Lynx.Except.guard, Lynx.Except.tryWith, bind, Except.bind]
  all_goals unfold Elixir.HoldLedger.Spec.«replacement/3»
  all_goals repeat' (split <;> try simp_all [Erlang.erlang.«==/2»,Lynx.Except.guard,Lynx.Except.tryWith,bind,Except.bind,Lynx.Term.true,Lynx.Term.false])

theorem unknown_sent_eq (entries : Lynx.Term) :
    Elixir.HoldLedger.Spec.«unknown_sent/1» entries = Elixir.HoldLedger.Ledger.«mark_unknown/1» entries := by
  fun_induction Elixir.HoldLedger.Ledger.«mark_unknown/1» entries
  all_goals simp_all [Elixir.HoldLedger.Spec.«unknown_sent/1», Elixir.HoldLedger.Ledger.«mark_unknown/1», bind, Except.bind]
  all_goals repeat' (split <;> try simp_all [bind, Except.bind, Lynx.Term.true, Lynx.Term.false])

theorem restated_valid (al hl ua uh : Int) (entries old_used old_holds old_entries : Lynx.Term)
    (valid : Elixir.HoldLedger.Spec.«valid?/1»
      (Lynx.Term.tuple #[Lynx.Term.integer al,Lynx.Term.integer hl,Lynx.Term.integer ua,Lynx.Term.integer uh,entries]) =
        Except.ok Lynx.Term.true) :
    Elixir.HoldLedger.Spec.«restated/2»
      (Lynx.Term.tuple #[Lynx.Term.integer al,Lynx.Term.integer hl,old_used,old_holds,old_entries]) entries =
      Except.ok (Lynx.Term.tuple #[Lynx.Term.integer al,Lynx.Term.integer hl,Lynx.Term.integer ua,Lynx.Term.integer uh,entries]) := by
  obtain ⟨a,b,c,d,es,equal,hp,hu,ha,hc,hal,hhl,hua,huh,hacap,hhcap⟩ := valid_view_1 _ valid
  simp at equal
  obtain ⟨rfl,rfl,rfl,rfl,rfl⟩ := equal
  simp [Elixir.HoldLedger.Spec.«restated/2»,Elixir.HoldLedger.Spec.«hold_amount/1»,Elixir.HoldLedger.Spec.«hold_count/1»,
      Elixir.HoldLedger.Spec.«holding?/1»,Erlang.erlang.«is_integer/1»,Erlang.erlang.«>/2»,Erlang.erlang.«>=/2»,ha,hc,bind,Except.bind]

theorem step_shape (state ev out : Lynx.Term)
    (hs : Elixir.HoldLedger.Ledger.«step/2» state ev = Except.ok out) :
    ∃ next result effects, out = Lynx.Term.tuple #[next,result,effects] := by
  simp only [Elixir.HoldLedger.Ledger.«step/2», Elixir.HoldLedger.Ledger.«request/3»,
    Elixir.HoldLedger.Ledger.«dispatch/2», Elixir.HoldLedger.Ledger.«timeout/2»,
    Elixir.HoldLedger.Ledger.«restart/1», Elixir.HoldLedger.Ledger.«retry/2»,
    Elixir.HoldLedger.Ledger.«processor_result/3», Elixir.HoldLedger.Ledger.«void/2»,
    Elixir.HoldLedger.Ledger.«transport_ack/2»,
    Lynx.Except.guard, Lynx.Except.tryWith, bind, Except.bind] at hs
  all_goals repeat' (split at hs <;> try simp_all [Lynx.Term.true, Lynx.Term.false])
  all_goals subst_vars
  all_goals first | exact ⟨_,_,_,rfl⟩ | exact ⟨_,_,_,by assumption⟩

@[expose] def normalize (output : Lynx.Term) : Except Lynx.Exception Lynx.Term := do
  let next ← Erlang.erlang.«element/2» (Lynx.Term.integer 1) output
  let result ← Erlang.erlang.«element/2» (Lynx.Term.integer 2) output
  let effects ← Erlang.erlang.«element/2» (Lynx.Term.integer 3) output
  let entries ← Erlang.erlang.«element/2» (Lynx.Term.integer 5) next
  let recalculated ← Elixir.HoldLedger.Spec.«restated/2» next entries
  pure (Lynx.Term.tuple #[recalculated,result,effects])

theorem normalize_valid (next result effects : Lynx.Term)
    (valid : Elixir.HoldLedger.Spec.«valid?/1» next = Except.ok Lynx.Term.true) :
    normalize (Lynx.Term.tuple #[next,result,effects]) = Except.ok (Lynx.Term.tuple #[next,result,effects]) := by
  obtain ⟨al,hl,ua,uh,entries,rfl,hp,hu,ha,hc,hal,hhl,hua,huh,hacap,hhcap⟩ := valid_view_1 next valid
  simp [normalize,Elixir.HoldLedger.Spec.«restated/2»,Elixir.HoldLedger.Spec.«hold_amount/1»,Elixir.HoldLedger.Spec.«hold_count/1»,
      Elixir.HoldLedger.Spec.«holding?/1»,Erlang.erlang.«is_integer/1»,Erlang.erlang.«>/2»,Erlang.erlang.«>=/2»,ha,hc,Erlang.erlang.«element/2»,bind,Except.bind]

theorem oracle_normalized (s event : Lynx.Term)
    (valid : Elixir.HoldLedger.Spec.«valid?/1» s = Except.ok Lynx.Term.true) :
    Elixir.HoldLedger.Spec.«expected_step/2» s event =
      (do let output ← Elixir.HoldLedger.Ledger.«step/2» s event
          normalize output) := by
  obtain ⟨al,hl,ua,uh,entries,rfl,hp,hu,ha,hc,hal,hhl,hua,huh,hacap,hhcap⟩ := valid_view_1 s valid
  have find_eq (query : Lynx.Term) : Elixir.HoldLedger.Ledger.«find/2» entries query = Elixir.HoldLedger.Spec.«lookup/2» entries query := by
    obtain ⟨value,hf,hl⟩ := compatible_1 entries query hp
    exact hf.trans hl.symm
  let changed (n : Int) (status : Lynx.Term) := Classical.choose (replaced_3 entries n status hp)
  have change_eq (n : Int) (status : Lynx.Term) :
      Elixir.HoldLedger.Ledger.«set_status/3» entries (Lynx.Term.integer n) status = Except.ok (changed n status) :=
    (Classical.choose_spec (replaced_3 entries n status hp)).1
  obtain ⟨restarted, restart_eq, _⟩ := marked_3 entries hp
  clear_value changed
  simp only [Elixir.HoldLedger.Ledger.«step/2»]
  split
  case h_1 ev key amount =>
    cases key <;> try solve | simp [Elixir.HoldLedger.Spec.«expected_step/2»,Elixir.HoldLedger.Spec.«expect_request/3»,
      Elixir.HoldLedger.Spec.«expect_single/6»,Elixir.HoldLedger.Spec.«expect_choice/4»,Elixir.HoldLedger.Spec.«expect_void/2»,
      Elixir.HoldLedger.Ledger.«request/3»,Elixir.HoldLedger.Ledger.«dispatch/2»,Elixir.HoldLedger.Ledger.«timeout/2»,
      Elixir.HoldLedger.Ledger.«retry/2»,Elixir.HoldLedger.Ledger.«processor_result/3»,Elixir.HoldLedger.Ledger.«void/2»,
      Elixir.HoldLedger.Ledger.«transport_ack/2»,find_eq,replacement_eq,change_eq,normalize,
      Elixir.HoldLedger.Spec.«restated/2»,Elixir.HoldLedger.Spec.«hold_amount/1»,Elixir.HoldLedger.Spec.«hold_count/1»,
      Elixir.HoldLedger.Spec.«holding?/1»,ha,hc,Erlang.erlang.«is_integer/1»,Erlang.erlang.«element/2»,
      Erlang.erlang.«>/2»,Erlang.erlang.«>=/2»,Erlang.erlang.«=:=/2»,Erlang.erlang.«==/2»,HoldLedgerProof.compare_atoms,
      Lynx.Except.guard,Lynx.Except.tryWith,bind,Except.bind,Lynx.Term.true,Lynx.Term.false]
    cases amount <;> try solve | simp [Elixir.HoldLedger.Spec.«expected_step/2»,Elixir.HoldLedger.Spec.«expect_request/3»,
      Elixir.HoldLedger.Spec.«expect_single/6»,Elixir.HoldLedger.Spec.«expect_choice/4»,Elixir.HoldLedger.Spec.«expect_void/2»,
      Elixir.HoldLedger.Ledger.«request/3»,Elixir.HoldLedger.Ledger.«dispatch/2»,Elixir.HoldLedger.Ledger.«timeout/2»,
      Elixir.HoldLedger.Ledger.«retry/2»,Elixir.HoldLedger.Ledger.«processor_result/3»,Elixir.HoldLedger.Ledger.«void/2»,
      Elixir.HoldLedger.Ledger.«transport_ack/2»,find_eq,replacement_eq,change_eq,normalize,
      Elixir.HoldLedger.Spec.«restated/2»,Elixir.HoldLedger.Spec.«hold_amount/1»,Elixir.HoldLedger.Spec.«hold_count/1»,
      Elixir.HoldLedger.Spec.«holding?/1»,ha,hc,Erlang.erlang.«is_integer/1»,Erlang.erlang.«element/2»,
      Erlang.erlang.«>/2»,Erlang.erlang.«>=/2»,Erlang.erlang.«=:=/2»,Erlang.erlang.«==/2»,HoldLedgerProof.compare_atoms,
      Lynx.Except.guard,Lynx.Except.tryWith,bind,Except.bind,Lynx.Term.true,Lynx.Term.false]
    rename_i kn an
    rcases lookup_shape_1 entries (Lynx.Term.integer kn) hp with absent | ⟨ek,av,status,found,known⟩
    all_goals try simp_all [Elixir.HoldLedger.Spec.«expected_step/2»,Elixir.HoldLedger.Spec.«expect_request/3»,
      Elixir.HoldLedger.Spec.«expect_single/6»,Elixir.HoldLedger.Spec.«expect_choice/4»,Elixir.HoldLedger.Spec.«expect_void/2»,
      Elixir.HoldLedger.Ledger.«request/3»,Elixir.HoldLedger.Ledger.«dispatch/2»,Elixir.HoldLedger.Ledger.«timeout/2»,
      Elixir.HoldLedger.Ledger.«retry/2»,Elixir.HoldLedger.Ledger.«processor_result/3»,Elixir.HoldLedger.Ledger.«void/2»,
      Elixir.HoldLedger.Ledger.«transport_ack/2»,find_eq,replacement_eq,change_eq,normalize,
      Elixir.HoldLedger.Spec.«restated/2»,Elixir.HoldLedger.Spec.«hold_amount/1»,Elixir.HoldLedger.Spec.«hold_count/1»,
      Elixir.HoldLedger.Spec.«holding?/1»,ha,hc,Erlang.erlang.«is_integer/1»,Erlang.erlang.«element/2»,
      Erlang.erlang.«>/2»,Erlang.erlang.«>=/2»,Erlang.erlang.«=:=/2»,Erlang.erlang.«==/2»,HoldLedgerProof.compare_atoms,
      Lynx.Except.guard,Lynx.Except.tryWith,bind,Except.bind,Lynx.Term.true,Lynx.Term.false]
    all_goals repeat' (split at * <;> (repeat' split_conjunction) <;> subst_vars <;> try simp_all [Elixir.HoldLedger.Spec.«expected_step/2»,Elixir.HoldLedger.Spec.«expect_request/3»,
      Elixir.HoldLedger.Spec.«expect_single/6»,Elixir.HoldLedger.Spec.«expect_choice/4»,Elixir.HoldLedger.Spec.«expect_void/2»,
      Elixir.HoldLedger.Ledger.«request/3»,Elixir.HoldLedger.Ledger.«dispatch/2»,Elixir.HoldLedger.Ledger.«timeout/2»,
      Elixir.HoldLedger.Ledger.«retry/2»,Elixir.HoldLedger.Ledger.«processor_result/3»,Elixir.HoldLedger.Ledger.«void/2»,
      Elixir.HoldLedger.Ledger.«transport_ack/2»,find_eq,replacement_eq,change_eq,normalize,
      Elixir.HoldLedger.Spec.«restated/2»,Elixir.HoldLedger.Spec.«hold_amount/1»,Elixir.HoldLedger.Spec.«hold_count/1»,
      Elixir.HoldLedger.Spec.«holding?/1»,ha,hc,Erlang.erlang.«is_integer/1»,Erlang.erlang.«element/2»,
      Erlang.erlang.«>/2»,Erlang.erlang.«>=/2»,Erlang.erlang.«=:=/2»,Erlang.erlang.«==/2»,HoldLedgerProof.compare_atoms,
      Lynx.Except.guard,Lynx.Except.tryWith,bind,Except.bind,Lynx.Term.true,Lynx.Term.false])
  case h_2 ev key =>
    cases key <;> try solve | simp [Elixir.HoldLedger.Spec.«expected_step/2»,Elixir.HoldLedger.Spec.«expect_request/3»,
      Elixir.HoldLedger.Spec.«expect_single/6»,Elixir.HoldLedger.Spec.«expect_choice/4»,Elixir.HoldLedger.Spec.«expect_void/2»,
      Elixir.HoldLedger.Ledger.«request/3»,Elixir.HoldLedger.Ledger.«dispatch/2»,Elixir.HoldLedger.Ledger.«timeout/2»,
      Elixir.HoldLedger.Ledger.«retry/2»,Elixir.HoldLedger.Ledger.«processor_result/3»,Elixir.HoldLedger.Ledger.«void/2»,
      Elixir.HoldLedger.Ledger.«transport_ack/2»,find_eq,replacement_eq,change_eq,normalize,
      Elixir.HoldLedger.Spec.«restated/2»,Elixir.HoldLedger.Spec.«hold_amount/1»,Elixir.HoldLedger.Spec.«hold_count/1»,
      Elixir.HoldLedger.Spec.«holding?/1»,ha,hc,Erlang.erlang.«is_integer/1»,Erlang.erlang.«element/2»,
      Erlang.erlang.«>/2»,Erlang.erlang.«>=/2»,Erlang.erlang.«=:=/2»,Erlang.erlang.«==/2»,HoldLedgerProof.compare_atoms,
      Lynx.Except.guard,Lynx.Except.tryWith,bind,Except.bind,Lynx.Term.true,Lynx.Term.false]
    rename_i kn
    rcases lookup_shape_1 entries (Lynx.Term.integer kn) hp with absent | ⟨ek,av,status,found,known⟩
    all_goals try simp_all [Elixir.HoldLedger.Spec.«expected_step/2»,Elixir.HoldLedger.Spec.«expect_request/3»,
      Elixir.HoldLedger.Spec.«expect_single/6»,Elixir.HoldLedger.Spec.«expect_choice/4»,Elixir.HoldLedger.Spec.«expect_void/2»,
      Elixir.HoldLedger.Ledger.«request/3»,Elixir.HoldLedger.Ledger.«dispatch/2»,Elixir.HoldLedger.Ledger.«timeout/2»,
      Elixir.HoldLedger.Ledger.«retry/2»,Elixir.HoldLedger.Ledger.«processor_result/3»,Elixir.HoldLedger.Ledger.«void/2»,
      Elixir.HoldLedger.Ledger.«transport_ack/2»,find_eq,replacement_eq,change_eq,normalize,
      Elixir.HoldLedger.Spec.«restated/2»,Elixir.HoldLedger.Spec.«hold_amount/1»,Elixir.HoldLedger.Spec.«hold_count/1»,
      Elixir.HoldLedger.Spec.«holding?/1»,ha,hc,Erlang.erlang.«is_integer/1»,Erlang.erlang.«element/2»,
      Erlang.erlang.«>/2»,Erlang.erlang.«>=/2»,Erlang.erlang.«=:=/2»,Erlang.erlang.«==/2»,HoldLedgerProof.compare_atoms,
      Lynx.Except.guard,Lynx.Except.tryWith,bind,Except.bind,Lynx.Term.true,Lynx.Term.false]
    all_goals repeat' (split at * <;> (repeat' split_conjunction) <;> subst_vars <;> try simp_all [Elixir.HoldLedger.Spec.«expected_step/2»,Elixir.HoldLedger.Spec.«expect_request/3»,
      Elixir.HoldLedger.Spec.«expect_single/6»,Elixir.HoldLedger.Spec.«expect_choice/4»,Elixir.HoldLedger.Spec.«expect_void/2»,
      Elixir.HoldLedger.Ledger.«request/3»,Elixir.HoldLedger.Ledger.«dispatch/2»,Elixir.HoldLedger.Ledger.«timeout/2»,
      Elixir.HoldLedger.Ledger.«retry/2»,Elixir.HoldLedger.Ledger.«processor_result/3»,Elixir.HoldLedger.Ledger.«void/2»,
      Elixir.HoldLedger.Ledger.«transport_ack/2»,find_eq,replacement_eq,change_eq,normalize,
      Elixir.HoldLedger.Spec.«restated/2»,Elixir.HoldLedger.Spec.«hold_amount/1»,Elixir.HoldLedger.Spec.«hold_count/1»,
      Elixir.HoldLedger.Spec.«holding?/1»,ha,hc,Erlang.erlang.«is_integer/1»,Erlang.erlang.«element/2»,
      Erlang.erlang.«>/2»,Erlang.erlang.«>=/2»,Erlang.erlang.«=:=/2»,Erlang.erlang.«==/2»,HoldLedgerProof.compare_atoms,
      Lynx.Except.guard,Lynx.Except.tryWith,bind,Except.bind,Lynx.Term.true,Lynx.Term.false])
  case h_3 ev key =>
    cases key <;> try solve | simp [Elixir.HoldLedger.Spec.«expected_step/2»,Elixir.HoldLedger.Spec.«expect_request/3»,
      Elixir.HoldLedger.Spec.«expect_single/6»,Elixir.HoldLedger.Spec.«expect_choice/4»,Elixir.HoldLedger.Spec.«expect_void/2»,
      Elixir.HoldLedger.Ledger.«request/3»,Elixir.HoldLedger.Ledger.«dispatch/2»,Elixir.HoldLedger.Ledger.«timeout/2»,
      Elixir.HoldLedger.Ledger.«retry/2»,Elixir.HoldLedger.Ledger.«processor_result/3»,Elixir.HoldLedger.Ledger.«void/2»,
      Elixir.HoldLedger.Ledger.«transport_ack/2»,find_eq,replacement_eq,change_eq,normalize,
      Elixir.HoldLedger.Spec.«restated/2»,Elixir.HoldLedger.Spec.«hold_amount/1»,Elixir.HoldLedger.Spec.«hold_count/1»,
      Elixir.HoldLedger.Spec.«holding?/1»,ha,hc,Erlang.erlang.«is_integer/1»,Erlang.erlang.«element/2»,
      Erlang.erlang.«>/2»,Erlang.erlang.«>=/2»,Erlang.erlang.«=:=/2»,Erlang.erlang.«==/2»,HoldLedgerProof.compare_atoms,
      Lynx.Except.guard,Lynx.Except.tryWith,bind,Except.bind,Lynx.Term.true,Lynx.Term.false]
    rename_i kn
    rcases lookup_shape_1 entries (Lynx.Term.integer kn) hp with absent | ⟨ek,av,status,found,known⟩
    all_goals try simp_all [Elixir.HoldLedger.Spec.«expected_step/2»,Elixir.HoldLedger.Spec.«expect_request/3»,
      Elixir.HoldLedger.Spec.«expect_single/6»,Elixir.HoldLedger.Spec.«expect_choice/4»,Elixir.HoldLedger.Spec.«expect_void/2»,
      Elixir.HoldLedger.Ledger.«request/3»,Elixir.HoldLedger.Ledger.«dispatch/2»,Elixir.HoldLedger.Ledger.«timeout/2»,
      Elixir.HoldLedger.Ledger.«retry/2»,Elixir.HoldLedger.Ledger.«processor_result/3»,Elixir.HoldLedger.Ledger.«void/2»,
      Elixir.HoldLedger.Ledger.«transport_ack/2»,find_eq,replacement_eq,change_eq,normalize,
      Elixir.HoldLedger.Spec.«restated/2»,Elixir.HoldLedger.Spec.«hold_amount/1»,Elixir.HoldLedger.Spec.«hold_count/1»,
      Elixir.HoldLedger.Spec.«holding?/1»,ha,hc,Erlang.erlang.«is_integer/1»,Erlang.erlang.«element/2»,
      Erlang.erlang.«>/2»,Erlang.erlang.«>=/2»,Erlang.erlang.«=:=/2»,Erlang.erlang.«==/2»,HoldLedgerProof.compare_atoms,
      Lynx.Except.guard,Lynx.Except.tryWith,bind,Except.bind,Lynx.Term.true,Lynx.Term.false]
    all_goals repeat' (split at * <;> (repeat' split_conjunction) <;> subst_vars <;> try simp_all [Elixir.HoldLedger.Spec.«expected_step/2»,Elixir.HoldLedger.Spec.«expect_request/3»,
      Elixir.HoldLedger.Spec.«expect_single/6»,Elixir.HoldLedger.Spec.«expect_choice/4»,Elixir.HoldLedger.Spec.«expect_void/2»,
      Elixir.HoldLedger.Ledger.«request/3»,Elixir.HoldLedger.Ledger.«dispatch/2»,Elixir.HoldLedger.Ledger.«timeout/2»,
      Elixir.HoldLedger.Ledger.«retry/2»,Elixir.HoldLedger.Ledger.«processor_result/3»,Elixir.HoldLedger.Ledger.«void/2»,
      Elixir.HoldLedger.Ledger.«transport_ack/2»,find_eq,replacement_eq,change_eq,normalize,
      Elixir.HoldLedger.Spec.«restated/2»,Elixir.HoldLedger.Spec.«hold_amount/1»,Elixir.HoldLedger.Spec.«hold_count/1»,
      Elixir.HoldLedger.Spec.«holding?/1»,ha,hc,Erlang.erlang.«is_integer/1»,Erlang.erlang.«element/2»,
      Erlang.erlang.«>/2»,Erlang.erlang.«>=/2»,Erlang.erlang.«=:=/2»,Erlang.erlang.«==/2»,HoldLedgerProof.compare_atoms,
      Lynx.Except.guard,Lynx.Except.tryWith,bind,Except.bind,Lynx.Term.true,Lynx.Term.false])
  case h_5 ev key =>
    cases key <;> try solve | simp [Elixir.HoldLedger.Spec.«expected_step/2»,Elixir.HoldLedger.Spec.«expect_request/3»,
      Elixir.HoldLedger.Spec.«expect_single/6»,Elixir.HoldLedger.Spec.«expect_choice/4»,Elixir.HoldLedger.Spec.«expect_void/2»,
      Elixir.HoldLedger.Ledger.«request/3»,Elixir.HoldLedger.Ledger.«dispatch/2»,Elixir.HoldLedger.Ledger.«timeout/2»,
      Elixir.HoldLedger.Ledger.«retry/2»,Elixir.HoldLedger.Ledger.«processor_result/3»,Elixir.HoldLedger.Ledger.«void/2»,
      Elixir.HoldLedger.Ledger.«transport_ack/2»,find_eq,replacement_eq,change_eq,normalize,
      Elixir.HoldLedger.Spec.«restated/2»,Elixir.HoldLedger.Spec.«hold_amount/1»,Elixir.HoldLedger.Spec.«hold_count/1»,
      Elixir.HoldLedger.Spec.«holding?/1»,ha,hc,Erlang.erlang.«is_integer/1»,Erlang.erlang.«element/2»,
      Erlang.erlang.«>/2»,Erlang.erlang.«>=/2»,Erlang.erlang.«=:=/2»,Erlang.erlang.«==/2»,HoldLedgerProof.compare_atoms,
      Lynx.Except.guard,Lynx.Except.tryWith,bind,Except.bind,Lynx.Term.true,Lynx.Term.false]
    rename_i kn
    rcases lookup_shape_1 entries (Lynx.Term.integer kn) hp with absent | ⟨ek,av,status,found,known⟩
    all_goals try simp_all [Elixir.HoldLedger.Spec.«expected_step/2»,Elixir.HoldLedger.Spec.«expect_request/3»,
      Elixir.HoldLedger.Spec.«expect_single/6»,Elixir.HoldLedger.Spec.«expect_choice/4»,Elixir.HoldLedger.Spec.«expect_void/2»,
      Elixir.HoldLedger.Ledger.«request/3»,Elixir.HoldLedger.Ledger.«dispatch/2»,Elixir.HoldLedger.Ledger.«timeout/2»,
      Elixir.HoldLedger.Ledger.«retry/2»,Elixir.HoldLedger.Ledger.«processor_result/3»,Elixir.HoldLedger.Ledger.«void/2»,
      Elixir.HoldLedger.Ledger.«transport_ack/2»,find_eq,replacement_eq,change_eq,normalize,
      Elixir.HoldLedger.Spec.«restated/2»,Elixir.HoldLedger.Spec.«hold_amount/1»,Elixir.HoldLedger.Spec.«hold_count/1»,
      Elixir.HoldLedger.Spec.«holding?/1»,ha,hc,Erlang.erlang.«is_integer/1»,Erlang.erlang.«element/2»,
      Erlang.erlang.«>/2»,Erlang.erlang.«>=/2»,Erlang.erlang.«=:=/2»,Erlang.erlang.«==/2»,HoldLedgerProof.compare_atoms,
      Lynx.Except.guard,Lynx.Except.tryWith,bind,Except.bind,Lynx.Term.true,Lynx.Term.false]
    all_goals repeat' (split at * <;> (repeat' split_conjunction) <;> subst_vars <;> try simp_all [Elixir.HoldLedger.Spec.«expected_step/2»,Elixir.HoldLedger.Spec.«expect_request/3»,
      Elixir.HoldLedger.Spec.«expect_single/6»,Elixir.HoldLedger.Spec.«expect_choice/4»,Elixir.HoldLedger.Spec.«expect_void/2»,
      Elixir.HoldLedger.Ledger.«request/3»,Elixir.HoldLedger.Ledger.«dispatch/2»,Elixir.HoldLedger.Ledger.«timeout/2»,
      Elixir.HoldLedger.Ledger.«retry/2»,Elixir.HoldLedger.Ledger.«processor_result/3»,Elixir.HoldLedger.Ledger.«void/2»,
      Elixir.HoldLedger.Ledger.«transport_ack/2»,find_eq,replacement_eq,change_eq,normalize,
      Elixir.HoldLedger.Spec.«restated/2»,Elixir.HoldLedger.Spec.«hold_amount/1»,Elixir.HoldLedger.Spec.«hold_count/1»,
      Elixir.HoldLedger.Spec.«holding?/1»,ha,hc,Erlang.erlang.«is_integer/1»,Erlang.erlang.«element/2»,
      Erlang.erlang.«>/2»,Erlang.erlang.«>=/2»,Erlang.erlang.«=:=/2»,Erlang.erlang.«==/2»,HoldLedgerProof.compare_atoms,
      Lynx.Except.guard,Lynx.Except.tryWith,bind,Except.bind,Lynx.Term.true,Lynx.Term.false])
  case h_6 ev key outcome =>
    cases key <;> try solve | simp [Elixir.HoldLedger.Spec.«expected_step/2»,Elixir.HoldLedger.Spec.«expect_request/3»,
      Elixir.HoldLedger.Spec.«expect_single/6»,Elixir.HoldLedger.Spec.«expect_choice/4»,Elixir.HoldLedger.Spec.«expect_void/2»,
      Elixir.HoldLedger.Ledger.«request/3»,Elixir.HoldLedger.Ledger.«dispatch/2»,Elixir.HoldLedger.Ledger.«timeout/2»,
      Elixir.HoldLedger.Ledger.«retry/2»,Elixir.HoldLedger.Ledger.«processor_result/3»,Elixir.HoldLedger.Ledger.«void/2»,
      Elixir.HoldLedger.Ledger.«transport_ack/2»,find_eq,replacement_eq,change_eq,normalize,
      Elixir.HoldLedger.Spec.«restated/2»,Elixir.HoldLedger.Spec.«hold_amount/1»,Elixir.HoldLedger.Spec.«hold_count/1»,
      Elixir.HoldLedger.Spec.«holding?/1»,ha,hc,Erlang.erlang.«is_integer/1»,Erlang.erlang.«element/2»,
      Erlang.erlang.«>/2»,Erlang.erlang.«>=/2»,Erlang.erlang.«=:=/2»,Erlang.erlang.«==/2»,HoldLedgerProof.compare_atoms,
      Lynx.Except.guard,Lynx.Except.tryWith,bind,Except.bind,Lynx.Term.true,Lynx.Term.false]
    rename_i kn
    rcases lookup_shape_1 entries (Lynx.Term.integer kn) hp with absent | ⟨ek,av,status,found,known⟩
    all_goals try simp_all [Elixir.HoldLedger.Spec.«expected_step/2»,Elixir.HoldLedger.Spec.«expect_request/3»,
      Elixir.HoldLedger.Spec.«expect_single/6»,Elixir.HoldLedger.Spec.«expect_choice/4»,Elixir.HoldLedger.Spec.«expect_void/2»,
      Elixir.HoldLedger.Ledger.«request/3»,Elixir.HoldLedger.Ledger.«dispatch/2»,Elixir.HoldLedger.Ledger.«timeout/2»,
      Elixir.HoldLedger.Ledger.«retry/2»,Elixir.HoldLedger.Ledger.«processor_result/3»,Elixir.HoldLedger.Ledger.«void/2»,
      Elixir.HoldLedger.Ledger.«transport_ack/2»,find_eq,replacement_eq,change_eq,normalize,
      Elixir.HoldLedger.Spec.«restated/2»,Elixir.HoldLedger.Spec.«hold_amount/1»,Elixir.HoldLedger.Spec.«hold_count/1»,
      Elixir.HoldLedger.Spec.«holding?/1»,ha,hc,Erlang.erlang.«is_integer/1»,Erlang.erlang.«element/2»,
      Erlang.erlang.«>/2»,Erlang.erlang.«>=/2»,Erlang.erlang.«=:=/2»,Erlang.erlang.«==/2»,HoldLedgerProof.compare_atoms,
      Lynx.Except.guard,Lynx.Except.tryWith,bind,Except.bind,Lynx.Term.true,Lynx.Term.false]
    all_goals repeat' (split at * <;> (repeat' split_conjunction) <;> subst_vars <;> try simp_all [Elixir.HoldLedger.Spec.«expected_step/2»,Elixir.HoldLedger.Spec.«expect_request/3»,
      Elixir.HoldLedger.Spec.«expect_single/6»,Elixir.HoldLedger.Spec.«expect_choice/4»,Elixir.HoldLedger.Spec.«expect_void/2»,
      Elixir.HoldLedger.Ledger.«request/3»,Elixir.HoldLedger.Ledger.«dispatch/2»,Elixir.HoldLedger.Ledger.«timeout/2»,
      Elixir.HoldLedger.Ledger.«retry/2»,Elixir.HoldLedger.Ledger.«processor_result/3»,Elixir.HoldLedger.Ledger.«void/2»,
      Elixir.HoldLedger.Ledger.«transport_ack/2»,find_eq,replacement_eq,change_eq,normalize,
      Elixir.HoldLedger.Spec.«restated/2»,Elixir.HoldLedger.Spec.«hold_amount/1»,Elixir.HoldLedger.Spec.«hold_count/1»,
      Elixir.HoldLedger.Spec.«holding?/1»,ha,hc,Erlang.erlang.«is_integer/1»,Erlang.erlang.«element/2»,
      Erlang.erlang.«>/2»,Erlang.erlang.«>=/2»,Erlang.erlang.«=:=/2»,Erlang.erlang.«==/2»,HoldLedgerProof.compare_atoms,
      Lynx.Except.guard,Lynx.Except.tryWith,bind,Except.bind,Lynx.Term.true,Lynx.Term.false])
  case h_7 ev key =>
    cases key <;> try solve | simp [Elixir.HoldLedger.Spec.«expected_step/2»,Elixir.HoldLedger.Spec.«expect_request/3»,
      Elixir.HoldLedger.Spec.«expect_single/6»,Elixir.HoldLedger.Spec.«expect_choice/4»,Elixir.HoldLedger.Spec.«expect_void/2»,
      Elixir.HoldLedger.Ledger.«request/3»,Elixir.HoldLedger.Ledger.«dispatch/2»,Elixir.HoldLedger.Ledger.«timeout/2»,
      Elixir.HoldLedger.Ledger.«retry/2»,Elixir.HoldLedger.Ledger.«processor_result/3»,Elixir.HoldLedger.Ledger.«void/2»,
      Elixir.HoldLedger.Ledger.«transport_ack/2»,find_eq,replacement_eq,change_eq,normalize,
      Elixir.HoldLedger.Spec.«restated/2»,Elixir.HoldLedger.Spec.«hold_amount/1»,Elixir.HoldLedger.Spec.«hold_count/1»,
      Elixir.HoldLedger.Spec.«holding?/1»,ha,hc,Erlang.erlang.«is_integer/1»,Erlang.erlang.«element/2»,
      Erlang.erlang.«>/2»,Erlang.erlang.«>=/2»,Erlang.erlang.«=:=/2»,Erlang.erlang.«==/2»,HoldLedgerProof.compare_atoms,
      Lynx.Except.guard,Lynx.Except.tryWith,bind,Except.bind,Lynx.Term.true,Lynx.Term.false]
    rename_i kn
    rcases lookup_shape_1 entries (Lynx.Term.integer kn) hp with absent | ⟨ek,av,status,found,known⟩
    all_goals try simp_all [Elixir.HoldLedger.Spec.«expected_step/2»,Elixir.HoldLedger.Spec.«expect_request/3»,
      Elixir.HoldLedger.Spec.«expect_single/6»,Elixir.HoldLedger.Spec.«expect_choice/4»,Elixir.HoldLedger.Spec.«expect_void/2»,
      Elixir.HoldLedger.Ledger.«request/3»,Elixir.HoldLedger.Ledger.«dispatch/2»,Elixir.HoldLedger.Ledger.«timeout/2»,
      Elixir.HoldLedger.Ledger.«retry/2»,Elixir.HoldLedger.Ledger.«processor_result/3»,Elixir.HoldLedger.Ledger.«void/2»,
      Elixir.HoldLedger.Ledger.«transport_ack/2»,find_eq,replacement_eq,change_eq,normalize,
      Elixir.HoldLedger.Spec.«restated/2»,Elixir.HoldLedger.Spec.«hold_amount/1»,Elixir.HoldLedger.Spec.«hold_count/1»,
      Elixir.HoldLedger.Spec.«holding?/1»,ha,hc,Erlang.erlang.«is_integer/1»,Erlang.erlang.«element/2»,
      Erlang.erlang.«>/2»,Erlang.erlang.«>=/2»,Erlang.erlang.«=:=/2»,Erlang.erlang.«==/2»,HoldLedgerProof.compare_atoms,
      Lynx.Except.guard,Lynx.Except.tryWith,bind,Except.bind,Lynx.Term.true,Lynx.Term.false]
    all_goals repeat' (split at * <;> (repeat' split_conjunction) <;> subst_vars <;> try simp_all [Elixir.HoldLedger.Spec.«expected_step/2»,Elixir.HoldLedger.Spec.«expect_request/3»,
      Elixir.HoldLedger.Spec.«expect_single/6»,Elixir.HoldLedger.Spec.«expect_choice/4»,Elixir.HoldLedger.Spec.«expect_void/2»,
      Elixir.HoldLedger.Ledger.«request/3»,Elixir.HoldLedger.Ledger.«dispatch/2»,Elixir.HoldLedger.Ledger.«timeout/2»,
      Elixir.HoldLedger.Ledger.«retry/2»,Elixir.HoldLedger.Ledger.«processor_result/3»,Elixir.HoldLedger.Ledger.«void/2»,
      Elixir.HoldLedger.Ledger.«transport_ack/2»,find_eq,replacement_eq,change_eq,normalize,
      Elixir.HoldLedger.Spec.«restated/2»,Elixir.HoldLedger.Spec.«hold_amount/1»,Elixir.HoldLedger.Spec.«hold_count/1»,
      Elixir.HoldLedger.Spec.«holding?/1»,ha,hc,Erlang.erlang.«is_integer/1»,Erlang.erlang.«element/2»,
      Erlang.erlang.«>/2»,Erlang.erlang.«>=/2»,Erlang.erlang.«=:=/2»,Erlang.erlang.«==/2»,HoldLedgerProof.compare_atoms,
      Lynx.Except.guard,Lynx.Except.tryWith,bind,Except.bind,Lynx.Term.true,Lynx.Term.false])
  case h_8 ev key =>
    cases key <;> simp [Elixir.HoldLedger.Spec.«expected_step/2»,Elixir.HoldLedger.Ledger.«transport_ack/2»,
      normalize,Elixir.HoldLedger.Spec.«restated/2»,ha,hc,Erlang.erlang.«is_integer/1»,Erlang.erlang.«element/2»,
      Lynx.Except.guard,Lynx.Except.tryWith,bind,Except.bind]
  case h_4 =>
    simp [Elixir.HoldLedger.Spec.«expected_step/2»,Elixir.HoldLedger.Ledger.«restart/1»,normalize,unknown_sent_eq,restart_eq,
      Elixir.HoldLedger.Spec.«restated/2»,Erlang.erlang.«element/2»,bind,Except.bind]
  case h_9 =>
    simp only [Elixir.HoldLedger.Spec.«expected_step/2»,normalize,Elixir.HoldLedger.Spec.«restated/2»,ha,hc,
      Erlang.erlang.«element/2»,bind,Except.bind]
    all_goals repeat' (split <;> try simp_all [bind,Except.bind,Lynx.Term.true,Lynx.Term.false])

theorem step_agrees (s event : Lynx.Term)
    (valid : Elixir.HoldLedger.Spec.«valid?/1» s = Except.ok Lynx.Term.true) :
    ∃ next result effects,
      Elixir.HoldLedger.Ledger.«step/2» s event = Except.ok (Lynx.Term.tuple #[next,result,effects]) ∧
      Elixir.HoldLedger.Spec.«expected_step/2» s event = Except.ok (Lynx.Term.tuple #[next,result,effects]) ∧
      Elixir.HoldLedger.Spec.«valid?/1» next = Except.ok Lynx.Term.true := by
  have preserved := Elixir.HoldLedger.ProofContracts.«po_s/2» s event valid
  change (do let output ← Elixir.HoldLedger.Ledger.«step/2» s event
             let next ← Erlang.erlang.«element/2» (Lynx.Term.integer 1) output
             Elixir.HoldLedger.Spec.«valid?/1» next) = Except.ok Lynx.Term.true at preserved
  cases step : Elixir.HoldLedger.Ledger.«step/2» s event with
  | error err => simp [step,bind,Except.bind] at preserved
  | ok output =>
    obtain ⟨next,result,effects,rfl⟩ := step_shape s event output step
    have successor : Elixir.HoldLedger.Spec.«valid?/1» next = Except.ok Lynx.Term.true := by
      simpa [step,Erlang.erlang.«element/2»,bind,Except.bind] using preserved
    refine ⟨next,result,effects,rfl,?_,successor⟩
    rw [oracle_normalized s event valid,step]
    simpa [bind,Except.bind] using normalize_valid next result effects successor

end HoldLedgerProof
