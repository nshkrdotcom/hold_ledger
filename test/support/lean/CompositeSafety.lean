module
public import HoldLedgerProof.CompositeInvariant
public import HoldLedgerProof.Voiding
public import HoldLedgerProof.Recovery

public section
namespace HoldLedgerProof.CompositeSafety
open HoldLedgerProof.Outbox

/-- Decompose the full independent invariant without dropping metadata checks or
    the physical walk requiring every voiding entry to have an obligation. -/
theorem composite_view (state : Lynx.Term) :
    Elixir.HoldLedger.Spec.«composite_valid?/1» state = Except.ok Lynx.Term.true ↔
    ∃ (ledger : Lynx.Term) (obligations : List Obligation) (entries : Lynx.Term),
      state = .tuple #[ledger,encode obligations] ∧
      Elixir.HoldLedger.Spec.«valid?/1» ledger = Except.ok Lynx.Term.true ∧
      Erlang.erlang.«element/2» (.integer 5) ledger = Except.ok entries ∧
      Elixir.HoldLedger.Spec.«obligations_valid?/3» (encode obligations) entries .nil = Except.ok Lynx.Term.true ∧
      Elixir.HoldLedger.Spec.«all_voiding_present?/2» entries (encode obligations) = Except.ok Lynx.Term.true := by
  constructor
  · intro valid
    obtain ⟨ledger,items,entries,shape,proper,located,obligations,all_present⟩ := CompositeInvariant.components state valid
    obtain ⟨encoded,rfl⟩ := CompositeInvariant.obligation_shape items entries .nil obligations
    exact ⟨ledger,encoded,entries,shape,proper,located,obligations,all_present⟩
  · rintro ⟨ledger,items,entries,rfl,proper,located,obligations,all_present⟩
    exact CompositeInvariant.assemble ledger (encode items) entries proper located obligations all_present

theorem init_valid (amount slots : Int) (amount_nonnegative : 0 ≤ amount) (slots_nonnegative : 0 ≤ slots) :
    (do let state ← Elixir.HoldLedger.Composite.«init/2» (.integer amount) (.integer slots)
        Elixir.HoldLedger.Spec.«composite_valid?/1» state) = Except.ok Lynx.Term.true := by
  simp [Elixir.HoldLedger.Composite.«init/2»,Elixir.HoldLedger.Ledger.«init/2»,
    Elixir.HoldLedger.Spec.«composite_valid?/1»,Elixir.HoldLedger.Spec.«valid?/1»,
    Elixir.HoldLedger.Spec.«nonnegative_state_valid?/5»,Elixir.HoldLedger.Spec.«proper_entries?/1»,
    Elixir.HoldLedger.Spec.«unique_keys?/1»,Elixir.HoldLedger.Spec.«unique_keys_seen?/2»,
    Elixir.HoldLedger.Spec.«hold_amount/1»,Elixir.HoldLedger.Spec.«hold_count/1»,
    Elixir.HoldLedger.Spec.«obligations_valid?/3»,Elixir.HoldLedger.Spec.«all_voiding_present?/2»,
    Erlang.erlang.«is_integer/1»,Erlang.erlang.«is_list/1»,Erlang.erlang.«==/2»,Erlang.erlang.«>=/2»,
    Erlang.erlang.«element/2»,Int.isGE_compare,
    amount_nonnegative,slots_nonnegative,
    Lynx.Term.true]

