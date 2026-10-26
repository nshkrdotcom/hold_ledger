module
public import HoldLedgerProof.ExposureCells
import Lean

public section
namespace HoldLedgerProof.ExposureUpdates
attribute [local instance] Classical.propDecidable
open HoldLedgerProof.Exposure HoldLedgerProof.ExposureCells

@[expose] def update : List Entry → Int → Lynx.Term → List Entry
  | [], _, _ => []
  | entry :: rest, key, status =>
      if entry.key = key then {entry with status := status} :: rest
      else entry :: update rest key status

@[expose] def put : List Entry → Int → Int → Lynx.Term → List Entry
  | [], key, amount, status => [⟨key,amount,status⟩]
  | entry :: rest, key, amount, status =>
      if entry.key = key then {entry with status := status} :: rest
      else entry :: put rest key amount status

@[expose] noncomputable def restart : List Entry → List Entry
  | [] => []
  | entry :: rest => by
      classical
      exact {entry with status := if entry.status = .atom "sent" then .atom "unknown" else entry.status} :: restart rest

theorem update_bridge (entries : List Entry) (key : Int) (status : Lynx.Term) :
    Elixir.HoldLedger.Ledger.«set_status/3» (entriesTerm entries) (.integer key) status =
      Except.ok (entriesTerm (update entries key status)) := by
  induction entries with
  | nil => rfl
  | cons entry rest ih =>
      by_cases same : entry.key = key <;>
        simp [entriesTerm,update,Elixir.HoldLedger.Ledger.«set_status/3»,Erlang.erlang.«==/2»,
          Lynx.Term.compare_integers,same,ih]

theorem put_bridge (entries : List Entry) (key amount : Int) (status : Lynx.Term) :
    Elixir.HoldLedger.Environment.«put/4» (entriesTerm entries) (.integer key) (.integer amount) status =
      Except.ok (entriesTerm (put entries key amount status)) := by
  induction entries with
  | nil => rfl
  | cons entry rest ih =>
      by_cases same : entry.key = key
      · subst key
        simp [entriesTerm,put,Elixir.HoldLedger.Environment.«put/4»,Erlang.erlang.«=:=/2»]
      · simp [entriesTerm,put,Elixir.HoldLedger.Environment.«put/4»,Erlang.erlang.«=:=/2»,
          same,Ne.symm same,ih]

theorem restart_bridge (entries : List Entry) :
    Elixir.HoldLedger.Ledger.«mark_unknown/1» (entriesTerm entries) = Except.ok (entriesTerm (restart entries)) := by
  induction entries with
  | nil => rfl
  | cons entry rest ih =>
      by_cases sent : entry.status = .atom "sent" <;>
        simp [entriesTerm,restart,Elixir.HoldLedger.Ledger.«mark_unknown/1»,sent,ih]

theorem update_lookup (entries : List Entry) (key query : Int) (status : Lynx.Term) :
    lookup (update entries key status) query =
      (lookup entries query).map (fun entry => if key = query then {entry with status := status} else entry) := by
  induction entries with
  | nil => rfl
  | cons entry rest ih =>
      by_cases target : entry.key = key
      all_goals by_cases selected : entry.key = query
      all_goals simp_all [lookup,update]
      all_goals grind

theorem restart_lookup (entries : List Entry) (key : Int) :
    lookup (restart entries) key = (lookup entries key).map
      (fun entry => {entry with status := if entry.status = .atom "sent" then .atom "unknown" else entry.status}) := by
  classical
  induction entries with
  | nil => rfl
  | cons entry rest ih =>
      by_cases selected : entry.key = key <;> simp [lookup,restart,selected,ih]

theorem update_keys (entries : List Entry) (key : Int) (status : Lynx.Term) :
    (update entries key status).map Entry.key = entries.map Entry.key := by
  induction entries with
  | nil => rfl
  | cons entry rest ih => by_cases selected : entry.key = key <;> simp [update,selected,ih]

theorem restart_keys (entries : List Entry) : (restart entries).map Entry.key = entries.map Entry.key := by
  induction entries with
  | nil => rfl
  | cons entry rest ih => simp [restart,ih]

theorem lookup_prepend (entries : List Entry) (entry : Entry) (key : Int) :
    lookup (entry :: entries) key = if entry.key = key then some entry else lookup entries key := rfl

theorem put_lookup (entries : List Entry) (key amount query : Int) (status : Lynx.Term) :
    lookup (put entries key amount status) query =
      if key = query then some ⟨key,((lookup entries key).map Entry.amount).getD amount,status⟩ else lookup entries query := by
  induction entries with
  | nil => by_cases same : key = query <;> simp [put,lookup,same]
  | cons entry rest ih =>
      by_cases target : entry.key = key
      all_goals by_cases selected : entry.key = query
      all_goals simp_all [lookup,put]
      all_goals grind

