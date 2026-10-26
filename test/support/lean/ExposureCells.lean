module
public import HoldLedgerProof.ExposureFacts
import Lean

public section
set_option maxHeartbeats 4000000
namespace HoldLedgerProof.ExposureCells
open HoldLedgerProof.Exposure

@[expose] def lookup : List Entry → Int → Option Entry
  | [], _ => none
  | entry :: rest, key => if entry.key = key then some entry else lookup rest key

@[expose] def observed : Option Entry → Lynx.Term
  | none => .atom "not_found"
  | some entry => .tuple #[.atom "ok",.tuple #[.integer entry.key,.integer entry.amount,entry.status]]

@[expose] def raw : Option Entry → Lynx.Term
  | none => .atom "not_found"
  | some entry => .tuple #[.integer entry.key,.integer entry.amount,entry.status]

theorem lookup_bridge (entries : List Entry) (key : Int) :
    Elixir.HoldLedger.Spec.«lookup/2» (entriesTerm entries) (.integer key) = Except.ok (observed (lookup entries key)) := by
  induction entries with
  | nil => rfl
  | cons entry rest ih =>
      by_cases same : entry.key = key <;>
        simp [entriesTerm,lookup,observed,Elixir.HoldLedger.Spec.«lookup/2»,Erlang.erlang.«==/2»,
          Lynx.Term.compare_integers,same,ih,]

theorem environment_lookup (entries : List Entry) (key : Int) :
    Elixir.HoldLedger.Environment.«lookup/2» (entriesTerm entries) (.integer key) = Except.ok (raw (lookup entries key)) := by
  induction entries with
  | nil => rfl
  | cons entry rest ih =>
      by_cases same : entry.key = key
      · subst key
        simp [entriesTerm,lookup,raw,Elixir.HoldLedger.Environment.«lookup/2»,Erlang.erlang.«=:=/2»,]
      · simp [entriesTerm,lookup,raw,Elixir.HoldLedger.Environment.«lookup/2»,Erlang.erlang.«=:=/2»,
          same,Ne.symm same,ih,]

theorem lookup_key {entries : List Entry} {key : Int} {entry : Entry}
    (found : lookup entries key = some entry) : entry.key = key := by
  induction entries with
  | nil => simp [lookup] at found
  | cons first rest ih =>
      by_cases same : first.key = key
      · simp [lookup,same] at found
        simpa [← found] using same
      · exact ih (by simpa [lookup,same] using found)

theorem lookup_member {entries : List Entry} {key : Int} {entry : Entry}
    (found : lookup entries key = some entry) : entry ∈ entries := by
  induction entries with
  | nil => simp [lookup] at found
  | cons first rest ih =>
      by_cases same : first.key = key
      · simp [lookup,same] at found
        simp [found]
      · exact List.mem_cons_of_mem _ (ih (by simpa [lookup,same] using found))

theorem lookup_of_member {entries : List Entry} {entry : Entry}
    (unique : (entries.map Entry.key).Nodup) (member : entry ∈ entries) : lookup entries entry.key = some entry := by
  have native := ExposureFacts.lookup_of_member entries entry unique member
  rw [lookup_bridge] at native
  cases found : lookup entries entry.key with
  | none => simp [found,observed] at native
  | some actual =>
      simp [found,observed] at native
      have equal : actual = entry := by cases actual; cases entry; simp_all
      simp [equal]

/-- A single identity's admissible held_entry/issued/remote combinations. -/
@[expose] def Cell : Option Entry → Option Entry → Option Entry → Prop
  | none, issued, remote => issued = none ∧ remote = none
  | some held_entry, none, none => held_entry.status = .atom "reserved" ∨ held_entry.status = .atom "voided"
  | some held_entry, some issued, none => issued.amount = held_entry.amount ∧ issued.status = .atom "issued" ∧
      (held_entry.status = .atom "sent" ∨ held_entry.status = .atom "unknown")
  | some held_entry, some issued, some remote => issued.amount = held_entry.amount ∧ issued.status = .atom "issued" ∧
      remote.amount = held_entry.amount ∧
      ((held_entry.status = .atom "sent" ∨ held_entry.status = .atom "unknown") ∧
          (remote.status = .atom "approved" ∨ remote.status = .atom "declined") ∨
        held_entry.status = .atom "authorized" ∧ remote.status = .atom "approved" ∨
        held_entry.status = .atom "voiding" ∧ (remote.status = .atom "approved" ∨ remote.status = .atom "voided") ∨
        held_entry.status = .atom "declined" ∧ remote.status = .atom "declined" ∨
        held_entry.status = .atom "voided" ∧ remote.status = .atom "voided")
  | some _, none, some _ => False

