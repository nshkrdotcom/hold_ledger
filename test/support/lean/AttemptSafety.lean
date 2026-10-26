module
public import Elixir.HoldLedger.Attempts
public import Lynx
import Lean

public section
set_option maxHeartbeats 16000000
namespace HoldLedgerProof.AttemptSafety

inductive Kind where | authorize | void | lookup
  deriving DecidableEq
inductive Phase where | running | stopping | committing
  deriving DecidableEq
structure Attempt where
  id : Int
  kind : Kind
  key : Int
  phase : Phase
  deriving DecidableEq
structure State where
  next : Int
  poison : Bool
  entries : List Attempt
  deriving DecidableEq
inductive Event where
  | start (kind : Kind) (key limit : Int)
  | result (id : Int)
  | down (id : Int)
  | deadline (id : Int)
  | shutdown (id : Int)
  | committed (id : Int)
  | poison
  deriving DecidableEq
inductive Intent where | spawn (id : Int) | shutdown (id : Int) | persist (id : Int) | retire (id : Int)
  deriving DecidableEq

@[expose] def kindTerm : Kind → Lynx.Term
  | .authorize => .atom "authorize"
  | .void => .atom "void"
  | .lookup => .atom "lookup"
@[expose] def phaseTerm : Phase → Lynx.Term
  | .running => .atom "running"
  | .stopping => .atom "stopping"
  | .committing => .atom "committing"