theorem put_keys_subset (entries : List Entry) (key amount : Int) (status : Lynx.Term) (query : Int)
    (member : query ∈ (put entries key amount status).map Entry.key) : query = key ∨ query ∈ entries.map Entry.key := by
  induction entries with
  | nil => simpa [put] using member
  | cons entry rest ih =>
      by_cases target : entry.key = key
      · simp [put,target] at member
        rcases member with first | rest
        · exact Or.inl first
        · exact Or.inr (List.mem_cons_of_mem _ (by simpa using rest))
      · simp only [put,ite_eq_right target,List.map_cons,List.mem_cons] at member
        rcases member with first | rest
        · exact Or.inr (by simp [first])
        · rcases ih rest with equal | tail
          · exact Or.inl equal
          · exact Or.inr (List.mem_cons_of_mem _ tail)

theorem put_unique (entries : List Entry) (key amount : Int) (status : Lynx.Term)
    (unique : (entries.map Entry.key).Nodup) : ((put entries key amount status).map Entry.key).Nodup := by
  induction entries with
  | nil => simp [put]
  | cons entry rest ih =>
      obtain ⟨absent,tail⟩ := List.nodup_cons.mp unique
      by_cases target : entry.key = key
      · simpa [put,target] using unique
      · simp only [put,ite_eq_right target,List.map_cons,List.nodup_cons]
        refine ⟨?_,ih tail⟩
        intro member
        rcases put_keys_subset rest key amount status entry.key member with equal | member
        · exact target equal
        · exact absent member

theorem replace_cell (before after issued next_issued records next_records : List Entry) (key : Int)
    (coupled : Coupled before issued records)
    (elsewhere : ∀ query, query ≠ key → lookup after query = lookup before query ∧
      lookup next_issued query = lookup issued query ∧ lookup next_records query = lookup records query)
    (selected : Cell (lookup after key) (lookup next_issued key) (lookup next_records key)) :
    Coupled after next_issued next_records := by
  intro query
  by_cases same : query = key
  · simpa [same] using selected
  · obtain ⟨ledger,intents,remote⟩ := elsewhere query same
    simpa [ledger,intents,remote] using coupled query

theorem ledger_lookup (entries : List Entry) (key : Int) :
    Elixir.HoldLedger.Ledger.«find/2» (entriesTerm entries) (.integer key) = Except.ok (observed (lookup entries key)) := by
  induction entries with
  | nil => rfl
  | cons entry rest ih =>
      by_cases same : entry.key = key <;>
        simp [entriesTerm,lookup,observed,Elixir.HoldLedger.Ledger.«find/2»,Erlang.erlang.«==/2»,
          Lynx.Term.compare_integers,same,ih]

theorem lookup_none (entries : List Entry) (key : Int) : lookup entries key = none ↔ key ∉ entries.map Entry.key := by
  induction entries with
  | nil => simp [lookup]
  | cons entry rest ih =>
      by_cases same : entry.key = key
      · simp [lookup,same]
      · simp [lookup,same,Ne.symm same,ih]

theorem coupled_update (entries issued records : List Entry) (key : Int) (entry : Entry) (status : Lynx.Term)
    (coupled : Coupled entries issued records) (found : lookup entries key = some entry)
    (selected : Cell (some {entry with status := status}) (lookup issued key) (lookup records key)) :
    Coupled (update entries key status) issued records := by
  apply replace_cell entries (update entries key status) issued issued records records key coupled
  · intro query different
    simp [update_lookup,Ne.symm different]
  · simpa [update_lookup,found] using selected

theorem coupled_fresh (entries issued records : List Entry) (key amount : Int)
    (coupled : Coupled entries issued records) (absent : lookup entries key = none) :
    Coupled (⟨key,amount,.atom "reserved"⟩ :: entries) issued records := by
  have cell := coupled key
  simp only [absent,Cell] at cell
  obtain ⟨issued_absent,remote_absent⟩ := cell
  apply replace_cell entries _ issued issued records records key coupled
  · intro query different
    simp [lookup,Ne.symm different]
  · simp [lookup,issued_absent,remote_absent,Cell]

theorem coupled_restart (entries issued records : List Entry) (coupled : Coupled entries issued records) :
    Coupled (restart entries) issued records := by
  intro key
  have cell := coupled key
  rw [restart_lookup]
  cases local_lookup : lookup entries key
  all_goals cases issued_lookup : lookup issued key
  all_goals cases remote_lookup : lookup records key
  all_goals simp only [local_lookup,issued_lookup,remote_lookup,Option.map_none,Option.map_some,Cell] at *
  all_goals try assumption
  all_goals split <;> simp_all [] <;> grind

end HoldLedgerProof.ExposureUpdates
