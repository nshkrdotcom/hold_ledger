module
public import HoldLedgerProof.Retention
public import HoldLedgerProof.Oracle
public import Init.Data.List.Int.Sum

public section
set_option maxHeartbeats 16000000
namespace HoldLedgerProof.Exposure

abbrev protectedStatus (status : Lynx.Term) : Prop :=
  status = .atom "sent" ∨ status = .atom "unknown" ∨
    status = .atom "authorized" ∨ status = .atom "voiding"

/-- A capacity-holding entry that has passed dispatch. This is a local-state
    predicate; processor causality supplies its initial witness at authorization. -/
@[expose] def Protected (state : Lynx.Term) (key amount : Int) : Prop :=
  Elixir.HoldLedger.Spec.«valid?/1» state = Except.ok Lynx.Term.true ∧
  ∃ al hl ua uh entries status,
    state = Lynx.Term.tuple #[.integer al,.integer hl,.integer ua,.integer uh,entries] ∧
    Elixir.HoldLedger.Spec.«lookup/2» entries (.integer key) =
      Except.ok (.tuple #[.atom "ok",.tuple #[.integer key,.integer amount,status]]) ∧
    protectedStatus status

/-- Truthful declines and terminal void confirmations exclude a still-live remote
    authorization. The processor must preserve this exclusion against late delivery. -/
@[expose] def NoRelease (key : Int) (events : List Lynx.Term) : Prop :=
  ∀ event ∈ events,
    event ≠ .tuple #[.atom "processor_result",.integer key,.atom "declined"] ∧
    event ≠ .tuple #[.atom "void_confirmed",.integer key]

theorem protected_view {state : Lynx.Term} {key amount : Int}
    (valid : Elixir.HoldLedger.Spec.«valid?/1» state = Except.ok Lynx.Term.true)
    (exposed : Elixir.HoldLedger.Spec.«exposed_entry?/3» state (.integer key) (.integer amount) =
      Except.ok Lynx.Term.true) : Protected state key amount := by
  obtain ⟨al,hl,ua,uh,entries,rfl,hp,hu,ha,hc,hal,hhl,hua,huh,hacap,hhcap⟩ := valid_view_1 state valid
  refine ⟨valid, ?_⟩
  rcases lookup_shape_1 entries (.integer key) hp with absent | ⟨stored,amt,status,found,known⟩
  · simp [Elixir.HoldLedger.Spec.«exposed_entry?/3»,absent] at exposed
  · by_cases same_key : stored = key
    · by_cases same_amount : amt = amount
      · subst stored
        subst amt
        refine ⟨al,hl,ua,uh,entries,status,rfl,found,?_⟩
        simp [Elixir.HoldLedger.Spec.«exposed_entry?/3»,found,Erlang.erlang.«=:=/2»,
          Erlang.erlang.«and/2»,
          Lynx.Term.true] at exposed
        by_cases hs : status = .atom "sent"
        all_goals by_cases hu : status = .atom "unknown"
        all_goals by_cases ha : status = .atom "authorized"
        all_goals simp_all [protectedStatus]
      · simp [Elixir.HoldLedger.Spec.«exposed_entry?/3»,found,same_amount,same_key,
          Erlang.erlang.«=:=/2»,Erlang.erlang.«and/2»,
          Lynx.Term.true,Lynx.Term.false] at exposed
    · by_cases same_amount : amt = amount
      all_goals simp [Elixir.HoldLedger.Spec.«exposed_entry?/3»,found,same_key,same_amount,
        Erlang.erlang.«=:=/2»,Erlang.erlang.«and/2»,
        Lynx.Term.true,Lynx.Term.false] at exposed

theorem protected_step {state event : Lynx.Term} {key amount : Int}
    (before : Protected state key amount)
    (no_decline : event ≠ .tuple #[.atom "processor_result",.integer key,.atom "declined"])
    (no_confirmation : event ≠ .tuple #[.atom "void_confirmed",.integer key]) :
    ∃ next result effects,
      Elixir.HoldLedger.Ledger.«step/2» state event = Except.ok (.tuple #[next,result,effects]) ∧
      Protected next key amount := by
  obtain ⟨valid,al,hl,ua,uh,entries,status,rfl,found,known⟩ := before
  obtain ⟨_,_,_,_,_,shape,hp,_,_,_,_,_,_,_,_,_⟩ := valid_view_1 _ valid
  simp at shape
  obtain ⟨rfl,rfl,rfl,rfl,rfl⟩ := shape
  obtain ⟨next,result,effects,applied,oracle,successor⟩ := step_agrees _ event valid
  have held := retained_lookup al hl ua uh key amount entries status event hp found known no_decline no_confirmation
  have exposed : Elixir.HoldLedger.Spec.«exposed_entry?/3» next (.integer key) (.integer amount) =
      Except.ok Lynx.Term.true := by
    simpa [applied,Erlang.erlang.«element/2»,bind,Except.bind] using held
  exact ⟨next,result,effects,applied,protected_view successor exposed⟩

theorem retained_history {events : List Lynx.Term} {state : Lynx.Term} {key amount : Int}
    (before : Protected state key amount) (processor : NoRelease key events) :
    ∃ final, Elixir.HoldLedger.Ledger.«run/2» state (Lynx.Term.list events) = Except.ok final ∧
      Protected final key amount := by
  induction events generalizing state with
  | nil => exact ⟨state,rfl,before⟩
  | cons event events ih =>
      obtain ⟨no_decline,no_confirmation⟩ := processor event (by simp)
      obtain ⟨next,result,effects,applied,kept⟩ := protected_step before no_decline no_confirmation
      have tail : NoRelease key events := by
        intro event member
        exact processor event (by simp [member])
      obtain ⟨final,replayed,still_held⟩ := ih kept tail
      refine ⟨final,?_,still_held⟩
      simpa [Lynx.Term.list,Elixir.HoldLedger.Ledger.«run/2»,applied,bind,Except.bind] using replayed

end HoldLedgerProof.Exposure
