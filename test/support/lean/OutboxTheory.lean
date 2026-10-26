module
public import Elixir.HoldLedger.Outbox
public import Elixir.HoldLedger.Spec
public import Lynx
import Lean

public section
namespace HoldLedgerProof.Outbox

structure Obligation where
  key : Int
  count : Int
  outcome : Lynx.Term

@[expose] def encode : List Obligation → Lynx.Term
  | [] => .nil
  | item :: rest => .cons (.tuple #[.integer item.key,.integer item.count,item.outcome]) (encode rest)

theorem present (items : List Obligation) (key : Int) :
    Elixir.HoldLedger.Spec.«obligation_present?/2» (encode items) (.integer key) =
      Except.ok (if key ∈ items.map Obligation.key then Lynx.Term.true else Lynx.Term.false) := by
  induction items with
  | nil => rfl
  | cons item rest ih =>
      by_cases same : key = item.key
      · subst key
        simp [encode,Elixir.HoldLedger.Spec.«obligation_present?/2»,Erlang.erlang.«=:=/2»]
      · simp [encode,Elixir.HoldLedger.Spec.«obligation_present?/2»,same,ih,
          Erlang.erlang.«=:=/2»]

@[expose] def Well (items : List Obligation) : Prop :=
  (items.map Obligation.key).Nodup ∧ ∀ item ∈ items,
    0 ≤ item.count ∧ Elixir.HoldLedger.Spec.«outcome_valid?/1» item.outcome = Except.ok Lynx.Term.true

inductive Change where
  | attempt | reset | outcome (value : Lynx.Term) | remove

@[expose] def Change.term : Change → Lynx.Term
  | .attempt => .atom "attempt"
  | .reset => .atom "reset"
  | .outcome value => .tuple #[.atom "outcome",value]
  | .remove => .atom "remove"

@[expose] def Change.allowed : Change → Prop
  | .outcome value => Elixir.HoldLedger.Spec.«outcome_valid?/1» value = Except.ok Lynx.Term.true
  | _ => True

@[expose] def Change.removes : Change → Bool
  | .remove => true
  | _ => false

@[expose] noncomputable def change : List Obligation → Lynx.Term → Change → List Obligation
  | [], _, _ => []
  | item :: rest, key, action => by
      classical
      exact if key = .integer item.key then
        match action with
        | .attempt => ⟨item.key,item.count + 1,.atom "unattempted"⟩ :: rest
        | .reset => ⟨item.key,0,item.outcome⟩ :: rest
        | .outcome value => ⟨item.key,item.count,value⟩ :: rest
        | .remove => rest
      else item :: change rest key action

theorem change_bridge (items : List Obligation) (key : Lynx.Term) (action : Change) :
    Elixir.HoldLedger.Spec.«expected_obligation_update/3» (encode items) key action.term =
      Except.ok (encode (change items key action)) := by
  induction items with
  | nil => cases action <;> rfl
  | cons item rest ih =>
      by_cases same : key = .integer item.key
      all_goals cases action
      all_goals simp only [Change.term] at ih
      all_goals simp [encode,change,Change.term,Elixir.HoldLedger.Spec.«expected_obligation_update/3»,
          Erlang.erlang.«=:=/2»,same,ih]

theorem change_subset (items : List Obligation) (target : Lynx.Term) (action : Change) (query : Int)
    (member : query ∈ (change items target action).map Obligation.key) : query ∈ items.map Obligation.key := by
  induction items with
  | nil => simp [change] at member
  | cons item rest ih =>
      by_cases same : target = .integer item.key
      · cases action <;> simp [change,same] at member <;> simp_all
      · simp only [change,ite_eq_right same,List.map_cons,List.mem_cons] at member
        rcases member with first | tail
        · simp [first]
        · exact List.mem_cons_of_mem _ (ih tail)

theorem well_cons (item : Obligation) (rest : List Obligation) :
    Well (item :: rest) ↔ item.key ∉ rest.map Obligation.key ∧ 0 ≤ item.count ∧
      Elixir.HoldLedger.Spec.«outcome_valid?/1» item.outcome = Except.ok Lynx.Term.true ∧ Well rest := by
  simp only [Well,List.map_cons,List.nodup_cons,List.mem_cons,forall_eq_or_imp]
  grind

theorem well_change (items : List Obligation) (target : Lynx.Term) (action : Change)
    (valid : Well items) (allowed : action.allowed) : Well (change items target action) := by
  induction items with
  | nil => simp [Well,change]
  | cons item rest ih =>
      obtain ⟨absent,count,outcome,tail⟩ := (well_cons item rest).mp valid
      by_cases same : target = .integer item.key
      · cases action
        case attempt =>
          simp only [change,ite_eq_left same]
          exact (well_cons _ rest).mpr ⟨absent,by dsimp; omega,rfl,tail⟩
        case reset =>
          simp only [change,ite_eq_left same]
          exact (well_cons _ rest).mpr ⟨absent,by simp,outcome,tail⟩
        case outcome value =>
          simp only [change,ite_eq_left same]
          exact (well_cons _ rest).mpr ⟨absent,count,allowed,tail⟩
        case remove => simpa [change,same] using tail
      · simp only [change,ite_eq_right same]
        apply (well_cons item _).mpr
        exact ⟨by intro member; exact absent (change_subset rest target action item.key member),count,outcome,ih tail⟩

theorem change_keys (items : List Obligation) (target : Lynx.Term) (action : Change) (query : Int)
    (distinct : (items.map Obligation.key).Nodup) :
    query ∈ (change items target action).map Obligation.key ↔
      query ∈ items.map Obligation.key ∧ ¬(action.removes = true ∧ target = .integer query) := by
  induction items with
  | nil => simp [change]
  | cons item rest ih =>
      obtain ⟨absent,tail⟩ := List.nodup_cons.mp distinct
      by_cases same : target = .integer item.key
      · cases action
        all_goals simp only [change,ite_eq_left same,List.map_cons,List.mem_cons,Change.removes]
        all_goals try simp
        all_goals constructor
        all_goals intro member
        all_goals try grind
        all_goals try obtain ⟨in_list,not_equal⟩ := member
        all_goals try rcases in_list with first | remaining
        all_goals try grind
      · rw [show change (item :: rest) target action = item :: change rest target action from by simp [change,same]]
        simp only [List.map_cons,List.mem_cons,ih tail]
        constructor
        · rintro (first | ⟨remaining,safe⟩)
          · exact ⟨Or.inl first,by intro h; apply same; simpa [first] using h.2⟩
          · exact ⟨Or.inr remaining,safe⟩
        · rintro ⟨first | remaining,safe⟩
          · exact Or.inl first
          · exact Or.inr ⟨remaining,safe⟩

theorem well_open (items : List Obligation) (key : Int)
    (valid : Well items) (fresh : key ∉ items.map Obligation.key) :
    Well (items ++ [⟨key,0,.atom "unattempted"⟩]) := by
  induction items with
  | nil => simp [Well,Elixir.HoldLedger.Spec.«outcome_valid?/1»]
  | cons item rest ih =>
      obtain ⟨absent,count,outcome,tail⟩ := (well_cons item rest).mp valid
      have different : item.key ≠ key := by intro equal; apply fresh; simp [equal]
      have tail_fresh : key ∉ rest.map Obligation.key := by intro member; apply fresh; simp [member]
      apply (well_cons item _).mpr
      exact ⟨by simpa [List.map_append,List.mem_append] using And.intro absent different,
        count,outcome,ih tail tail_fresh⟩

theorem fetch_shape (items : List Obligation) (key : Int) :
    Elixir.HoldLedger.Outbox.«fetch/2» (encode items) (.integer key) = Except.ok (.atom "not_found") ∨
    ∃ (count : Int) (outcome : Lynx.Term),
      Elixir.HoldLedger.Outbox.«fetch/2» (encode items) (.integer key) =
        Except.ok (.tuple #[.integer key,.integer count,outcome]) ∧ key ∈ items.map Obligation.key := by
  induction items with
  | nil => exact Or.inl rfl
  | cons item rest ih =>
      by_cases same : key = item.key
      · subst key
        exact Or.inr ⟨item.count,item.outcome,by simp [encode,Elixir.HoldLedger.Outbox.«fetch/2»,Erlang.erlang.«=:=/2»],by simp⟩
      · rcases ih with absent | ⟨count,outcome,found,member⟩
        · exact Or.inl (by simp [encode,Elixir.HoldLedger.Outbox.«fetch/2»,same,Erlang.erlang.«=:=/2»,absent])
        · exact Or.inr ⟨count,outcome,by simp [encode,Elixir.HoldLedger.Outbox.«fetch/2»,same,Erlang.erlang.«=:=/2»,found],by simp [member]⟩

/-- Membership always produces a Boolean atom, independently of the candidate terms. -/
theorem member_boolean (value : Lynx.Term) (candidates : List Lynx.Term) :
    Lynx.Term.isMember value candidates = Lynx.Term.atom "true" ∨
    Lynx.Term.isMember value candidates = Lynx.Term.atom "false" := by
  induction candidates with
  | nil => exact Or.inr rfl
  | cons candidate rest ih =>
      simp only [Lynx.Term.isMember_cons]
      split
      · exact Or.inl rfl
      · exact ih

theorem outcome_boolean (reason : Lynx.Term) :
    Elixir.HoldLedger.Spec.«outcome_valid?/1» (.tuple #[.atom "error",reason]) = Except.ok Lynx.Term.true ∨
    Elixir.HoldLedger.Spec.«outcome_valid?/1» (.tuple #[.atom "error",reason]) = Except.ok Lynx.Term.false := by
  simp only [Elixir.HoldLedger.Spec.«outcome_valid?/1»,Except.ok.injEq]
  exact member_boolean reason _

theorem valid_outcome_boolean (outcome : Lynx.Term) :
    Elixir.HoldLedger.Spec.«outcome_valid?/1» outcome = Except.ok Lynx.Term.true ∨
    Elixir.HoldLedger.Spec.«outcome_valid?/1» outcome = Except.ok Lynx.Term.false := by
  unfold Elixir.HoldLedger.Spec.«outcome_valid?/1»
  split
  · exact Or.inl rfl
  · exact (outcome_boolean _)
  · exact Or.inr rfl

theorem fold_attempt (items : List Obligation) (key : Lynx.Term) :
    Elixir.HoldLedger.Outbox.«fold/2» (encode items) (.tuple #[.atom "void_attempt",key]) =
      Elixir.HoldLedger.Spec.«expected_obligation_update/3» (encode items) key (.atom "attempt") := by
  induction items with
  | nil => rfl
  | cons item rest ih =>
      by_cases same : key = .integer item.key <;>
        simp [encode,Elixir.HoldLedger.Outbox.«fold/2»,
          Elixir.HoldLedger.Spec.«expected_obligation_update/3»,ih,same,
          Erlang.erlang.«=:=/2»,bind,Except.bind]

theorem fold_retry (items : List Obligation) (key : Lynx.Term) :
    Elixir.HoldLedger.Outbox.«fold/2» (encode items) (.tuple #[.atom "void_retry_enabled",key]) =
      Elixir.HoldLedger.Spec.«expected_obligation_update/3» (encode items) key (.atom "reset") := by
  induction items with
  | nil => rfl
  | cons item rest ih =>
      by_cases same : key = .integer item.key <;>
        simp [encode,Elixir.HoldLedger.Outbox.«fold/2»,
          Elixir.HoldLedger.Spec.«expected_obligation_update/3»,ih,same,
          Erlang.erlang.«=:=/2»,bind,Except.bind]

theorem remove_oracle (items : List Obligation) (key : Lynx.Term) :
    Elixir.HoldLedger.Outbox.«remove/2» (encode items) key =
      Elixir.HoldLedger.Spec.«expected_obligation_update/3» (encode items) key (.atom "remove") := by
  induction items with
  | nil => rfl
  | cons item rest ih =>
      by_cases same : key = .integer item.key <;>
        simp [encode,Elixir.HoldLedger.Outbox.«remove/2»,
          Elixir.HoldLedger.Spec.«expected_obligation_update/3»,ih,same,
          Erlang.erlang.«=:=/2»,bind,Except.bind]

theorem fold_outcome_allowed (items : List Obligation) (key reason : Lynx.Term)
    (allowed : Elixir.HoldLedger.Spec.«outcome_valid?/1» (.tuple #[.atom "error",reason]) =
      Except.ok Lynx.Term.true) :
    Elixir.HoldLedger.Outbox.«fold/2» (encode items) (.tuple #[.atom "void_outcome",key,.tuple #[.atom "error",reason]]) =
      Elixir.HoldLedger.Spec.«expected_obligation_update/3» (encode items) key
        (.tuple #[.atom "outcome",.tuple #[.atom "error",reason]]) := by
  have member := allowed
  simp only [Elixir.HoldLedger.Spec.«outcome_valid?/1»,Except.ok.injEq] at member
  induction items with
  | nil => rfl
  | cons item rest ih =>
      by_cases same : key = .integer item.key <;>
        simp [encode,Elixir.HoldLedger.Outbox.«fold/2»,
          Elixir.HoldLedger.Spec.«expected_obligation_update/3»,
          Erlang.erlang.«=:=/2»,Lynx.Term.exactCompare_eq_integer,member,
          same,
          Erlang.erlang.«and/2»,
          bind,Except.bind,Lynx.Term.true,Lynx.Term.false,ih]

theorem fold_outcome_rejected (items : List Obligation) (key reason : Lynx.Term)
    (rejected : Elixir.HoldLedger.Spec.«outcome_valid?/1» (.tuple #[.atom "error",reason]) =
      Except.ok Lynx.Term.false) :
    Elixir.HoldLedger.Outbox.«fold/2» (encode items) (.tuple #[.atom "void_outcome",key,.tuple #[.atom "error",reason]]) =
      Except.ok (encode items) := by
  have member := rejected
  simp only [Elixir.HoldLedger.Spec.«outcome_valid?/1»,Except.ok.injEq] at member
  induction items with
  | nil => rfl
  | cons item rest ih =>
      by_cases same : key = .integer item.key
      · subst key
        simp [encode,Elixir.HoldLedger.Outbox.«fold/2»,ih,member,
          Erlang.erlang.«=:=/2»,Erlang.erlang.«and/2»]
      · simp [encode,Elixir.HoldLedger.Outbox.«fold/2»,ih,same,member,
          Erlang.erlang.«=:=/2»,Erlang.erlang.«and/2»]

theorem fold_other (items : List Obligation) (event : Lynx.Term)
    (no_attempt : ∀ key, event ≠ .tuple #[.atom "void_attempt",key])
    (no_retry : ∀ key, event ≠ .tuple #[.atom "void_retry_enabled",key])
    (no_outcome : ∀ key reason, event ≠ .tuple #[.atom "void_outcome",key,.tuple #[.atom "error",reason]]) :
    Elixir.HoldLedger.Outbox.«fold/2» (encode items) event = Except.ok (encode items) := by
  induction items with
  | nil => rfl
  | cons item rest ih =>
      simp only [encode]
      unfold Elixir.HoldLedger.Outbox.«fold/2»
      repeat' (split <;> try simp_all [])

theorem encode_append (first second : List Obligation) :
    Erlang.erlang.«++/2» (encode first) (encode second) = Except.ok (encode (first ++ second)) := by
  induction first with
  | nil => rfl
  | cons item rest ih => simp [encode,Erlang.erlang.«++/2»,ih]

theorem open_append (items : List Obligation) (key : Int)
    (fresh : key ∉ items.map Obligation.key) :
    Elixir.HoldLedger.Outbox.«open/2» (encode items) (.integer key) =
      Except.ok (encode (items ++ [⟨key,0,.atom "unattempted"⟩])) := by
  induction items with
  | nil => rfl
  | cons item rest ih =>
      have different : key ≠ item.key := by intro eq; apply fresh; simp [eq]
      have tail : key ∉ rest.map Obligation.key := by intro member; apply fresh; simp [member]
      simp [encode,Elixir.HoldLedger.Outbox.«open/2»,different,ih tail,
        Erlang.erlang.«=:=/2»]

end HoldLedgerProof.Outbox