theorem metadata_agrees (ledger next event result effects : Lynx.Term) (items : List Obligation)
    (applied : Elixir.HoldLedger.Ledger.«step/2» ledger event = Except.ok (.tuple #[next,result,effects]))
    (oracle : Elixir.HoldLedger.Spec.«expected_step/2» ledger event = Except.ok (.tuple #[next,result,effects]))
    (ignored : Elixir.HoldLedger.Composite.«open_effects/2» effects (encode items) = Except.ok (encode items))
    (not_voiding : result ≠ .atom "voiding") :
    Elixir.HoldLedger.Composite.«step/2» (.tuple #[ledger,encode items]) event =
      Elixir.HoldLedger.Spec.«expected_composite_step/2» (.tuple #[ledger,encode items]) event := by
  by_cases confirmation : ∃ key, event = .tuple #[.atom "void_confirmed",key] ∧ result = .atom "voided"
  · obtain ⟨key,rfl,rfl⟩ := confirmation
    simp [Elixir.HoldLedger.Composite.«step/2»,Elixir.HoldLedger.Spec.«expected_composite_step/2»,
      applied,oracle,ignored,remove_oracle,bind,Except.bind]
  · by_cases attempt : ∃ key, event = .tuple #[.atom "void_attempt",key]
    · obtain ⟨key,rfl⟩ := attempt
      simp [Elixir.HoldLedger.Composite.«step/2»,Elixir.HoldLedger.Spec.«expected_composite_step/2»,
        applied,oracle,ignored,fold_attempt,bind,Except.bind]
    · by_cases retry : ∃ key, event = .tuple #[.atom "void_retry_enabled",key]
      · obtain ⟨key,rfl⟩ := retry
        simp [Elixir.HoldLedger.Composite.«step/2»,Elixir.HoldLedger.Spec.«expected_composite_step/2»,
          applied,oracle,ignored,fold_retry,bind,Except.bind]
      · by_cases outcome : ∃ key reason, event = .tuple #[.atom "void_outcome",key,.tuple #[.atom "error",reason]]
        · obtain ⟨key,reason,rfl⟩ := outcome
          rcases outcome_boolean reason with yes | no
          · simp [Elixir.HoldLedger.Composite.«step/2»,Elixir.HoldLedger.Spec.«expected_composite_step/2»,
              applied,oracle,ignored,fold_outcome_allowed items key reason yes,yes,
              bind,Except.bind]
          · simp [Elixir.HoldLedger.Composite.«step/2»,Elixir.HoldLedger.Spec.«expected_composite_step/2»,
              applied,oracle,ignored,fold_outcome_rejected items key reason no,no]
        · have unchanged := fold_other items event
            (by intro key equal; exact attempt ⟨key,equal⟩)
            (by intro key equal; exact retry ⟨key,equal⟩)
            (by intro key reason equal; exact outcome ⟨key,reason,equal⟩)
          simp only [Elixir.HoldLedger.Composite.«step/2»,Elixir.HoldLedger.Spec.«expected_composite_step/2»,
            applied,oracle,ignored,bind,Except.bind]
          repeat' (split <;> try simp_all [])
          all_goals simp_all [unchanged,bind,Except.bind]

theorem preserve_unchanged (ledger next before after event result : Lynx.Term) (items : List Obligation)
    (valid : Elixir.HoldLedger.Spec.«composite_valid?/1» (.tuple #[ledger,encode items]) = Except.ok Lynx.Term.true)
    (ledger_valid : Elixir.HoldLedger.Spec.«valid?/1» ledger = Except.ok Lynx.Term.true)
    (next_valid : Elixir.HoldLedger.Spec.«valid?/1» next = Except.ok Lynx.Term.true)
    (old_located : Erlang.erlang.«element/2» (.integer 5) ledger = Except.ok before)
    (new_located : Erlang.erlang.«element/2» (.integer 5) next = Except.ok after)
    (frame : Voiding.Frame before after event result)
    (no_open : ∀ key : Int, ¬(event = .tuple #[.atom "void",.integer key] ∧ result = .atom "voiding"))
    (no_close : ∀ key : Int, ¬(event = .tuple #[.atom "void_confirmed",.integer key] ∧ result = .atom "voided")) :
    Elixir.HoldLedger.Spec.«composite_valid?/1» (.tuple #[next,encode items]) = Except.ok Lynx.Term.true := by
  obtain ⟨well,coupled⟩ := (CompositeInvariant.full_view ledger items before ledger_valid old_located).mp valid
  apply (CompositeInvariant.full_view next items after next_valid new_located).mpr
  refine ⟨well,?_⟩
  intro key
  rw [frame key]
  simpa [no_open key,no_close key] using coupled key

theorem preserve_change (ledger next before after event result target : Lynx.Term) (items : List Obligation) (action : Change)
    (valid : Elixir.HoldLedger.Spec.«composite_valid?/1» (.tuple #[ledger,encode items]) = Except.ok Lynx.Term.true)
    (ledger_valid : Elixir.HoldLedger.Spec.«valid?/1» ledger = Except.ok Lynx.Term.true)
    (next_valid : Elixir.HoldLedger.Spec.«valid?/1» next = Except.ok Lynx.Term.true)
    (old_located : Erlang.erlang.«element/2» (.integer 5) ledger = Except.ok before)
    (new_located : Erlang.erlang.«element/2» (.integer 5) next = Except.ok after)
    (frame : Voiding.Frame before after event result)
    (allowed : action.allowed)
    (no_open : ∀ key : Int, ¬(event = .tuple #[.atom "void",.integer key] ∧ result = .atom "voiding"))
    (closing : ∀ key : Int, (event = .tuple #[.atom "void_confirmed",.integer key] ∧ result = .atom "voided") ↔
      (action.removes = true ∧ target = .integer key)) :
    Elixir.HoldLedger.Spec.«composite_valid?/1» (.tuple #[next,encode (change items target action)]) = Except.ok Lynx.Term.true := by
  obtain ⟨well,coupled⟩ := (CompositeInvariant.full_view ledger items before ledger_valid old_located).mp valid
  apply (CompositeInvariant.full_view next (change items target action) after next_valid new_located).mpr
  refine ⟨well_change items target action well allowed,?_⟩
  intro key
  rw [frame key,change_keys items target action key well.1]
  simp [no_open key,closing key,coupled key]

theorem preserve_open (ledger next before after : Lynx.Term) (items : List Obligation) (key : Int)
    (valid : Elixir.HoldLedger.Spec.«composite_valid?/1» (.tuple #[ledger,encode items]) = Except.ok Lynx.Term.true)
    (ledger_valid : Elixir.HoldLedger.Spec.«valid?/1» ledger = Except.ok Lynx.Term.true)
    (next_valid : Elixir.HoldLedger.Spec.«valid?/1» next = Except.ok Lynx.Term.true)
    (old_located : Erlang.erlang.«element/2» (.integer 5) ledger = Except.ok before)
    (new_located : Erlang.erlang.«element/2» (.integer 5) next = Except.ok after)
    (frame : Voiding.Frame before after (.tuple #[.atom "void",.integer key]) (.atom "voiding"))
    (fresh : key ∉ items.map Obligation.key) :
    Elixir.HoldLedger.Spec.«composite_valid?/1» (.tuple #[next,encode (items ++ [⟨key,0,.atom "unattempted"⟩])]) = Except.ok Lynx.Term.true := by
  obtain ⟨well,coupled⟩ := (CompositeInvariant.full_view ledger items before ledger_valid old_located).mp valid
  apply (CompositeInvariant.full_view next _ after next_valid new_located).mpr
  refine ⟨well_open items key well fresh,?_⟩
  intro query
  rw [frame query]
  simp [coupled query,List.map_append,List.mem_append,eq_comm]

theorem composite_oracle (state event : Lynx.Term)
    (valid : Elixir.HoldLedger.Spec.«composite_valid?/1» state = Except.ok Lynx.Term.true) :
    Elixir.HoldLedger.Composite.«step/2» state event =
      Elixir.HoldLedger.Spec.«expected_composite_step/2» state event := by
  obtain ⟨ledger,items,entries,rfl,ledger_valid,located,obligations,_⟩ := (composite_view state).mp valid
  obtain ⟨next,result,effects,applied,oracle,_⟩ := step_agrees ledger event ledger_valid
  obtain ⟨old_entries,old_located,form⟩ := Voiding.effect_form ledger event next result effects ledger_valid applied
  have equal : old_entries = entries := Except.ok.inj (old_located.symm.trans located)
  subst old_entries
  rcases form with ⟨rfl,not_voiding⟩ | ⟨key,amount,rfl,not_voiding⟩ | ⟨key,amount,rfl,rfl,rfl,authorized⟩
  · exact metadata_agrees ledger next event result .nil items applied oracle rfl not_voiding
  · apply metadata_agrees ledger next event result _ items applied oracle _ not_voiding
    simp [Elixir.HoldLedger.Composite.«open_effects/2»]
  · have fresh := CompositeInvariant.nonvoid_absent items entries .nil key amount (.atom "authorized")
      obligations authorized (by simp)
    have opened := open_append items key fresh
    have unchanged := fold_other (items ++ [⟨key,0,.atom "unattempted"⟩]) (.tuple #[.atom "void",.integer key])
      (by intros; simp) (by intros; simp) (by intros; simp)
    have appended : Erlang.erlang.«++/2» (encode items)
        (.list [.tuple #[.integer key,.integer 0,.atom "unattempted"]]) =
        Except.ok (encode (items ++ [⟨key,0,.atom "unattempted"⟩])) :=
      encode_append items [⟨key,0,.atom "unattempted"⟩]
    simp [Elixir.HoldLedger.Composite.«step/2»,Elixir.HoldLedger.Composite.«open_effects/2»,
      Elixir.HoldLedger.Spec.«expected_composite_step/2»,applied,oracle,opened,unchanged,appended]

theorem composite_preserves (state event : Lynx.Term)
    (valid : Elixir.HoldLedger.Spec.«composite_valid?/1» state = Except.ok Lynx.Term.true) :
    ∃ next result effects,
      Elixir.HoldLedger.Composite.«step/2» state event = Except.ok (.tuple #[next,result,effects]) ∧
      Elixir.HoldLedger.Spec.«composite_valid?/1» next = Except.ok Lynx.Term.true := by
  have agrees := composite_oracle state event valid
  obtain ⟨ledger,items,before,rfl,ledger_valid,old_located,obligations,_⟩ := (composite_view state).mp valid
  obtain ⟨next,result,effects,applied,oracle,next_valid⟩ := step_agrees ledger event ledger_valid
  obtain ⟨actual_before,after,previous,new_located,frame⟩ := Voiding.ledger_frame ledger event next result effects ledger_valid applied
  have equal : actual_before = before := Except.ok.inj (previous.symm.trans old_located)
  subst actual_before
  have change_safe (target : Lynx.Term) (action : Change) (allowed : action.allowed)
      (no_open : ∀ key : Int, ¬(event = .tuple #[.atom "void",.integer key] ∧ result = .atom "voiding"))
      (closing : ∀ key : Int, (event = .tuple #[.atom "void_confirmed",.integer key] ∧ result = .atom "voided") ↔
        (action.removes = true ∧ target = .integer key)) :=
    preserve_change ledger next before after event result target items action valid ledger_valid next_valid old_located new_located frame allowed no_open closing
  have unchanged_safe
      (no_open : ∀ key : Int, ¬(event = .tuple #[.atom "void",.integer key] ∧ result = .atom "voiding"))
      (no_close : ∀ key : Int, ¬(event = .tuple #[.atom "void_confirmed",.integer key] ∧ result = .atom "voided")) :=
    preserve_unchanged ledger next before after event result items valid ledger_valid next_valid old_located new_located frame no_open no_close
  rw [agrees]
  by_cases opening : ∃ key, event = .tuple #[.atom "void",key] ∧ result = .atom "voiding"
  · obtain ⟨key,rfl,rfl⟩ := opening
    obtain ⟨actual,located,form⟩ := Voiding.effect_form ledger (.tuple #[.atom "void",key]) next (.atom "voiding") effects ledger_valid applied
    have equal : actual = before := Except.ok.inj (located.symm.trans old_located)
    subst actual
    rcases form with ⟨_,bad⟩ | ⟨_,_,_,bad⟩ | ⟨intkey,amount,identity,_,_,found⟩
    · exact False.elim (bad rfl)
    · exact False.elim (bad rfl)
    · simp only [Lynx.Term.tuple.injEq,Array.mk.injEq,List.cons.injEq,and_true,true_and] at identity
      subst key
      have fresh := CompositeInvariant.nonvoid_absent items before .nil intkey amount (.atom "authorized") obligations found (by simp)
      have append := encode_append items [⟨intkey,0,.atom "unattempted"⟩]
      change Erlang.erlang.«++/2» (encode items)
        (.list [.tuple #[.integer intkey,.integer 0,.atom "unattempted"]]) = _ at append
      simp only [Elixir.HoldLedger.Spec.«expected_composite_step/2»,oracle,append,bind,Except.bind]
      exact ⟨_,_,_,rfl,preserve_open ledger next before after items intkey valid ledger_valid next_valid old_located new_located frame fresh⟩
  · by_cases confirmation : ∃ key, event = .tuple #[.atom "void_confirmed",key] ∧ result = .atom "voided"
    · obtain ⟨key,rfl,rfl⟩ := confirmation
      have changed := change_bridge items key Change.remove
      simp only [Change.term] at changed
      simp only [Elixir.HoldLedger.Spec.«expected_composite_step/2»,oracle,changed,bind,Except.bind]
      refine ⟨_,_,_,rfl,change_safe key .remove trivial ?_ ?_⟩
      · intros; simp
      · intros; simp [Change.removes]
    · by_cases attempt : ∃ key, event = .tuple #[.atom "void_attempt",key]
      · obtain ⟨key,rfl⟩ := attempt
        have changed := change_bridge items key Change.attempt
        simp only [Change.term] at changed
        simp only [Elixir.HoldLedger.Spec.«expected_composite_step/2»,oracle,changed,bind,Except.bind]
        refine ⟨_,_,_,rfl,change_safe key .attempt trivial ?_ ?_⟩
        · intros; simp
        · intros; simp [Change.removes]
      · by_cases outcome : ∃ key reason, event = .tuple #[.atom "void_outcome",key,.tuple #[.atom "error",reason]]
        · obtain ⟨key,reason,rfl⟩ := outcome
          rcases outcome_boolean reason with allowed | rejected
          · have changed := change_bridge items key (.outcome (.tuple #[.atom "error",reason]))
            simp only [Change.term] at changed
            simp [Elixir.HoldLedger.Spec.«expected_composite_step/2»,oracle,allowed,changed]
            exact change_safe key (.outcome (.tuple #[.atom "error",reason])) allowed (by intros; simp) (by intros; simp [Change.removes])
          · simp [Elixir.HoldLedger.Spec.«expected_composite_step/2»,oracle,rejected]
            exact unchanged_safe (by intros; simp) (by intros; simp)
        · by_cases retry : ∃ key, event = .tuple #[.atom "void_retry_enabled",key]
          · obtain ⟨key,rfl⟩ := retry
            have changed := change_bridge items key Change.reset
            simp only [Change.term] at changed
            simp only [Elixir.HoldLedger.Spec.«expected_composite_step/2»,oracle,changed,bind,Except.bind]
            refine ⟨_,_,_,rfl,change_safe key .reset trivial ?_ ?_⟩ <;> intros <;> simp [Change.removes]
          · have safe := unchanged_safe
              (by intro key h; exact opening ⟨.integer key,h⟩)
              (by intro key h; exact confirmation ⟨.integer key,h⟩)
            simp only [Elixir.HoldLedger.Spec.«expected_composite_step/2»,oracle,bind,Except.bind]
            repeat' (split <;> try simp_all [])
            all_goals exact ⟨_,_,_,rfl,safe⟩

/-- Successful live commit traces preserve full composite validity at every edge. -/
theorem recovery_valid {state final : Lynx.Term} {events : List Lynx.Term}
    (valid : Elixir.HoldLedger.Spec.«composite_valid?/1» state = Except.ok Lynx.Term.true)
    (committed : Recovery.Committed state events final) :
    Elixir.HoldLedger.Spec.«composite_valid?/1» final = Except.ok Lynx.Term.true := by
  induction committed with
  | empty state => exact valid
  | @next state event next result effects events final applied tail ih =>
      obtain ⟨actual,res,fx,step,preserved⟩ := composite_preserves state event valid
      have equal := Except.ok.inj (step.symm.trans applied)
      simp only [Lynx.Term.tuple.injEq,Array.mk.injEq,List.cons.injEq,and_true] at equal
      obtain ⟨rfl,rfl,rfl⟩ := equal
      exact ih preserved

/-- Every proper finite event history succeeds and retains complete coupling. -/
theorem composite_history (state : Lynx.Term) (events : List Lynx.Term)
    (valid : Elixir.HoldLedger.Spec.«composite_valid?/1» state = Except.ok Lynx.Term.true) :
    ∃ final, Elixir.HoldLedger.Composite.«run/2» state (.list events) = Except.ok final ∧
      Elixir.HoldLedger.Spec.«composite_valid?/1» final = Except.ok Lynx.Term.true ∧
      Recovery.Committed state events final := by
  induction events generalizing state with
  | nil => exact ⟨state,rfl,valid,Recovery.Committed.empty state⟩
  | cons event rest ih =>
      obtain ⟨next,result,effects,applied,preserved⟩ := composite_preserves state event valid
      obtain ⟨final,run,valid_final,committed⟩ := ih next preserved
      refine ⟨final,?_,valid_final,Recovery.Committed.next applied committed⟩
      simpa [Lynx.Term.list,Elixir.HoldLedger.Composite.«run/2»,applied,bind,Except.bind] using run

/-- An authorized void opens exactly one fresh obligation and retains coupling. -/
theorem open_obligation (ledger : Lynx.Term) (items : List Obligation) (key amount : Int)
    (valid : Elixir.HoldLedger.Spec.«composite_valid?/1» (.tuple #[ledger,encode items]) = Except.ok Lynx.Term.true)
    (authorized : (do let entries ← Erlang.erlang.«element/2» (.integer 5) ledger
                      Elixir.HoldLedger.Spec.«lookup/2» entries (.integer key)) =
       Except.ok (.tuple #[.atom "ok",.tuple #[.integer key,.integer amount,.atom "authorized"]])) :
    ∃ next,
      Elixir.HoldLedger.Composite.«step/2» (.tuple #[ledger,encode items]) (.tuple #[.atom "void",.integer key]) =
        Except.ok (.tuple #[.tuple #[next,encode (items ++ [⟨key,0,.atom "unattempted"⟩])],.atom "voiding",
          .cons (.tuple #[.atom "void",.integer key]) .nil]) ∧
      Elixir.HoldLedger.Spec.«composite_valid?/1» (.tuple #[next,encode (items ++ [⟨key,0,.atom "unattempted"⟩])]) = Except.ok Lynx.Term.true := by
  obtain ⟨_,_,entries,shape,ledger_valid,located,obligations,_⟩ := CompositeInvariant.components (.tuple #[ledger,encode items]) valid
  simp only [Lynx.Term.tuple.injEq,Array.mk.injEq,List.cons.injEq,and_true] at shape
  obtain ⟨rfl,rfl⟩ := shape
  obtain ⟨al,hl,ua,uh,es,rfl,proper,_,_,_,_,_,_,_,_,_⟩ := valid_view_1 ledger ledger_valid
  simp [Erlang.erlang.«element/2»] at authorized located
  subst entries
  obtain ⟨out,changed,_⟩ := Voiding.selected_status es (.integer key) (.integer amount) (.atom "authorized") (.atom "voiding") proper authorized
  obtain ⟨_,found,spec_found⟩ := compatible_1 es (.integer key) proper
  have find : Elixir.HoldLedger.Ledger.«find/2» es (.integer key) =
      Except.ok (.tuple #[.atom "ok",.tuple #[.integer key,.integer amount,.atom "authorized"]]) := found.trans (spec_found.symm.trans authorized)
  have fresh := CompositeInvariant.nonvoid_absent items es .nil key amount (.atom "authorized") obligations authorized (by simp)
  have opened := open_append items key fresh
  have unchanged := fold_other (items ++ [⟨key,0,.atom "unattempted"⟩]) (.tuple #[.atom "void",.integer key])
    (by intros; simp) (by intros; simp) (by intros; simp)
  have actual : Elixir.HoldLedger.Composite.«step/2»
      (.tuple #[.tuple #[.integer al,.integer hl,.integer ua,.integer uh,es],encode items]) (.tuple #[.atom "void",.integer key]) =
      Except.ok (.tuple #[.tuple #[.tuple #[.integer al,.integer hl,.integer ua,.integer uh,out],
        encode (items ++ [⟨key,0,.atom "unattempted"⟩])],.atom "voiding",.cons (.tuple #[.atom "void",.integer key]) .nil]) := by
    simp [Elixir.HoldLedger.Composite.«step/2»,Elixir.HoldLedger.Composite.«open_effects/2»,
      Elixir.HoldLedger.Ledger.«step/2»,Elixir.HoldLedger.Ledger.«void/2»,find,changed,opened,unchanged]
  obtain ⟨next,result,effects,step,preserved⟩ := composite_preserves _ (.tuple #[.atom "void",.integer key]) valid
  have equal := Except.ok.inj (step.symm.trans actual)
  simp only [Lynx.Term.tuple.injEq,Array.mk.injEq,List.cons.injEq,and_true] at equal
  obtain ⟨rfl,rfl,rfl⟩ := equal
  exact ⟨_,actual,preserved⟩

/-- One confirmation releases a pending hold and retires its obligation in one
    transition; repeating it is stale and leaves the composite unchanged. -/
theorem confirmation_once (ledger : Lynx.Term) (items : List Obligation) (key amount : Int)
    (valid : Elixir.HoldLedger.Spec.«composite_valid?/1» (.tuple #[ledger,encode items]) = Except.ok Lynx.Term.true)
    (voiding : (do let entries ← Erlang.erlang.«element/2» (.integer 5) ledger
                   Elixir.HoldLedger.Spec.«lookup/2» entries (.integer key)) =
       Except.ok (.tuple #[.atom "ok",.tuple #[.integer key,.integer amount,.atom "voiding"]])) :
    ∃ next,
      Elixir.HoldLedger.Composite.«step/2» (.tuple #[ledger,encode items]) (.tuple #[.atom "void_confirmed",.integer key]) =
        Except.ok (.tuple #[next,.atom "voided",.nil]) ∧
      Elixir.HoldLedger.Spec.«composite_valid?/1» next = Except.ok Lynx.Term.true ∧
      Elixir.HoldLedger.Composite.«step/2» next (.tuple #[.atom "void_confirmed",.integer key]) =
        Except.ok (.tuple #[next,.atom "stale",.nil]) ∧
      key ∉ (change items (.integer key) .remove).map Obligation.key := by
  obtain ⟨_,_,entries,shape,ledger_valid,located,obligations,_⟩ := CompositeInvariant.components (.tuple #[ledger,encode items]) valid
  simp only [Lynx.Term.tuple.injEq,Array.mk.injEq,List.cons.injEq,and_true] at shape
  obtain ⟨rfl,rfl⟩ := shape
  obtain ⟨al,hl,ua,uh,es,rfl,proper,_,_,_,_,_,_,_,_,_⟩ := valid_view_1 ledger ledger_valid
  simp [Erlang.erlang.«element/2»] at voiding located
  subst entries
  obtain ⟨out,changed,lookup⟩ := Voiding.selected_status es (.integer key) (.integer amount) (.atom "voiding") (.atom "voided") proper voiding
  obtain ⟨_,found,spec_found⟩ := compatible_1 es (.integer key) proper
  have find : Elixir.HoldLedger.Ledger.«find/2» es (.integer key) =
      Except.ok (.tuple #[.atom "ok",.tuple #[.integer key,.integer amount,.atom "voiding"]]) := found.trans (spec_found.symm.trans voiding)
  have removed := remove_oracle items (.integer key)
  have bridge := change_bridge items (.integer key) Change.remove
  simp only [Change.term] at bridge
  have actual : Elixir.HoldLedger.Composite.«step/2»
      (.tuple #[.tuple #[.integer al,.integer hl,.integer ua,.integer uh,es],encode items]) (.tuple #[.atom "void_confirmed",.integer key]) =
      Except.ok (.tuple #[.tuple #[.tuple #[.integer al,.integer hl,.integer (ua-amount),.integer (uh-1),out],
        encode (change items (.integer key) .remove)],.atom "voided",.nil]) := by
    simp [Elixir.HoldLedger.Composite.«step/2»,Elixir.HoldLedger.Composite.«open_effects/2»,
      Elixir.HoldLedger.Ledger.«step/2»,Elixir.HoldLedger.Ledger.«void_confirmed/2»,find,changed,removed,bridge]
  obtain ⟨next,result,effects,step,preserved⟩ := composite_preserves _ (.tuple #[.atom "void_confirmed",.integer key]) valid
  have equal := Except.ok.inj (step.symm.trans actual)
  simp only [Lynx.Term.tuple.injEq,Array.mk.injEq,List.cons.injEq,and_true] at equal
  obtain ⟨rfl,rfl,rfl⟩ := equal
  have next_ledger_valid : Elixir.HoldLedger.Spec.«valid?/1»
      (.tuple #[.integer al,.integer hl,.integer (ua-amount),.integer (uh-1),out]) = Except.ok Lynx.Term.true := by
    obtain ⟨_,_,_,shape,good,_,_,_⟩ := CompositeInvariant.components _ preserved
    simp only [Lynx.Term.tuple.injEq,Array.mk.injEq,List.cons.injEq,and_true] at shape
    obtain ⟨rfl,rfl⟩ := shape
    exact good
  obtain ⟨_,_,_,_,_,shape,proper_out,_,_,_,_,_,_,_,_,_⟩ := valid_view_1 _ next_ledger_valid
  simp only [Lynx.Term.tuple.injEq,Array.mk.injEq,List.cons.injEq,Lynx.Term.integer.injEq,and_true] at shape
  obtain ⟨rfl,rfl,rfl,rfl,rfl⟩ := shape
  obtain ⟨_,find_out,spec_out⟩ := compatible_1 out (.integer key) proper_out
  have terminal := find_out.trans (spec_out.symm.trans lookup)
  have unchanged := fold_other (change items (.integer key) .remove) (.tuple #[.atom "void_confirmed",.integer key])
    (by intros; simp) (by intros; simp) (by intros; simp)
  have ⟨well,_⟩ := (CompositeInvariant.full_view _ items es ledger_valid rfl).mp valid
  refine ⟨_,actual,preserved,?_,?_⟩
  · simp [Elixir.HoldLedger.Composite.«step/2»,Elixir.HoldLedger.Composite.«open_effects/2»,
      Elixir.HoldLedger.Ledger.«step/2»,Elixir.HoldLedger.Ledger.«void_confirmed/2»,terminal,unchanged]
  · simp [change_keys items (.integer key) .remove key well.1,Change.removes]

/-- Agreement with the independent composite oracle over every finite history. -/
theorem composite_oracle_history (state : Lynx.Term) (events : List Lynx.Term)
    (valid : Elixir.HoldLedger.Spec.«composite_valid?/1» state = Except.ok Lynx.Term.true) :
    ∃ final, Elixir.HoldLedger.Composite.«run/2» state (.list events) = Except.ok final ∧
      Elixir.HoldLedger.Spec.«expected_composite_run/2» state (.list events) = Except.ok final ∧
      Elixir.HoldLedger.Spec.«composite_valid?/1» final = Except.ok Lynx.Term.true := by
  induction events generalizing state with
  | nil => exact ⟨state,rfl,rfl,valid⟩
  | cons event rest ih =>
      obtain ⟨next,result,effects,applied,preserved⟩ := composite_preserves state event valid
      have expected := (composite_oracle state event valid).symm.trans applied
      obtain ⟨final,actual,oracle,final_valid⟩ := ih next preserved
      refine ⟨final,?_,?_,final_valid⟩
      · simpa [Lynx.Term.list,Elixir.HoldLedger.Composite.«run/2»,applied,bind,Except.bind] using actual
      · simpa [Lynx.Term.list,Elixir.HoldLedger.Spec.«expected_composite_run/2»,expected,bind,Except.bind] using oracle

end HoldLedgerProof.CompositeSafety