@[expose] def entriesTerm : List Attempt → Lynx.Term
  | [] => .nil
  | a :: rest => .cons (.tuple #[.integer a.id,kindTerm a.kind,.integer a.key,phaseTerm a.phase]) (entriesTerm rest)
@[expose] def stateTerm (s : State) : Lynx.Term :=
  .tuple #[.integer s.next,if s.poison then .atom "true" else .atom "false",entriesTerm s.entries]
@[expose] def eventTerm : Event → Lynx.Term
  | .start k key limit => .tuple #[.atom "start",kindTerm k,.integer key,.integer limit]
  | .result id => .tuple #[.atom "result",.integer id]
  | .down id => .tuple #[.atom "down",.integer id]
  | .deadline id => .tuple #[.atom "deadline",.integer id]
  | .shutdown id => .tuple #[.atom "shutdown_result",.integer id]
  | .committed id => .tuple #[.atom "committed",.integer id]
  | .poison => .atom "poison"

@[expose] def lookup : List Attempt → Int → Option Attempt
  | [], _ => none
  | a :: rest, id => if a.id = id then some a else lookup rest id
@[expose] def replace : List Attempt → Int → Phase → List Attempt
  | [], _, _ => []
  | a :: rest, id, phase => if a.id = id then {a with phase := phase} :: rest else a :: replace rest id phase
@[expose] def remove : List Attempt → Int → List Attempt
  | [], _ => []
  | a :: rest, id => if a.id = id then rest else a :: remove rest id
@[expose] def occupied (entries : List Attempt) (kind : Kind) (key : Int) : Bool :=
  entries.any (fun a => a.kind == kind && a.key == key)

@[expose] def change (s : State) (id : Int) (source destination : Phase) (intent : Int → Intent) : State × List Intent :=
  match lookup s.entries id with
  | some a => if a.phase = source then ({s with entries := replace s.entries id destination},[intent id]) else (s,[])
  | none => (s,[])

@[expose] def step (s : State) : Event → State × List Intent
  | .start kind key limit =>
    if !s.poison && decide (0 < limit) && decide ((s.entries.length : Int) < limit) && !occupied s.entries kind key then
      ({s with next := s.next + 1, entries := ⟨s.next,kind,key,.running⟩ :: s.entries},[.spawn s.next])
    else (s,[])
  | .result id => change s id .running .committing .persist
  | .down id => change s id .running .committing .persist
  | .deadline id => change s id .running .stopping .shutdown
  | .shutdown id => change s id .stopping .committing .persist
  | .committed id =>
    match lookup s.entries id with
    | some a => if a.phase = .committing then ({s with entries := remove s.entries id},[.retire id]) else (s,[])
    | none => (s,[])
  | .poison => ({s with poison := true},[])

@[expose] def Valid (s : State) : Prop :=
  1 ≤ s.next ∧ (s.entries.map Attempt.id).Nodup ∧
  (s.entries.map (fun a => (a.kind,a.key))).Nodup ∧
  ∀ a ∈ s.entries, 1 ≤ a.id ∧ a.id < s.next

@[expose] def initial : State := ⟨1,false,[]⟩

theorem initial_valid : Valid initial := by simp [Valid,initial]

theorem replace_ids (entries : List Attempt) (id : Int) (phase : Phase) :
    (replace entries id phase).map Attempt.id = entries.map Attempt.id := by
  induction entries with
  | nil => rfl
  | cons a rest ih => simp only [replace]; split <;> simp_all

theorem replace_slots (entries : List Attempt) (id : Int) (phase : Phase) :
    (replace entries id phase).map (fun a => (a.kind,a.key)) = entries.map (fun a => (a.kind,a.key)) := by
  induction entries with
  | nil => rfl
  | cons a rest ih => simp only [replace]; split <;> simp_all

theorem replace_bounds {entries : List Attempt} {id next : Int} {phase : Phase}
    (bounded : ∀ a ∈ entries, 1 ≤ a.id ∧ a.id < next) :
    ∀ a ∈ replace entries id phase, 1 ≤ a.id ∧ a.id < next := by
  induction entries with
  | nil => simp [replace]
  | cons a rest ih =>
      have first := bounded a (by simp)
      have tail := ih (by intro e h; exact bounded e (by simp [h]))
      simp only [replace]
      split <;> simp_all

theorem remove_sublist (entries : List Attempt) (id : Int) : (remove entries id).Sublist entries := by
  induction entries with
  | nil => exact .refl []
  | cons a rest ih =>
      simp only [remove]
      split
      · exact List.sublist_cons_self a rest
      · exact ih.cons_cons a

theorem replace_valid {s : State} {id : Int} {phase : Phase} (valid : Valid s) :
    Valid {s with entries := replace s.entries id phase} := by
  exact ⟨valid.1,by simpa [replace_ids] using valid.2.1,
    by simpa [replace_slots] using valid.2.2.1,replace_bounds valid.2.2.2⟩

theorem remove_valid {s : State} {id : Int} (valid : Valid s) :
    Valid {s with entries := remove s.entries id} := by
  have subset := remove_sublist s.entries id
  exact ⟨valid.1,(subset.map _).nodup valid.2.1,(subset.map _).nodup valid.2.2.1,
    fun a member => valid.2.2.2 a (subset.subset member)⟩

theorem change_valid {s : State} {id : Int} {source destination : Phase} {intent : Int → Intent}
    (valid : Valid s) : Valid (change s id source destination intent).1 := by
  simp only [change]
  repeat' (split <;> try exact valid)
  exact replace_valid valid

theorem step_valid {s : State} (event : Event) (valid : Valid s) : Valid (step s event).1 := by
  cases event with
  | start kind key limit =>
      simp only [step]
      split
      · rename_i allowed
        have not_occupied : occupied s.entries kind key = false := by cases found : occupied s.entries kind key <;> simp_all
        have fresh_slot : (kind,key) ∉ s.entries.map (fun a => (a.kind,a.key)) := by
          simp [occupied] at not_occupied
          intro member
          obtain ⟨a,member,equal⟩ := List.mem_map.mp member
          have fields := Prod.mk.inj equal
          exact not_occupied a member fields.1 fields.2
        have fresh_id : s.next ∉ s.entries.map Attempt.id := by
          intro member
          obtain ⟨a,member,equal⟩ := List.mem_map.mp member
          have bound := valid.2.2.2 a member
          omega
        refine ⟨by change 1 ≤ s.next + 1; have := valid.1; omega,by simpa using List.nodup_cons.mpr ⟨fresh_id,valid.2.1⟩,
          by simpa using List.nodup_cons.mpr ⟨fresh_slot,valid.2.2.1⟩,?_⟩
        intro a member
        rcases List.mem_cons.mp member with rfl | tail
        · exact ⟨valid.1,by change s.next < s.next + 1; omega⟩
        · have := valid.2.2.2 a tail
          change 1 ≤ a.id ∧ a.id < s.next + 1
          omega
      · exact valid
  | result id | down id | deadline id | shutdown id => exact change_valid valid
  | committed id =>
      simp only [step]
      repeat' (split <;> try exact valid)
      exact remove_valid valid
  | poison => exact valid

theorem lookup_member {entries : List Attempt} {id : Int} {a : Attempt}
    (found : lookup entries id = some a) : a ∈ entries := by
  induction entries with
  | nil => simp [lookup] at found
  | cons head rest ih =>
      by_cases same : head.id = id
      · simp [lookup,same] at found
        simp [found]
      · exact List.mem_cons_of_mem _ (ih (by simpa [lookup,same] using found))

theorem lookup_absent (entries : List Attempt) (id : Int) :
    lookup entries id = none ↔ id ∉ entries.map Attempt.id := by
  induction entries with
  | nil => simp [lookup]
  | cons a rest ih =>
      by_cases same : a.id = id <;> simp_all [lookup,eq_comm]

theorem lookup_replace (entries : List Attempt) (id query : Int) (phase : Phase) :
    lookup (replace entries id phase) query =
      if id = query then (lookup entries query).map (fun a => {a with phase := phase})
      else lookup entries query := by
  induction entries with
  | nil => simp [replace,lookup]
  | cons a rest ih =>
      by_cases hit : a.id = id
      all_goals by_cases selected : a.id = query
      all_goals by_cases same : id = query
      all_goals simp_all [replace,lookup]

theorem lookup_remove {entries : List Attempt} {id query : Int}
    (unique : (entries.map Attempt.id).Nodup) :
    lookup (remove entries id) query = if id = query then none else lookup entries query := by
  induction entries with
  | nil => simp [remove,lookup]
  | cons a rest ih =>
      obtain ⟨not_in_tail,tail_unique⟩ := List.nodup_cons.mp unique
      by_cases hit : a.id = id
      all_goals by_cases selected : a.id = query
      all_goals by_cases same : id = query
      all_goals simp_all [remove,lookup,lookup_absent]

theorem lookup_id {entries : List Attempt} {id : Int} {a : Attempt}
    (found : lookup entries id = some a) : a.id = id := by
  induction entries with
  | nil => simp [lookup] at found
  | cons head rest ih =>
      by_cases same : head.id = id
      · simp [lookup,same] at found
        subst a
        exact same
      · exact ih (by simpa [lookup,same] using found)

@[expose] def Retired (s : State) (ids : List Int) : Prop :=
  ids.Nodup ∧ ∀ id ∈ ids, id < s.next ∧ lookup s.entries id = none

@[expose] def recordRetirements : List Int → List Intent → List Int
  | ids, [] => ids
  | ids, .retire id :: rest => recordRetirements (id :: ids) rest
  | ids, _ :: rest => recordRetirements ids rest

theorem change_retired {s : State} {ids : List Int} {id : Int} {source destination : Phase} {intent : Int → Intent}
    (before : Retired s ids) : Retired (change s id source destination intent).1 ids := by
  simp only [change]
  repeat' (split <;> try exact before)
  refine ⟨before.1,?_⟩
  intro query member
  obtain ⟨bound,absent⟩ := before.2 query member
  exact ⟨bound,by simp [lookup_replace,absent]⟩

theorem step_retired {s : State} {ids : List Int} (event : Event)
    (valid : Valid s) (before : Retired s ids) :
    Retired (step s event).1 (recordRetirements ids (step s event).2) := by
  cases event with
  | start kind key limit =>
      simp only [step]
      split
      · simp only [recordRetirements]
        refine ⟨before.1,?_⟩
        intro id member
        obtain ⟨bound,absent⟩ := before.2 id member
        have different : s.next ≠ id := by omega
        exact ⟨by change id < s.next + 1; omega,by simp [lookup,different,absent]⟩
      · exact before
  | result id | down id | deadline id | shutdown id =>
      all_goals simp only [step,change]
      all_goals repeat' (split <;> try exact before)
      all_goals simp only [recordRetirements]
      all_goals refine ⟨before.1,?_⟩
      all_goals intro query member
      all_goals obtain ⟨bound,absent⟩ := before.2 query member
      all_goals exact ⟨bound,by simp [lookup_replace,absent]⟩
  | committed id =>
      simp only [step]
      split
      next a found =>
        split
        next committing =>
          simp only [recordRetirements]
          have fresh : id ∉ ids := by
            intro member
            have absent := (before.2 id member).2
            simp [found] at absent
          have present := lookup_member found
          have identity := lookup_id found
          have bound := (valid.2.2.2 a present).2
          refine ⟨List.nodup_cons.mpr ⟨fresh,before.1⟩,?_⟩
          intro query member
          rcases List.mem_cons.mp member with rfl | tail
          · exact ⟨by simpa [identity] using bound,by simp [lookup_remove valid.2.1]⟩
          · obtain ⟨bound,absent⟩ := before.2 query tail
            exact ⟨bound,by simp [lookup_remove valid.2.1,absent]⟩
        next => exact before
      next => exact before
  | poison => exact before

@[expose] def run : State → List Event → State × List Intent
  | state, [] => (state,[])
  | state, event :: rest =>
      let (next,intents) := step state event
      let (final,tail) := run next rest
      (final,intents ++ tail)

theorem record_append (ids : List Int) (first second : List Intent) :
    recordRetirements ids (first ++ second) = recordRetirements (recordRetirements ids first) second := by
  induction first generalizing ids with
  | nil => rfl
  | cons intent rest ih => cases intent <;> simp [recordRetirements,ih]

theorem history_safety {s : State} {ids : List Int} (events : List Event)
    (valid : Valid s) (retired : Retired s ids) :
    Valid (run s events).1 ∧ Retired (run s events).1 (recordRetirements ids (run s events).2) := by
  induction events generalizing s ids with
  | nil => exact ⟨valid,retired⟩
  | cons event rest ih =>
      obtain ⟨kept,unique⟩ := ih (step_valid event valid) (step_retired event valid retired)
      simpa [run,record_append] using And.intro kept unique

@[expose] def recordPersists : List Int → List Intent → List Int
  | ids, [] => ids
  | ids, .persist id :: rest => recordPersists (id :: ids) rest
  | ids, _ :: rest => recordPersists ids rest

@[expose] def Persisted (s : State) (ids : List Int) : Prop :=
  ids.Nodup ∧
  (∀ id ∈ ids, id < s.next ∧ ∀ a, lookup s.entries id = some a → a.phase = .committing) ∧
  (∀ a ∈ s.entries, a.phase = .committing → a.id ∈ ids)

theorem replace_committing {entries : List Attempt} {ids : List Int} {id : Int} {phase : Phase}
    (before : ∀ a ∈ entries, a.phase = .committing → a.id ∈ ids)
    (new_entry : phase = .committing → id ∈ ids) :
    ∀ a ∈ replace entries id phase, a.phase = .committing → a.id ∈ ids := by
  induction entries with
  | nil => simp [replace]
  | cons a rest ih =>
      have tail := ih (by intro e member; exact before e (by simp [member]))
      by_cases hit : a.id = id
      · simp only [replace,ite_eq_left hit,List.mem_cons]
        intro e member committing
        rcases member with rfl | member
        · simpa [hit] using new_entry committing
        · exact before e (by simp [member]) committing
      · simp only [replace,ite_eq_right hit,List.mem_cons]
        intro e member committing
        rcases member with rfl | member
        · exact before e (by simp) committing
        · exact tail e member committing

theorem persist_fresh {s : State} {ids : List Int} {id : Int} {a : Attempt}
    (before : Persisted s ids) (found : lookup s.entries id = some a)
    (not_committing : a.phase ≠ .committing) : id ∉ ids := by
  intro member
  exact not_committing ((before.2.1 id member).2 a found)

theorem persist_replace {s : State} {ids : List Int} {id : Int} {a : Attempt}
    (valid : Valid s) (before : Persisted s ids) (found : lookup s.entries id = some a)
    (not_committing : a.phase ≠ .committing) :
    Persisted {s with entries := replace s.entries id .committing} (id :: ids) := by
  have fresh := persist_fresh before found not_committing
  have bound := (valid.2.2.2 a (lookup_member found)).2
  have identity := lookup_id found
  refine ⟨List.nodup_cons.mpr ⟨fresh,before.1⟩,?_,?_⟩
  · intro query member
    rcases List.mem_cons.mp member with rfl | member
    · refine ⟨by simpa [identity] using bound,?_⟩
      intro selected selected_eq
      simp [lookup_replace,found] at selected_eq
      simp [← selected_eq]
    · obtain ⟨old_bound,old_phase⟩ := before.2.1 query member
      have different : id ≠ query := by intro eq; exact fresh (eq ▸ member)
      exact ⟨old_bound,by simpa [lookup_replace,different] using old_phase⟩
  · apply replace_committing
    · intro e member phase
      exact List.mem_cons_of_mem _ (before.2.2 e member phase)
    · intro _; simp

theorem stopping_persisted {s : State} {ids : List Int} {id : Int} {a : Attempt}
    (before : Persisted s ids) (found : lookup s.entries id = some a)
    (not_committing : a.phase ≠ .committing) :
    Persisted {s with entries := replace s.entries id .stopping} ids := by
  have fresh := persist_fresh before found not_committing
  refine ⟨before.1,?_,replace_committing before.2.2 (by simp)⟩
  intro query member
  obtain ⟨bound,phase⟩ := before.2.1 query member
  have different : id ≠ query := by intro eq; exact fresh (eq ▸ member)
  exact ⟨bound,by simpa [lookup_replace,different] using phase⟩

theorem step_persisted {s : State} {ids : List Int} (event : Event)
    (valid : Valid s) (before : Persisted s ids) :
    Persisted (step s event).1 (recordPersists ids (step s event).2) := by
  cases event with
  | start kind key limit =>
      simp only [step]
      split
      · simp only [recordPersists]
        refine ⟨before.1,?_,?_⟩
        · intro id member
          obtain ⟨bound,phase⟩ := before.2.1 id member
          have different : s.next ≠ id := by omega
          exact ⟨by change id < s.next + 1; omega,by simpa [lookup,different] using phase⟩
        · intro a member phase
          rcases List.mem_cons.mp member with rfl | tail
          · simp at phase
          · exact before.2.2 a tail phase
      · exact before
  | result id | down id | shutdown id =>
      all_goals simp only [step,change]
      all_goals split
      all_goals try exact before
      all_goals split
      all_goals try exact before
      all_goals rename_i a found phase
      all_goals simp only [recordPersists]
      all_goals exact persist_replace valid before found (by simp [phase])
  | deadline id =>
      simp only [step,change]
      split
      next a found =>
        split
        next phase =>
          simp only [recordPersists]
          exact stopping_persisted before found (by simp [phase])
        next => exact before
      next => exact before
  | committed id =>
      simp only [step]
      split
      next a found =>
        split
        next phase =>
          simp only [recordPersists]
          have subset := remove_sublist s.entries id
          refine ⟨before.1,?_,?_⟩
          · intro query member
            obtain ⟨bound,old_phase⟩ := before.2.1 query member
            refine ⟨bound,?_⟩
            by_cases same : id = query
            · simp [lookup_remove valid.2.1,same]
            · simpa [lookup_remove valid.2.1,same] using old_phase
          · intro e member
            exact before.2.2 e (subset.subset member)
        next => exact before
      next => exact before
  | poison => exact before

theorem record_persists_append (ids : List Int) (first second : List Intent) :
    recordPersists ids (first ++ second) = recordPersists (recordPersists ids first) second := by
  induction first generalizing ids with
  | nil => rfl
  | cons intent rest ih => cases intent <;> simp [recordPersists,ih]

theorem persistence_history {s : State} {ids : List Int} (events : List Event)
    (valid : Valid s) (persisted : Persisted s ids) :
    Valid (run s events).1 ∧ Persisted (run s events).1 (recordPersists ids (run s events).2) := by
  induction events generalizing s ids with
  | nil => exact ⟨valid,persisted⟩
  | cons event rest ih =>
      obtain ⟨kept,unique⟩ := ih (step_valid event valid) (step_persisted event valid persisted)
      simpa [run,record_persists_append] using And.intro kept unique

theorem persist_once (events : List Event) : (recordPersists [] (run initial events).2).Nodup := by
  have result := persistence_history (ids := []) events initial_valid (by simp [Persisted,initial])
  exact result.2.1

theorem retire_requires_persist (events : List Event) (id : Int)
    (retirement : Intent.retire id ∈ (step (run initial events).1 (.committed id)).2) :
    id ∈ recordPersists [] (run initial events).2 := by
  obtain ⟨valid,persisted⟩ := persistence_history (ids := []) events initial_valid (by simp [Persisted,initial])
  simp only [step] at retirement
  split at retirement
  next a found =>
    split at retirement
    next phase =>
      have member := lookup_member found
      have same := lookup_id found
      simpa [same] using persisted.2.2 a member phase
    next => simp at retirement
  next => simp at retirement

@[expose] def foundTerm : Option Attempt → Lynx.Term
  | none => .atom "not_found"
  | some a => .tuple #[.atom "ok",.tuple #[.integer a.id,kindTerm a.kind,.integer a.key,phaseTerm a.phase]]

@[expose] def intentTerm (s : State) : Intent → Lynx.Term
  | .spawn id => .tuple #[.atom "spawn",.integer id]
  | .retire id => .tuple #[.atom "retire",.integer id]
  | .persist id =>
    match lookup s.entries id with
    | some a => .tuple #[.atom "persist",.integer id,kindTerm a.kind,.integer a.key]
    | none => .atom "invalid_intent"
  | .shutdown id =>
    match lookup s.entries id with
    | some a => .tuple #[.atom "shutdown",.integer id,kindTerm a.kind,.integer a.key]
    | none => .atom "invalid_intent"

@[expose] def intentsTerm (s : State) (intents : List Intent) : Lynx.Term :=
  Lynx.Term.list (intents.map (intentTerm s))

theorem count_bridge (entries : List Attempt) :
    Elixir.HoldLedger.Attempts.«count/1» (entriesTerm entries) =
      Except.ok (.integer entries.length) := by
  induction entries with
  | nil => rfl
  | cons a rest ih => simp [entriesTerm,Elixir.HoldLedger.Attempts.«count/1»,ih,Int.add_comm]

theorem occupied_bridge (entries : List Attempt) (kind : Kind) (key : Int) :
    Elixir.HoldLedger.Attempts.«occupied?/3» (entriesTerm entries) (kindTerm kind) (.integer key) =
      Except.ok (if occupied entries kind key then .atom "true" else .atom "false") := by
  induction entries with
  | nil => rfl
  | cons a rest ih =>
      have reverse : (key = a.key) ↔ (a.key = key) := eq_comm
      by_cases same : a.key = key
      all_goals cases kind <;> cases tag : a.kind
      all_goals simp_all [entriesTerm,occupied,kindTerm,Elixir.HoldLedger.Attempts.«occupied?/3»,
        Erlang.erlang.«=:=/2»,Erlang.erlang.«and/2»,
        Lynx.Term.true,Lynx.Term.false]

theorem lookup_bridge (entries : List Attempt) (id : Int) :
    Elixir.HoldLedger.Attempts.«lookup/2» (entriesTerm entries) (.integer id) = Except.ok (foundTerm (lookup entries id)) := by
  induction entries with
  | nil => rfl
  | cons a rest ih =>
      have reverse : (id = a.id) ↔ (a.id = id) := eq_comm
      by_cases same : a.id = id <;> simp [entriesTerm,lookup,foundTerm,
        Elixir.HoldLedger.Attempts.«lookup/2»,same,ih,reverse,
        Erlang.erlang.«=:=/2»]

theorem replace_bridge {entries : List Attempt} {id : Int} {selected : Attempt}
    (found : lookup entries id = some selected) (phase : Phase) :
    Elixir.HoldLedger.Attempts.«replace/3» (entriesTerm entries) (.integer id) (phaseTerm phase) =
      Except.ok (entriesTerm (replace entries id phase)) := by
  induction entries with
  | nil => simp [lookup] at found
  | cons a rest ih =>
      have reverse : (id = a.id) ↔ (a.id = id) := eq_comm
      by_cases same : a.id = id
      · simp [entriesTerm,replace,Elixir.HoldLedger.Attempts.«replace/3»,same,
          Erlang.erlang.«=:=/2»]
      · have tail : lookup rest id = some selected := by simpa [lookup,same] using found
        simp [entriesTerm,replace,Elixir.HoldLedger.Attempts.«replace/3»,same,ih tail,reverse,
          Erlang.erlang.«=:=/2»]

theorem remove_bridge (entries : List Attempt) (id : Int) :
    Elixir.HoldLedger.Attempts.«remove/2» (entriesTerm entries) (.integer id) = Except.ok (entriesTerm (remove entries id)) := by
  induction entries with
  | nil => rfl
  | cons a rest ih =>
      have reverse : (id = a.id) ↔ (a.id = id) := eq_comm
      by_cases same : a.id = id <;> simp [entriesTerm,remove,Elixir.HoldLedger.Attempts.«remove/2»,same,ih,
        reverse,Erlang.erlang.«=:=/2»]

theorem step_bridge (s : State) (event : Event) :
    let (next,intents) := step s event
    Elixir.HoldLedger.Attempts.«step/2» (stateTerm s) (eventTerm event) =
      Except.ok (.tuple #[stateTerm next,intentsTerm s intents]) := by
  cases event with
  | start kind key limit =>
      have occupancy := occupied_bridge s.entries kind key
      by_cases positive : 0 < limit
      all_goals by_cases space : (s.entries.length : Int) < limit
      all_goals cases poison : s.poison
      all_goals cases busy : occupied s.entries kind key
      all_goals cases kind
      all_goals simp only [kindTerm] at occupancy
      all_goals simp [positive,space,poison,busy,step,eventTerm,stateTerm,intentsTerm,intentTerm,kindTerm,phaseTerm,entriesTerm,
        Elixir.HoldLedger.Attempts.«step/2»,count_bridge,occupancy,
        Erlang.erlang.«is_integer/1»,Erlang.erlang.«=:=/2»,
        Erlang.erlang.«>/2»,Erlang.erlang.«</2»,Erlang.erlang.«not/1»,Int.compare_eq_gt,Int.compare_eq_lt,
        Ordering.isGT_iff_eq_gt,Ordering.isLT_iff_eq_lt,
        Lynx.Term.true,Lynx.Term.false]
  | result id | down id | deadline id | shutdown id =>
      simp only [step,change]
      cases found : lookup s.entries id with
      | none => simp [eventTerm,stateTerm,intentsTerm,Elixir.HoldLedger.Attempts.«step/2»,
          Elixir.HoldLedger.Attempts.«change/5»,lookup_bridge,found,foundTerm]
      | some a =>
          have identity := lookup_id found
          have running := replace_bridge found .running
          have stopping := replace_bridge found .stopping
          have committing := replace_bridge found .committing
          simp only [phaseTerm] at running stopping committing
          cases phase : a.phase
          all_goals simp_all [eventTerm,stateTerm,intentsTerm,intentTerm,phaseTerm,
            Elixir.HoldLedger.Attempts.«step/2»,Elixir.HoldLedger.Attempts.«change/5»,Erlang.erlang.«and/2»,
            lookup_bridge,foundTerm,Erlang.erlang.«=:=/2»,
            Lynx.Term.true,Lynx.Term.false]
  | committed id =>
      simp only [step]
      cases found : lookup s.entries id with
      | none => simp [eventTerm,stateTerm,intentsTerm,Elixir.HoldLedger.Attempts.«step/2»,
          lookup_bridge,found,foundTerm]
      | some a =>
          have identity := lookup_id found
          cases phase : a.phase
          all_goals simp_all [eventTerm,stateTerm,intentsTerm,intentTerm,phaseTerm,
            Elixir.HoldLedger.Attempts.«step/2»,lookup_bridge,foundTerm,remove_bridge,
            Erlang.erlang.«=:=/2»,Lynx.Term.true]
  | poison => simp [step,eventTerm,stateTerm,intentsTerm,Elixir.HoldLedger.Attempts.«step/2»]

/-- Each edge executes the actual translated lifecycle on the encoded state. -/
inductive TranslatedRun : State → List Event → State → List Intent → Prop where
  | empty (state) : TranslatedRun state [] state []
  | next {state event successor intents events final tail} :
      Elixir.HoldLedger.Attempts.«step/2» (stateTerm state) (eventTerm event) =
        Except.ok (.tuple #[stateTerm successor,intentsTerm state intents]) →
      TranslatedRun successor events final tail →
      TranslatedRun state (event :: events) final (intents ++ tail)

theorem run_translated (s : State) (events : List Event) :
    TranslatedRun s events (run s events).1 (run s events).2 := by
  induction events generalizing s with
  | nil => exact .empty s
  | cons event events ih =>
      exact .next (step_bridge s event) (ih (step s event).1)

/-- Typed runtime events preserve unique operation/key slots and IDs; persistence
    acknowledgments retire each logical attempt at most once over any finite run.
    The per-edge bridge invokes the actual Lynx-translated Attempts.step/2. -/
theorem translated_history_safety (events : List Event) :
    TranslatedRun initial events (run initial events).1 (run initial events).2 ∧
    Valid (run initial events).1 ∧
    (recordRetirements [] (run initial events).2).Nodup := by
  obtain ⟨valid,retired⟩ := history_safety (ids := []) events initial_valid (by simp [Retired])
  exact ⟨run_translated initial events,valid,retired.1⟩

/-- A persistence request enters committing before another completion can emit;
    no result/death/deadline/shutdown result produces a second persistence intent. -/
theorem committing_quiet {s : State} {id : Int} {a : Attempt}
    (found : lookup s.entries id = some a) (phase : a.phase = .committing) :
    step s (.result id) = (s,[]) ∧ step s (.down id) = (s,[]) ∧
    step s (.deadline id) = (s,[]) ∧ step s (.shutdown id) = (s,[]) := by
  simp [step,change,found,phase]

end HoldLedgerProof.AttemptSafety
