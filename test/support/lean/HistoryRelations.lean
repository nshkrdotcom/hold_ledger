module

public import Elixir.HoldLedger.ProofContracts
public import HoldLedgerProof.CoreLookup
public import HoldLedgerProof.CorePreservation

public section
set_option maxHeartbeats 4000000
namespace HoldLedgerProof

theorem unique_view (entries : Lynx.Term)
    (unique : Elixir.HoldLedger.Spec.«unique_keys?/1» entries = Except.ok Lynx.Term.true) :
    Elixir.HoldLedger.Spec.«unique_keys_seen?/2» entries Lynx.Term.nil = Except.ok Lynx.Term.true := by
  simp only [Elixir.HoldLedger.Spec.«unique_keys?/1»,Lynx.Except.guard,Lynx.Except.tryWith] at unique
  all_goals repeat' (split at unique <;> try simp_all [Lynx.Term.true])

theorem identity_lookup (es dst key amount old : Lynx.Term)
    (proper : Elixir.HoldLedger.Spec.«proper_entries?/1» es = Except.ok Lynx.Term.true)
    (identities : Elixir.HoldLedger.Spec.«identities_present?/2» es dst = Except.ok Lynx.Term.true)
    (lookup : Elixir.HoldLedger.Spec.«lookup/2» es key =
      Except.ok (Lynx.Term.tuple #[Lynx.Term.atom "ok", Lynx.Term.tuple #[key,amount,old]])) :
    ∃ newer, Elixir.HoldLedger.Spec.«lookup/2» dst key =
      Except.ok (Lynx.Term.tuple #[Lynx.Term.atom "ok", Lynx.Term.tuple #[key,amount,newer]]) := by
  fun_induction Elixir.HoldLedger.Spec.«lookup/2» es key generalizing dst amount old
  all_goals simp only [Elixir.HoldLedger.Spec.«proper_entries?/1»,
    Lynx.Except.guard,Lynx.Except.tryWith,bind,Except.bind] at proper
  all_goals repeat' (split at proper <;> try simp_all [Lynx.Term.true])
  all_goals try simp only [Erlang.erlang.«==/2»,bind,Except.bind] at lookup
  all_goals repeat' (split at lookup <;> (repeat' split_conjunction) <;> subst_vars <;>
    try simp_all [Elixir.HoldLedger.Spec.«identities_present?/2»,Lynx.Except.guard,Lynx.Except.tryWith,Erlang.erlang.«=:=/2»,Erlang.erlang.«and/2»,Erlang.erlang.«is_integer/1»,bind,Except.bind,Lynx.Term.true,Lynx.Term.false])
  all_goals try simp only [Elixir.HoldLedger.Spec.«identities_present?/2»] at identities
  all_goals repeat' (split at identities <;> (repeat' split_conjunction) <;> subst_vars <;>
    try simp_all [])

  all_goals try simp_all [
    Lynx.Term.true]
  all_goals repeat' (split at * <;> (repeat' split_conjunction) <;> subst_vars <;>
    try simp_all [])
  all_goals first | exact ⟨_,by assumption⟩ | solve_by_elim

theorem identities_trans (es middle dst : Lynx.Term)
    (proper : Elixir.HoldLedger.Spec.«proper_entries?/1» es = Except.ok Lynx.Term.true)
    (middle_proper : Elixir.HoldLedger.Spec.«proper_entries?/1» middle = Except.ok Lynx.Term.true)
    (unique : Elixir.HoldLedger.Spec.«unique_keys_seen?/2» es Lynx.Term.nil = Except.ok Lynx.Term.true)
    (first : Elixir.HoldLedger.Spec.«identities_present?/2» es middle = Except.ok Lynx.Term.true)
    (second : Elixir.HoldLedger.Spec.«identities_present?/2» middle dst = Except.ok Lynx.Term.true) :
    Elixir.HoldLedger.Spec.«identities_present?/2» es dst = Except.ok Lynx.Term.true := by
  apply identities_1 es Lynx.Term.nil dst unique
  intro key amount old _ lookup
  obtain ⟨newer,hfirst⟩ := identity_lookup es middle key amount old proper first lookup
  exact identity_lookup middle dst key amount newer middle_proper second hfirst

theorem terminal_entries (es seen dst : Lynx.Term)
    (unique : Elixir.HoldLedger.Spec.«unique_keys_seen?/2» es seen = Except.ok Lynx.Term.true)
    (map : ∀ key amount status,
      Elixir.HoldLedger.Spec.«seen?/2» seen key = Except.ok Lynx.Term.false →
      Elixir.HoldLedger.Spec.«lookup/2» es key =
        Except.ok (Lynx.Term.tuple #[Lynx.Term.atom "ok",Lynx.Term.tuple #[key,amount,status]]) →
      (status = Lynx.Term.atom "declined" ∨ status = Lynx.Term.atom "voided") →
      Elixir.HoldLedger.Spec.«lookup/2» dst key =
        Except.ok (Lynx.Term.tuple #[Lynx.Term.atom "ok",Lynx.Term.tuple #[key,amount,status]])) :
    Elixir.HoldLedger.Spec.«terminal_entries_preserved?/2» es dst = Except.ok Lynx.Term.true := by
  fun_induction Elixir.HoldLedger.Spec.«unique_keys_seen?/2» es seen generalizing dst
  all_goals try simp only [bind,Except.bind] at unique
  all_goals repeat' (split at unique <;> try simp_all [Lynx.Term.true,Lynx.Term.false])
  all_goals try simp_all [Elixir.HoldLedger.Spec.«terminal_entries_preserved?/2»]
  rename_i seen n amount old rest x generated ih heq
  have tail : Elixir.HoldLedger.Spec.«terminal_entries_preserved?/2» rest dst = Except.ok Lynx.Term.true := by
    apply ih dst
    intro key amount status hs hl ht
    simp only [Elixir.HoldLedger.Spec.«seen?/2»,Erlang.erlang.«==/2»,bind,Except.bind] at hs
    by_cases equal : (Lynx.Term.integer n).compare key = Ordering.eq
    · simp [equal] at hs
    · have hs' : Elixir.HoldLedger.Spec.«seen?/2» seen key = Except.ok Lynx.Term.false := by
        simpa [equal,Lynx.Term.false] using hs
      apply map key amount status hs'
      · simpa [Elixir.HoldLedger.Spec.«lookup/2»,Erlang.erlang.«==/2»,bind,Except.bind,equal] using hl
      · exact ht
  by_cases declined : old = Lynx.Term.atom "declined"
  · subst old
    have head := map (Lynx.Term.integer n) amount (Lynx.Term.atom "declined") heq
      (by simp [Elixir.HoldLedger.Spec.«lookup/2»,Erlang.erlang.«==/2»]) (Or.inl rfl)
    simp [Elixir.HoldLedger.Spec.«terminal?/1»,head,tail,
      Erlang.erlang.«==/2»]
  · by_cases voided : old = Lynx.Term.atom "voided"
    · subst old
      have head := map (Lynx.Term.integer n) amount (Lynx.Term.atom "voided") heq
        (by simp [Elixir.HoldLedger.Spec.«lookup/2»,Erlang.erlang.«==/2»]) (Or.inr rfl)
      simp [Elixir.HoldLedger.Spec.«terminal?/1»,head,tail,
        Erlang.erlang.«==/2»]
    · simp [Elixir.HoldLedger.Spec.«terminal?/1»,tail]

end HoldLedgerProof
