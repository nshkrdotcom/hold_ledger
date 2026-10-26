module
public import HoldLedgerProof.ExposureUpdates
import Lean

public section
set_option maxHeartbeats 4000000
namespace HoldLedgerProof.ExposureValidity
open HoldLedgerProof.Exposure HoldLedgerProof.ExposureCells

theorem coupled (entries issued records : List Entry)
    (proper : Elixir.HoldLedger.Spec.«proper_entries?/1» (entriesTerm entries) = Except.ok Lynx.Term.true)
    (issued_valid : Elixir.HoldLedger.Spec.«issued_valid?/3» (entriesTerm issued) (entriesTerm entries) .nil = Except.ok Lynx.Term.true)
    (remote_valid : Elixir.HoldLedger.Spec.«remote_valid?/3» (entriesTerm records) (entriesTerm issued) .nil = Except.ok Lynx.Term.true)
    (agreement : Elixir.HoldLedger.Spec.«local_remote_agree?/3» (entriesTerm entries) (entriesTerm issued) (entriesTerm records) = Except.ok Lynx.Term.true) :
    Coupled entries issued records := by
  intro key
  cases local_lookup : lookup entries key with
  | none =>
      have issued_absent : lookup issued key = none := by
        cases found : lookup issued key with
        | none => rfl
        | some intent =>
            have member := lookup_member found
            have intent_key := lookup_key found
            obtain ⟨_,_,status,located⟩ := ExposureFacts.issued_member issued (entriesTerm entries) .nil proper issued_valid intent member
            rw [intent_key,lookup_bridge,local_lookup] at located
            simp [observed] at located
      have remote_absent : lookup records key = none := by
        cases found : lookup records key with
        | none => rfl
        | some record =>
            have member := lookup_member found
            have record_key := lookup_key found
            have issued_record := (ExposureFacts.remote_member records issued .nil remote_valid record member).2
            rw [record_key,lookup_bridge,issued_absent] at issued_record
            simp [observed] at issued_record
      simp [Cell,issued_absent,remote_absent]
  | some entry =>
      have member := lookup_member local_lookup
      have entry_key := lookup_key local_lookup
      have valid := (ExposureFacts.local_agree entries (entriesTerm issued) (entriesTerm records)).mp agreement entry member
      rw [lookup_bridge,lookup_bridge] at valid
      simp only [bind,Except.bind] at valid
      rw [entry_key] at valid
      apply (cell_local entry (lookup issued key) (lookup records key) ?_ ?_).mpr
      · simpa [entry_key] using valid
      · intro intent found
        exact (lookup_key found).trans entry_key.symm
      · intro record found
        exact (lookup_key found).trans entry_key.symm

theorem cell_issued (entry intent : Entry) (remote : Option Entry)
    (cell : Cell (some entry) (some intent) remote) :
    intent.amount = entry.amount ∧ intent.status = .atom "issued" ∧
      (entry.status = .atom "sent" ∨ entry.status = .atom "unknown" ∨ entry.status = .atom "authorized" ∨
        entry.status = .atom "voiding" ∨ entry.status = .atom "declined" ∨ entry.status = .atom "voided") := by
  cases remote <;> simp only [Cell] at cell <;> grind

theorem cell_remote (entry intent record : Entry)
    (cell : Cell (some entry) (some intent) (some record)) :
    record.amount = entry.amount ∧ intent.amount = record.amount ∧ intent.status = .atom "issued" ∧
      (record.status = .atom "approved" ∨ record.status = .atom "declined" ∨ record.status = .atom "voided") := by
  simp only [Cell] at cell
  grind

theorem reconstruct (entries issued records : List Entry)
    (proper : Elixir.HoldLedger.Spec.«proper_entries?/1» (entriesTerm entries) = Except.ok Lynx.Term.true)
    (entries_unique : (entries.map Entry.key).Nodup)
    (issued_unique : (issued.map Entry.key).Nodup) (remote_unique : (records.map Entry.key).Nodup)
    (coupling : Coupled entries issued records) :
    Elixir.HoldLedger.Spec.«issued_valid?/3» (entriesTerm issued) (entriesTerm entries) .nil = Except.ok Lynx.Term.true ∧
    Elixir.HoldLedger.Spec.«remote_valid?/3» (entriesTerm records) (entriesTerm issued) .nil = Except.ok Lynx.Term.true ∧
    Elixir.HoldLedger.Spec.«local_remote_agree?/3» (entriesTerm entries) (entriesTerm issued) (entriesTerm records) = Except.ok Lynx.Term.true := by
  have issued_check : Elixir.HoldLedger.Spec.«issued_valid?/3» (entriesTerm issued) (entriesTerm entries) .nil = Except.ok Lynx.Term.true := by
    apply ExposureFacts.issued_check issued (entriesTerm entries) [] issued_unique (by simp)
    intro intent member
    have found := lookup_of_member issued_unique member
    have cell := coupling intent.key
    rw [found] at cell
    cases local_lookup : lookup entries intent.key with
    | none => simp [local_lookup,Cell] at cell
    | some entry =>
        rw [local_lookup] at cell
        obtain ⟨amount,status,allowed⟩ := cell_issued entry intent _ cell
        have positive := Exposure.encoded_positive proper entry (lookup_member local_lookup)
        refine ⟨by omega,status,?_⟩
        rw [lookup_bridge,local_lookup]
        have key := lookup_key local_lookup
        rcases allowed with sent | unknown | authorized | voiding | declined | voided
        all_goals simp [*,observed,Elixir.HoldLedger.Spec.«issued_local?/2»,Erlang.erlang.«=:=/2»]
  have remote_check : Elixir.HoldLedger.Spec.«remote_valid?/3» (entriesTerm records) (entriesTerm issued) .nil = Except.ok Lynx.Term.true := by
    apply ExposureFacts.remote_check records (entriesTerm issued) [] remote_unique (by simp)
    intro record member
    have found := lookup_of_member remote_unique member
    have cell := coupling record.key
    rw [found] at cell
    cases local_lookup : lookup entries record.key with
    | none => simp [local_lookup,Cell] at cell
    | some entry =>
        rw [local_lookup] at cell
        cases intent_lookup : lookup issued record.key with
        | none => simp [intent_lookup,Cell] at cell
        | some intent =>
            rw [intent_lookup] at cell
            obtain ⟨amount,intent_amount,status,allowed⟩ := cell_remote entry intent record cell
            have positive := Exposure.encoded_positive proper entry (lookup_member local_lookup)
            refine ⟨by omega,allowed,?_⟩
            rw [lookup_bridge,intent_lookup]
            have key := lookup_key intent_lookup
            simp [observed,key,intent_amount,status]
  refine ⟨issued_check,remote_check,?_⟩
  apply (ExposureFacts.local_agree entries (entriesTerm issued) (entriesTerm records)).mpr
  intro entry member
  rw [lookup_bridge,lookup_bridge]
  simp only [bind,Except.bind]
  have cell := coupling entry.key
  have found := lookup_of_member entries_unique member
  rw [found] at cell
  exact (cell_local entry _ _ (by intro intent located; exact lookup_key located)
    (by intro record located; exact lookup_key located)).mp cell