@[expose] def Coupled (entries issued records : List Entry) : Prop :=
  ∀ key, Cell (lookup entries key) (lookup issued key) (lookup records key)

theorem cell_local (entry : Entry) (issued remote : Option Entry)
    (issued_key : ∀ item, issued = some item → item.key = entry.key)
    (remote_key : ∀ item, remote = some item → item.key = entry.key) :
    Cell (some entry) issued remote ↔
      Elixir.HoldLedger.Spec.«entry_agrees?/5» (.integer entry.key) (.integer entry.amount) entry.status
        (observed issued) (observed remote) = Except.ok Lynx.Term.true := by
  cases issued with
  | none =>
      cases remote with
      | none =>
          by_cases reserved : entry.status = .atom "reserved"
          all_goals by_cases voided : entry.status = .atom "voided"
          all_goals simp [Cell,observed,Elixir.HoldLedger.Spec.«entry_agrees?/5»,reserved,voided]
      | some record => simp [Cell,observed,Elixir.HoldLedger.Spec.«entry_agrees?/5»]
  | some intent =>
      have equal := issued_key intent rfl
      cases remote with
      | none =>
          by_cases issue_status : intent.status = .atom "issued"
          all_goals by_cases amount : intent.amount = entry.amount
          all_goals by_cases sent : entry.status = .atom "sent"
          all_goals by_cases unknown : entry.status = .atom "unknown"
          all_goals simp_all [Cell,observed,Elixir.HoldLedger.Spec.«entry_agrees?/5»,Erlang.erlang.«=:=/2»,Erlang.erlang.«and/2»,
            ]
      | some record =>
          have remote_equal := remote_key record rfl
          by_cases issue_status : intent.status = .atom "issued"
          all_goals by_cases amount : intent.amount = entry.amount
          all_goals by_cases remote_amount : record.amount = entry.amount
          all_goals by_cases sent : entry.status = .atom "sent"
          all_goals try solve | simp_all [Cell,observed,Elixir.HoldLedger.Spec.«entry_agrees?/5»,Erlang.erlang.«=:=/2»,Erlang.erlang.«and/2»,
            Lynx.Except.guard,Lynx.Except.tryWith,Lynx.Except.andAlso,bind,Except.bind]
          all_goals by_cases unknown : entry.status = .atom "unknown"
          all_goals try solve | simp_all [Cell,observed,Elixir.HoldLedger.Spec.«entry_agrees?/5»,Erlang.erlang.«=:=/2»,Erlang.erlang.«and/2»,
            Lynx.Except.guard,Lynx.Except.tryWith,Lynx.Except.andAlso,bind,Except.bind]
          all_goals by_cases authorized : entry.status = .atom "authorized"
          all_goals try solve | simp_all [Cell,observed,Elixir.HoldLedger.Spec.«entry_agrees?/5»,Erlang.erlang.«=:=/2»,Erlang.erlang.«and/2»,
            Lynx.Except.guard,Lynx.Except.tryWith,Lynx.Except.andAlso,bind,Except.bind]
          all_goals by_cases voiding : entry.status = .atom "voiding"
          all_goals try solve | simp_all [Cell,observed,Elixir.HoldLedger.Spec.«entry_agrees?/5»,Erlang.erlang.«=:=/2»,Erlang.erlang.«and/2»,
            Lynx.Except.guard,Lynx.Except.tryWith,Lynx.Except.andAlso,bind,Except.bind]
          all_goals by_cases declined : entry.status = .atom "declined"
          all_goals try solve | simp_all [Cell,observed,Elixir.HoldLedger.Spec.«entry_agrees?/5»,Erlang.erlang.«=:=/2»,Erlang.erlang.«and/2»,
            Lynx.Except.guard,Lynx.Except.tryWith,Lynx.Except.andAlso,bind,Except.bind]
          all_goals by_cases voided : entry.status = .atom "voided"
          all_goals try solve | simp_all [Cell,observed,Elixir.HoldLedger.Spec.«entry_agrees?/5»,Erlang.erlang.«=:=/2»,Erlang.erlang.«and/2»,
            Lynx.Except.guard,Lynx.Except.tryWith,Lynx.Except.andAlso,bind,Except.bind]
          all_goals by_cases approved : record.status = .atom "approved"
          all_goals by_cases declined : record.status = .atom "declined"
          all_goals by_cases voided : record.status = .atom "voided"
          all_goals simp_all [Cell,observed,Elixir.HoldLedger.Spec.«entry_agrees?/5»,Erlang.erlang.«=:=/2»,Erlang.erlang.«and/2»,
            Lynx.Except.andAlso,]

end HoldLedgerProof.ExposureCells
