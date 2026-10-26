module

public import Elixir.HoldLedger.ProofContracts
public import HoldLedgerProof.Induction
public import HoldLedgerProof.CoreAccounting

public section
set_option maxHeartbeats 16000000

theorem HoldLedgerProof.valid_view_1 : ∀ state, Elixir.HoldLedger.Spec.«valid?/1» state = Except.ok Lynx.Term.true →
    ∃ (al hl ua uh : Int) (es : Lynx.Term),
      state = Lynx.Term.tuple #[Lynx.Term.integer al, Lynx.Term.integer hl,
        Lynx.Term.integer ua, Lynx.Term.integer uh, es] ∧
      Elixir.HoldLedger.Spec.«proper_entries?/1» es = Except.ok Lynx.Term.true ∧
      Elixir.HoldLedger.Spec.«unique_keys?/1» es = Except.ok Lynx.Term.true ∧
      Elixir.HoldLedger.Spec.«hold_amount/1» es = Except.ok (Lynx.Term.integer ua) ∧
      Elixir.HoldLedger.Spec.«hold_count/1» es = Except.ok (Lynx.Term.integer uh) ∧
      0 ≤ al ∧ 0 ≤ hl ∧ 0 ≤ ua ∧ 0 ≤ uh ∧ ua ≤ al ∧ uh ≤ hl := by
  intro state h
  simp only [Elixir.HoldLedger.Spec.«valid?/1», Elixir.HoldLedger.Spec.«nonnegative_state_valid?/5»,
    Lynx.Except.guard, Lynx.Except.tryWith, bind, Except.bind] at h
  all_goals repeat' (split at h <;> try simp_all [Lynx.Term.true])
  all_goals repeat' (split at * <;> try simp_all [])
  all_goals simp only [Erlang.erlang.«is_integer/1», bind, Except.bind] at *
  all_goals repeat' (split at * <;> try simp_all [Lynx.Term.true, Lynx.Term.false])
  all_goals obtain ⟨⟨a, ha⟩, c, hc⟩ := HoldLedgerProof.totals_1 _ (by assumption)
  all_goals simp_all [Erlang.erlang.«==/2», Lynx.Term.true, Lynx.Term.false]
  all_goals repeat' (split at * <;> try simp_all [Lynx.Term.true, Lynx.Term.false])
  all_goals subst_vars
  all_goals try simp_all []
  all_goals repeat' split_conjunction
  all_goals refine ⟨_, _, _, _, _, (by exact ⟨rfl, rfl, rfl, rfl, rfl⟩), ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_⟩ <;> first | assumption | omega