theorem view (ledger obligations : Lynx.Term) (entries issued records : List Entry)
    (ledger_valid : Elixir.HoldLedger.Spec.«valid?/1» ledger = Except.ok Lynx.Term.true)
    (located : Erlang.erlang.«element/2» (.integer 5) ledger = Except.ok (entriesTerm entries)) :
    Elixir.HoldLedger.Spec.«exposure_valid?/1»
      (.tuple #[.tuple #[ledger,obligations],.tuple #[entriesTerm issued,entriesTerm records]]) = Except.ok Lynx.Term.true ↔
      Elixir.HoldLedger.Spec.«composite_valid?/1» (.tuple #[ledger,obligations]) = Except.ok Lynx.Term.true ∧
      (issued.map Entry.key).Nodup ∧ (records.map Entry.key).Nodup ∧ Coupled entries issued records := by
  obtain ⟨al,hl,ua,uh,actual,shape,proper,distinct,_,_,_,_,_,_,_,_⟩ := valid_view_1 ledger ledger_valid
  have equal : actual = entriesTerm entries := by subst ledger; simpa [Erlang.erlang.«element/2»] using located
  rw [equal] at proper distinct
  have entries_unique : (entries.map Entry.key).Nodup := by
    have listed : Erlang.erlang.«is_list/1» (entriesTerm entries) = Except.ok Lynx.Term.true := by cases entries <;> rfl
    have seen : Elixir.HoldLedger.Spec.«unique_keys_seen?/2» (entriesTerm entries) .nil = Except.ok Lynx.Term.true := by
      simpa [Elixir.HoldLedger.Spec.«unique_keys?/1»,listed,Lynx.Except.tryWith,bind,Except.bind] using distinct
    rw [← ExposureFacts.physical_encode entries] at seen
    have unique := ((CompositeEntries.unique (ExposureFacts.physical entries) []).mp seen).1
    simpa [ExposureFacts.physical,List.map_map,Function.comp_def] using unique
  constructor
  · intro valid
    have parts : Elixir.HoldLedger.Spec.«composite_valid?/1» (.tuple #[ledger,obligations]) = Except.ok Lynx.Term.true ∧
        Elixir.HoldLedger.Spec.«issued_valid?/3» (entriesTerm issued) (entriesTerm entries) .nil = Except.ok Lynx.Term.true ∧
        Elixir.HoldLedger.Spec.«remote_valid?/3» (entriesTerm records) (entriesTerm issued) .nil = Except.ok Lynx.Term.true ∧
        Elixir.HoldLedger.Spec.«local_remote_agree?/3» (entriesTerm entries) (entriesTerm issued) (entriesTerm records) = Except.ok Lynx.Term.true := by
      simp only [Elixir.HoldLedger.Spec.«exposure_valid?/1»,located,bind,Except.bind] at valid
      repeat' (split at * <;> try simp_all [Lynx.Term.true])
    obtain ⟨composite,issued_valid,remote_valid,agreement⟩ := parts
    exact ⟨composite,(ExposureFacts.issued_unique issued (entriesTerm entries) [] issued_valid).1,
      (ExposureFacts.remote_unique records (entriesTerm issued) [] remote_valid).1,
      coupled entries issued records proper issued_valid remote_valid agreement⟩
  · rintro ⟨composite,issued_unique,remote_unique,relation⟩
    obtain ⟨issued_check,remote_check,agreement⟩ := reconstruct entries issued records proper entries_unique issued_unique remote_unique relation
    simp [Elixir.HoldLedger.Spec.«exposure_valid?/1»,composite,located,issued_check,remote_check,agreement]

end HoldLedgerProof.ExposureValidity
