module
public import HoldLedgerProof.Voiding
public import HoldLedgerProof.OutboxTheory
import Lean

public section
namespace HoldLedgerProof.CompositeEntries

structure Entry where
  key : Int
  amount : Int
  status : Lynx.Term

@[expose] def encode : List Entry → Lynx.Term
  | [] => .nil
  | item :: rest => .cons (.tuple #[.integer item.key,.integer item.amount,item.status]) (encode rest)

/-- This is a representation of entry data, without a second ledger transition. -/
theorem shape (entries : Lynx.Term)
    (proper : Elixir.HoldLedger.Spec.«proper_entries?/1» entries = Except.ok Lynx.Term.true) :
    ∃ items : List Entry, entries = encode items := by
  fun_induction Elixir.HoldLedger.Spec.«proper_entries?/1» entries
  all_goals try simp only [Lynx.Except.guard,Lynx.Except.tryWith,Lynx.Except.andAlso,
    bind,Except.bind] at proper
  all_goals repeat' (split at * <;> try simp_all [Lynx.Term.true])
  all_goals simp_all [Erlang.erlang.«is_integer/1»,Lynx.Term.true,Lynx.Term.false]
  all_goals repeat' (split at * <;> try simp_all [])
  all_goals try exact ⟨[],rfl⟩
  all_goals obtain ⟨rest,rfl⟩ := (by assumption : ∃ items : List Entry, _)
  all_goals exact ⟨⟨_,_,_⟩ :: rest,rfl⟩

/-- The physical walk in Spec is preserved, rather than replaced by lookup alone. -/
theorem all_present (entries : List Entry) (items : List Outbox.Obligation) :
    Elixir.HoldLedger.Spec.«all_voiding_present?/2» (encode entries) (Outbox.encode items) = Except.ok Lynx.Term.true ↔
      ∀ entry ∈ entries, entry.status = .atom "voiding" → entry.key ∈ items.map Outbox.Obligation.key := by
  induction entries with
  | nil => simp [encode,Elixir.HoldLedger.Spec.«all_voiding_present?/2»]
  | cons entry rest ih =>
      by_cases voiding : entry.status = .atom "voiding"
      · simp [encode,Elixir.HoldLedger.Spec.«all_voiding_present?/2»,voiding,Outbox.present]
        split <;> simp_all
      · simp [encode,Elixir.HoldLedger.Spec.«all_voiding_present?/2»,voiding]
        simpa only [List.mem_map,Lynx.Term.true] using ih

@[expose] def keysTerm (keys : List Int) : Lynx.Term := .list (keys.map Lynx.Term.integer)

theorem seen (keys : List Int) (key : Int) :
    Elixir.HoldLedger.Spec.«seen?/2» (keysTerm keys) (.integer key) =
      Except.ok (if key ∈ keys then Lynx.Term.true else Lynx.Term.false) := by
  induction keys with
  | nil => rfl
  | cons first rest ih =>
      simp only [keysTerm] at ih
      by_cases same : first = key
      · subst first
        simp [keysTerm,Lynx.Term.list,Elixir.HoldLedger.Spec.«seen?/2»,Erlang.erlang.«==/2»]
      · have different : key ≠ first := Ne.symm same
        simp [keysTerm,Lynx.Term.list,Elixir.HoldLedger.Spec.«seen?/2»,Erlang.erlang.«==/2»,
          Lynx.Term.compare_integers,same,different,ih]

theorem unique (entries : List Entry) (visited : List Int) :
    Elixir.HoldLedger.Spec.«unique_keys_seen?/2» (encode entries) (keysTerm visited) = Except.ok Lynx.Term.true ↔
      (entries.map Entry.key).Nodup ∧ ∀ entry ∈ entries, entry.key ∉ visited := by
  induction entries generalizing visited with
  | nil => simp [encode,Elixir.HoldLedger.Spec.«unique_keys_seen?/2»]
  | cons entry rest ih =>
      have recursive := ih (entry.key :: visited)
      by_cases previous : entry.key ∈ visited
      · simp [encode,Elixir.HoldLedger.Spec.«unique_keys_seen?/2»,seen,previous]
      · simp only [encode,Elixir.HoldLedger.Spec.«unique_keys_seen?/2»,seen,
          ite_eq_right previous,Lynx.Term.false,bind,Except.bind]
        change Elixir.HoldLedger.Spec.«unique_keys_seen?/2» (encode rest) (keysTerm (entry.key :: visited)) =
          Except.ok Lynx.Term.true ↔ _
        rw [recursive]
        simp only [List.map_cons,List.nodup_cons,List.mem_cons,forall_eq_or_imp,not_or,List.mem_map] at *
        grind

theorem lookup_member (entries : List Entry) (key amount : Int) (status : Lynx.Term)
    (found : Elixir.HoldLedger.Spec.«lookup/2» (encode entries) (.integer key) =
      Except.ok (.tuple #[.atom "ok",.tuple #[.integer key,.integer amount,status]])) :
    ∃ entry ∈ entries, entry.key = key ∧ entry.amount = amount ∧ entry.status = status := by
  induction entries with
  | nil => simp [encode,Elixir.HoldLedger.Spec.«lookup/2»] at found
  | cons entry rest ih =>
      by_cases same : entry.key = key
      · simp [encode,Elixir.HoldLedger.Spec.«lookup/2»,same,Erlang.erlang.«==/2»] at found
        exact ⟨entry,by simp,same,found.1,found.2⟩
      · have tail : Elixir.HoldLedger.Spec.«lookup/2» (encode rest) (.integer key) =
            Except.ok (.tuple #[.atom "ok",.tuple #[.integer key,.integer amount,status]]) := by
          simpa [encode,Elixir.HoldLedger.Spec.«lookup/2»,same,Erlang.erlang.«==/2»,
            Lynx.Term.compare_integers,Int.compare_eq_eq,bind,Except.bind] using found
        obtain ⟨selected,member,hkey,hamount,hstatus⟩ := ih tail
        exact ⟨selected,by simp [member],hkey,hamount,hstatus⟩

theorem lookup_of_member (entries : List Entry) (entry : Entry)
    (distinct : (entries.map Entry.key).Nodup) (member : entry ∈ entries) :
    Elixir.HoldLedger.Spec.«lookup/2» (encode entries) (.integer entry.key) =
      Except.ok (.tuple #[.atom "ok",.tuple #[.integer entry.key,.integer entry.amount,entry.status]]) := by
  induction entries with
  | nil => simp at member
  | cons head rest ih =>
      obtain ⟨not_present,tail_distinct⟩ := List.nodup_cons.mp distinct
      rcases List.mem_cons.mp member with rfl | tail
      · simp [encode,Elixir.HoldLedger.Spec.«lookup/2»,Erlang.erlang.«==/2»]
      · have different : head.key ≠ entry.key := by
          intro equal
          apply not_present
          exact List.mem_map.mpr ⟨entry,tail,equal.symm⟩
        simp [encode,Elixir.HoldLedger.Spec.«lookup/2»,different,ih tail_distinct tail,
          Erlang.erlang.«==/2»,Lynx.Term.compare_integers]

theorem at_physical (entries : List Entry) (key : Int)
    (distinct : (entries.map Entry.key).Nodup) :
    Voiding.At (encode entries) key ↔ ∃ entry ∈ entries, entry.key = key ∧ entry.status = .atom "voiding" := by
  constructor
  · rintro ⟨amount,located⟩
    obtain ⟨entry,member,hkey,_,status⟩ := lookup_member entries key amount (.atom "voiding") located
    exact ⟨entry,member,hkey,status⟩
  · rintro ⟨entry,member,rfl,status⟩
    exact ⟨entry.amount,by simpa [status] using lookup_of_member entries entry distinct member⟩

theorem all_present_lookup (entries : List Entry) (items : List Outbox.Obligation)
    (distinct : (entries.map Entry.key).Nodup) :
    Elixir.HoldLedger.Spec.«all_voiding_present?/2» (encode entries) (Outbox.encode items) = Except.ok Lynx.Term.true ↔
      ∀ key, Voiding.At (encode entries) key → key ∈ items.map Outbox.Obligation.key := by
  rw [all_present]
  constructor
  · intro physical key located
    obtain ⟨entry,member,equal,status⟩ := (at_physical entries key distinct).mp located
    simpa [equal] using physical entry member status
  · intro lookup entry member status
    apply lookup entry.key
    exact (at_physical entries entry.key distinct).mpr ⟨entry,member,rfl,status⟩

end HoldLedgerProof.CompositeEntries
