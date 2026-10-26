module
public import HoldLedgerProof.CompositeSafety
public import HoldLedgerProof.ExposureBound
import all Lynx.Term.Compare
import Lean

public section
set_option maxHeartbeats 4000000
namespace HoldLedgerProof.ExposureFacts
open HoldLedgerProof.Exposure

@[expose] def physical (entries : List Exposure.Entry) : List CompositeEntries.Entry :=
  entries.map (fun entry => ⟨entry.key,entry.amount,entry.status⟩)

theorem physical_encode (entries : List Exposure.Entry) :
    CompositeEntries.encode (physical entries) = entriesTerm entries := by
  induction entries with
  | nil => rfl
  | cons entry rest ih => simp [physical,CompositeEntries.encode,entriesTerm] at *; exact ih

theorem lookup_of_member (entries : List Exposure.Entry) (entry : Exposure.Entry)
    (distinct : (entries.map Exposure.Entry.key).Nodup) (member : entry ∈ entries) :
    Elixir.HoldLedger.Spec.«lookup/2» (entriesTerm entries) (.integer entry.key) =
      Except.ok (.tuple #[.atom "ok",.tuple #[.integer entry.key,.integer entry.amount,entry.status]]) := by
  have actual := CompositeEntries.lookup_of_member (physical entries)
    ⟨entry.key,entry.amount,entry.status⟩ (by simpa [physical,List.map_map,Function.comp_def] using distinct)
    (List.mem_map.mpr ⟨entry,member,rfl⟩)
  simpa [physical_encode] using actual

theorem ledger_shape (entries : Lynx.Term)
    (proper : Elixir.HoldLedger.Spec.«proper_entries?/1» entries = Except.ok Lynx.Term.true) :
    ∃ records : List Entry, entries = entriesTerm records := by
  obtain ⟨physical,rfl⟩ := CompositeEntries.shape entries proper
  refine ⟨physical.map (fun entry => ⟨entry.key,entry.amount,entry.status⟩),?_⟩
  clear proper
  induction physical with
  | nil => rfl
  | cons entry rest ih => simp [CompositeEntries.encode,entriesTerm] at *; exact ih

theorem issued_shape (issued entries seen : Lynx.Term)
    (valid : Elixir.HoldLedger.Spec.«issued_valid?/3» issued entries seen = Except.ok Lynx.Term.true) :
    ∃ records : List Exposure.Entry, issued = entriesTerm records := by
  fun_induction Elixir.HoldLedger.Spec.«issued_valid?/3» issued entries seen
  all_goals try simp only [Erlang.erlang.«is_integer/1»,
    Lynx.Except.guard,Lynx.Except.tryWith,Lynx.Except.andAlso,bind,Except.bind] at valid
  all_goals repeat' (split at * <;> try simp_all [Lynx.Term.true,Lynx.Term.false])
  all_goals try exact ⟨[],rfl⟩
  all_goals obtain ⟨rest,rfl⟩ := (by assumption : ∃ records : List Exposure.Entry, _)
  all_goals exact ⟨⟨_,_,.atom "issued"⟩ :: rest,rfl⟩

theorem remote_shape (remote issued seen : Lynx.Term)
    (valid : Elixir.HoldLedger.Spec.«remote_valid?/3» remote issued seen = Except.ok Lynx.Term.true) :
    ∃ records : List Exposure.Entry, remote = entriesTerm records := by
  fun_induction Elixir.HoldLedger.Spec.«remote_valid?/3» remote issued seen
  all_goals try simp only [Erlang.erlang.«is_integer/1»,
    Lynx.Except.guard,Lynx.Except.tryWith,Lynx.Except.andAlso,bind,Except.bind] at valid
  all_goals repeat' (split at * <;> try simp_all [Lynx.Term.true,Lynx.Term.false])
  all_goals try exact ⟨[],rfl⟩
  all_goals obtain ⟨rest,rfl⟩ := (by assumption : ∃ records : List Exposure.Entry, _)
  all_goals exact ⟨⟨_,_,_⟩ :: rest,rfl⟩

theorem local_agree (entries : List Exposure.Entry) (issued remote : Lynx.Term) :
    Elixir.HoldLedger.Spec.«local_remote_agree?/3» (entriesTerm entries) issued remote = Except.ok Lynx.Term.true ↔
      ∀ entry ∈ entries,
        (do let issued_record ← Elixir.HoldLedger.Spec.«lookup/2» issued (.integer entry.key)
            let remote_record ← Elixir.HoldLedger.Spec.«lookup/2» remote (.integer entry.key)
            Elixir.HoldLedger.Spec.«entry_agrees?/5» (.integer entry.key) (.integer entry.amount) entry.status issued_record remote_record) =
              Except.ok Lynx.Term.true := by
  induction entries with
  | nil => simp [entriesTerm,Elixir.HoldLedger.Spec.«local_remote_agree?/3»]
  | cons entry rest ih =>
      simp only [entriesTerm,Elixir.HoldLedger.Spec.«local_remote_agree?/3»,List.mem_cons,forall_eq_or_imp,
        bind,Except.bind]
      constructor
      · intro valid
        repeat' (split at valid <;> try simp_all [Lynx.Term.true,bind,Except.bind])
        all_goals simpa [bind,Except.bind] using ih
      · rintro ⟨first,tail⟩
        have rest := ih.mpr tail
        cases issued_lookup : Elixir.HoldLedger.Spec.«lookup/2» issued (.integer entry.key)
        all_goals cases remote_lookup : Elixir.HoldLedger.Spec.«lookup/2» remote (.integer entry.key)
        all_goals simp_all [bind,Except.bind]
        all_goals repeat' (split <;> simp_all [bind,Except.bind])

theorem native_lookup_shape (entries : List Exposure.Entry) (key : Int) :
    Elixir.HoldLedger.Spec.«lookup/2» (entriesTerm entries) (.integer key) = Except.ok (.atom "not_found") ∨
    ∃ amount status, Elixir.HoldLedger.Spec.«lookup/2» (entriesTerm entries) (.integer key) =
      Except.ok (.tuple #[.atom "ok",.tuple #[.integer key,.integer amount,status]]) := by
  induction entries with
  | nil => exact Or.inl rfl
  | cons entry rest ih =>
      by_cases same : entry.key = key
      · exact Or.inr ⟨entry.amount,entry.status,by simp [entriesTerm,Elixir.HoldLedger.Spec.«lookup/2»,same,Erlang.erlang.«==/2»]⟩
      · simpa [entriesTerm,Elixir.HoldLedger.Spec.«lookup/2»,same,Erlang.erlang.«==/2»,
          Lynx.Term.compare_integers,Int.compare_eq_eq,bind,Except.bind] using ih

theorem exact_record (key amount candidate : Int) (status : Lynx.Term) (tag : String) :
    (Lynx.Term.tuple #[.atom "ok",.tuple #[.integer key,.integer amount,status]]).exactCompare
      (.tuple #[.atom "ok",.tuple #[.integer key,.integer candidate,.atom tag]]) = Ordering.eq ↔
      amount = candidate ∧ status = .atom tag := by
  simp only [Lynx.Term.exactCompare_tuple,List.compareLex,Ordering.then_eq_eq]
  cases ha : (Lynx.Term.integer amount).exactCompare (.integer candidate)
  all_goals cases hs : status.exactCompare (.atom tag)
  all_goals simp_all [Lynx.Term.exactCompare_eq_atom]
  all_goals repeat' intro equal
  all_goals subst_vars
  all_goals simp_all

/-- Each valid issued record names a positive, already-dispatched ledger entry. -/
theorem issued_member (issued : List Exposure.Entry) (entries seen : Lynx.Term)
    (proper : Elixir.HoldLedger.Spec.«proper_entries?/1» entries = Except.ok Lynx.Term.true)
    (valid : Elixir.HoldLedger.Spec.«issued_valid?/3» (entriesTerm issued) entries seen = Except.ok Lynx.Term.true) :
    ∀ item ∈ issued, item.status = .atom "issued" ∧ 0 < item.amount ∧
      ∃ status, Elixir.HoldLedger.Spec.«lookup/2» entries (.integer item.key) =
        Except.ok (.tuple #[.atom "ok",.tuple #[.integer item.key,.integer item.amount,status]]) := by
  induction issued generalizing seen with
  | nil => simp
  | cons item rest ih =>
      rcases Voiding.integer_lookup_shape entries item.key proper with ⟨_,absent⟩ | ⟨amount,status,_,located,_⟩
      all_goals by_cases issued_status : item.status = .atom "issued"
      all_goals simp only [entriesTerm,Elixir.HoldLedger.Spec.«issued_valid?/3»,Erlang.erlang.«is_integer/1»,
        Lynx.Except.guard,Lynx.Except.tryWith,Lynx.Except.andAlso,bind,Except.bind] at valid
      all_goals repeat' (split at valid <;> try simp_all [Lynx.Term.true,Lynx.Term.false])
      all_goals simp_all [Erlang.erlang.«>/2»,Ordering.isGT_iff_eq_gt,
        Elixir.HoldLedger.Spec.«issued_local?/2»,Erlang.erlang.«=:=/2»]
      all_goals repeat' (split at * <;> try simp_all [])
      all_goals try grind [Int.compare_eq_gt]

theorem absent_comparison (key amount : Int) :
    (Lynx.Term.atom "not_found").exactCompare
      (.tuple #[.atom "ok",.tuple #[.integer key,.integer amount,.atom "issued"]]) = Ordering.lt := by
  rw [Lynx.Term.exactCompare_eq_step]
  rfl

/-- Each remote record has an exact issued-identity/amount witness. -/
theorem remote_member (records issued : List Exposure.Entry) (seen : Lynx.Term)
    (valid : Elixir.HoldLedger.Spec.«remote_valid?/3» (entriesTerm records) (entriesTerm issued) seen = Except.ok Lynx.Term.true) :
    ∀ item ∈ records, 0 < item.amount ∧
      Elixir.HoldLedger.Spec.«lookup/2» (entriesTerm issued) (.integer item.key) =
        Except.ok (.tuple #[.atom "ok",.tuple #[.integer item.key,.integer item.amount,.atom "issued"]]) := by
  induction records generalizing seen with
  | nil => simp
  | cons item rest ih =>
      rcases native_lookup_shape issued item.key with absent | ⟨amount,status,located⟩
      all_goals simp only [entriesTerm,Elixir.HoldLedger.Spec.«remote_valid?/3»,Erlang.erlang.«is_integer/1»,
        Lynx.Except.guard,Lynx.Except.tryWith,Lynx.Except.andAlso,bind,Except.bind] at valid
      all_goals repeat' (split at valid <;> try simp_all [Lynx.Term.true])
      all_goals simp_all [Erlang.erlang.«>/2»,Ordering.isGT_iff_eq_gt,Int.compare_eq_gt,Erlang.erlang.«=:=/2»,exact_record]
      all_goals repeat' (split at * <;> try simp_all [])
      all_goals try simp_all [absent_comparison,exact_record]
      all_goals exact ih _ valid

theorem issued_parts (item : Entry) (rest : List Entry) (entries seen : Lynx.Term)
    (valid : Elixir.HoldLedger.Spec.«issued_valid?/3» (entriesTerm (item :: rest)) entries seen = Except.ok Lynx.Term.true) :
    item.status = .atom "issued" ∧
      Elixir.HoldLedger.Spec.«seen?/2» seen (.integer item.key) = Except.ok Lynx.Term.false ∧
      Elixir.HoldLedger.Spec.«issued_valid?/3» (entriesTerm rest) entries (.cons (.integer item.key) seen) = Except.ok Lynx.Term.true := by
  rcases item with ⟨key,amount,status⟩
  by_cases issued : status = .atom "issued"
  · subst status
    simp only [entriesTerm,Elixir.HoldLedger.Spec.«issued_valid?/3»,Erlang.erlang.«is_integer/1»,
      Lynx.Except.guard,Lynx.Except.tryWith,Lynx.Except.andAlso,bind,Except.bind] at valid
    repeat' (split at * <;> try simp_all [Lynx.Term.true,Lynx.Term.false])
  · simp [entriesTerm,Elixir.HoldLedger.Spec.«issued_valid?/3»,issued] at valid

theorem issued_unique (records : List Exposure.Entry) (entries : Lynx.Term) (visited : List Int)
    (valid : Elixir.HoldLedger.Spec.«issued_valid?/3» (entriesTerm records) entries (CompositeEntries.keysTerm visited) = Except.ok Lynx.Term.true) :
    (records.map Exposure.Entry.key).Nodup ∧ ∀ entry ∈ records, entry.key ∉ visited := by
  induction records generalizing visited with
  | nil => simp
  | cons item rest ih =>
      obtain ⟨_,not_seen,tail_valid⟩ := issued_parts item rest entries (CompositeEntries.keysTerm visited) valid
      have tail_check : Elixir.HoldLedger.Spec.«issued_valid?/3» (entriesTerm rest) entries (CompositeEntries.keysTerm (item.key :: visited)) = Except.ok Lynx.Term.true := tail_valid
      obtain ⟨unique,tail⟩ := ih (item.key :: visited) tail_check
      simp only [CompositeEntries.seen] at not_seen
      split at not_seen <;> simp_all [Lynx.Term.true,Lynx.Term.false,List.map_cons,List.nodup_cons,List.mem_map]
      all_goals grind

theorem remote_unique (records : List Exposure.Entry) (issued : Lynx.Term) (visited : List Int)
    (valid : Elixir.HoldLedger.Spec.«remote_valid?/3» (entriesTerm records) issued (CompositeEntries.keysTerm visited) = Except.ok Lynx.Term.true) :
    (records.map Exposure.Entry.key).Nodup ∧ ∀ entry ∈ records, entry.key ∉ visited := by
  induction records generalizing visited with
  | nil => simp
  | cons item rest ih =>
      simp only [entriesTerm,Elixir.HoldLedger.Spec.«remote_valid?/3»,Erlang.erlang.«is_integer/1»,
        Lynx.Except.guard,Lynx.Except.tryWith,Lynx.Except.andAlso,bind,Except.bind] at valid
      repeat' (split at valid <;> try simp_all [Lynx.Term.true])
      all_goals try simp_all [CompositeEntries.seen]
      all_goals repeat' (split at * <;> try simp_all [])
      all_goals have tail_valid : Elixir.HoldLedger.Spec.«remote_valid?/3» (entriesTerm rest) issued (CompositeEntries.keysTerm (item.key :: visited)) = Except.ok Lynx.Term.true := by assumption
      all_goals obtain ⟨unique,tail⟩ := ih (item.key :: visited) tail_valid
      all_goals simp only [List.mem_cons,not_or] at *
      all_goals grind

theorem issued_check (records : List Entry) (entries : Lynx.Term) (visited : List Int)
    (unique : (records.map Entry.key).Nodup)
    (fresh : ∀ item ∈ records, item.key ∉ visited)
    (each : ∀ item ∈ records, 0 < item.amount ∧ item.status = .atom "issued" ∧
      (do let located ← Elixir.HoldLedger.Spec.«lookup/2» entries (.integer item.key)
          Elixir.HoldLedger.Spec.«issued_local?/2» located (.integer item.amount)) = Except.ok Lynx.Term.true) :
    Elixir.HoldLedger.Spec.«issued_valid?/3» (entriesTerm records) entries (CompositeEntries.keysTerm visited) = Except.ok Lynx.Term.true := by
  induction records generalizing visited with
  | nil => rfl
  | cons item rest ih =>
      obtain ⟨absent,tail_unique⟩ := List.nodup_cons.mp unique
      obtain ⟨positive,status,local_ok⟩ := each item (by simp)
      have not_seen := fresh item (by simp)
      have tail_fresh : ∀ entry ∈ rest, entry.key ∉ item.key :: visited := by
        intro entry member
        have different : entry.key ≠ item.key := by intro equal; exact absent (List.mem_map.mpr ⟨entry,member,equal⟩)
        simp [different,fresh entry (by simp [member])]
      have tail := ih (item.key :: visited) tail_unique tail_fresh (by intro entry member; exact each entry (by simp [member]))
      change Elixir.HoldLedger.Spec.«issued_valid?/3» (entriesTerm rest) entries (.cons (.integer item.key) (CompositeEntries.keysTerm visited)) = _ at tail
      simp only [bind,Except.bind] at local_ok
      cases item with
      | mk key amount state =>
        simp only at status
        subst state
        simp [entriesTerm,Elixir.HoldLedger.Spec.«issued_valid?/3»,CompositeEntries.seen,not_seen,
          positive,local_ok,tail,Erlang.erlang.«is_integer/1»,Erlang.erlang.«>/2»,Int.compare_eq_gt,Ordering.isGT_iff_eq_gt,
          Lynx.Except.andAlso,bind,Except.bind]

theorem remote_check (records : List Entry) (issued : Lynx.Term) (visited : List Int)
    (unique : (records.map Entry.key).Nodup)
    (fresh : ∀ item ∈ records, item.key ∉ visited)
    (each : ∀ item ∈ records, 0 < item.amount ∧
      (item.status = .atom "approved" ∨ item.status = .atom "declined" ∨ item.status = .atom "voided") ∧
      Elixir.HoldLedger.Spec.«lookup/2» issued (.integer item.key) =
        Except.ok (.tuple #[.atom "ok",.tuple #[.integer item.key,.integer item.amount,.atom "issued"]])) :
    Elixir.HoldLedger.Spec.«remote_valid?/3» (entriesTerm records) issued (CompositeEntries.keysTerm visited) = Except.ok Lynx.Term.true := by
  induction records generalizing visited with
  | nil => rfl
  | cons item rest ih =>
      obtain ⟨absent,tail_unique⟩ := List.nodup_cons.mp unique
      obtain ⟨positive,status,located⟩ := each item (by simp)
      have not_seen := fresh item (by simp)
      have tail_fresh : ∀ entry ∈ rest, entry.key ∉ item.key :: visited := by
        intro entry member
        have different : entry.key ≠ item.key := by intro equal; exact absent (List.mem_map.mpr ⟨entry,member,equal⟩)
        simp [different,fresh entry (by simp [member])]
      have tail := ih (item.key :: visited) tail_unique tail_fresh (by intro entry member; exact each entry (by simp [member]))
      have recursive : Elixir.HoldLedger.Spec.«remote_valid?/3» (entriesTerm rest) issued (.cons (.integer item.key) (CompositeEntries.keysTerm visited)) = Except.ok Lynx.Term.true := tail
      rcases status with approved | declined | voided
      all_goals simp [*,entriesTerm,Elixir.HoldLedger.Spec.«remote_valid?/3»,CompositeEntries.seen,
        Erlang.erlang.«is_integer/1»,Erlang.erlang.«>/2»,Erlang.erlang.«=:=/2»,
        Int.compare_eq_gt,Ordering.isGT_iff_eq_gt,Lynx.Except.andAlso]

theorem approved_holds (key amount local_amount : Int) (status : Lynx.Term)
    (valid : Elixir.HoldLedger.Spec.«entry_agrees?/5» (.integer key) (.integer local_amount) status
      (.tuple #[.atom "ok",.tuple #[.integer key,.integer amount,.atom "issued"]])
      (.tuple #[.atom "ok",.tuple #[.integer key,.integer amount,.atom "approved"]]) = Except.ok Lynx.Term.true) :
    local_amount = amount ∧ HoldLedgerProof.held status = true := by
  by_cases amount_same : amount = local_amount
  all_goals by_cases sent : status = .atom "sent"
  all_goals by_cases unknown : status = .atom "unknown"
  all_goals by_cases authorized : status = .atom "authorized"
  all_goals by_cases voiding : status = .atom "voiding"
  all_goals simp_all [Elixir.HoldLedger.Spec.«entry_agrees?/5»,Erlang.erlang.«=:=/2»,Erlang.erlang.«and/2»,
    Lynx.Except.andAlso,HoldLedgerProof.held]

@[expose] noncomputable def livePairs : List Exposure.Entry → List (Int × Int)
  | [] => []
  | entry :: rest => by
      classical
      exact if entry.status = .atom "approved" then (entry.key,entry.amount) :: livePairs rest else livePairs rest

theorem live_origin (records : List Exposure.Entry) (pair : Int × Int)
    (member : pair ∈ livePairs records) :
    ∃ entry ∈ records, pair = (entry.key,entry.amount) ∧ entry.status = .atom "approved" := by
  induction records with
  | nil => simp [livePairs] at member
  | cons entry rest ih =>
      by_cases approved : entry.status = .atom "approved"
      · simp only [livePairs,ite_eq_left approved,List.mem_cons] at member
        rcases member with equal | tail
        · exact ⟨entry,by simp,equal,approved⟩
        · obtain ⟨selected,member,equal,status⟩ := ih tail
          exact ⟨selected,by simp [member],equal,status⟩
      · obtain ⟨selected,member,equal,status⟩ := ih (by simpa [livePairs,approved] using member)
        exact ⟨selected,by simp [member],equal,status⟩

theorem live_distinct (records : List Exposure.Entry) (distinct : (records.map Exposure.Entry.key).Nodup) :
    (livePairs records).Nodup := by
  induction records with
  | nil => simp [livePairs]
  | cons entry rest ih =>
      obtain ⟨absent,tail⟩ := List.nodup_cons.mp distinct
      simp only [livePairs]
      split
      · apply List.nodup_cons.mpr
        refine ⟨?_,ih tail⟩
        intro member
        obtain ⟨selected,member,equal,_⟩ := live_origin rest (entry.key,entry.amount) member
        apply absent
        exact List.mem_map.mpr ⟨selected,member,(congrArg Prod.fst equal).symm⟩
      · exact ih tail

end HoldLedgerProof.ExposureFacts
