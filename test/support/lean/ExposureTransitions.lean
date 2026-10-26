module
public import Elixir.HoldLedger.Exposure
public import HoldLedgerProof.ExposureValidity
import Lean

public section
set_option maxHeartbeats 4000000
namespace HoldLedgerProof.ExposureTransitions
open HoldLedgerProof.Exposure HoldLedgerProof.ExposureCells HoldLedgerProof.ExposureUpdates

@[expose] def state (ledger obligations : Lynx.Term) (issued records : List Entry) : Lynx.Term :=
  .tuple #[.tuple #[ledger,obligations],.tuple #[entriesTerm issued,entriesTerm records]]

theorem composite_projection (ledger obligations event next result effects : Lynx.Term)
    (valid : Elixir.HoldLedger.Spec.«composite_valid?/1» (.tuple #[ledger,obligations]) = Except.ok Lynx.Term.true)
    (applied : Elixir.HoldLedger.Ledger.«step/2» ledger event = Except.ok (.tuple #[next,result,effects])) :
    ∃ remaining,
      Elixir.HoldLedger.Composite.«step/2» (.tuple #[ledger,obligations]) event =
        Except.ok (.tuple #[.tuple #[next,remaining],result,effects]) ∧
      Elixir.HoldLedger.Spec.«composite_valid?/1» (.tuple #[next,remaining]) = Except.ok Lynx.Term.true := by
  obtain ⟨actual,res,fx,step,preserved⟩ := CompositeSafety.composite_preserves _ event valid
  have expanded := step
  simp only [Elixir.HoldLedger.Composite.«step/2»,applied,bind,Except.bind] at expanded
  repeat' (split at expanded <;> try simp_all [Lynx.Term.true])
  all_goals repeat' split_conjunction
  all_goals subst_vars
  all_goals exact ⟨_,rfl,preserved⟩

theorem local_glue (ledger obligations event next result effects : Lynx.Term)
    (entries issued records next_issued next_records : List Entry)
    (valid : Elixir.HoldLedger.Spec.«composite_valid?/1» (.tuple #[ledger,obligations]) = Except.ok Lynx.Term.true)
    (accepted : Elixir.HoldLedger.Exposure.«local?/1» event = Except.ok Lynx.Term.true)
    (applied : Elixir.HoldLedger.Ledger.«step/2» ledger event = Except.ok (.tuple #[next,result,effects]))
    (located : Erlang.erlang.«element/2» (.integer 5) next = Except.ok (entriesTerm entries))
    (issued_effects : Elixir.HoldLedger.Exposure.«issue_all/2» (.tuple #[entriesTerm issued,entriesTerm records]) effects =
      Except.ok (.tuple #[entriesTerm next_issued,entriesTerm next_records]))
    (unique_issued : (next_issued.map Entry.key).Nodup) (unique_records : (next_records.map Entry.key).Nodup)
    (coupling : Coupled entries next_issued next_records) :
    ∃ next_state, Elixir.HoldLedger.Exposure.«step/2» (state ledger obligations issued records) (.tuple #[.atom "local",event]) =
      Except.ok next_state ∧ Elixir.HoldLedger.Spec.«exposure_valid?/1» next_state = Except.ok Lynx.Term.true := by
  obtain ⟨remaining,step,preserved⟩ := composite_projection ledger obligations event next result effects valid applied
  obtain ⟨_,_,_,shape,next_valid,_,_,_⟩ := CompositeInvariant.components _ preserved
  simp only [Lynx.Term.tuple.injEq,Array.mk.injEq,List.cons.injEq,and_true] at shape
  obtain ⟨rfl,rfl⟩ := shape
  refine ⟨state next remaining next_issued next_records,?_,?_⟩
  · simp [state,Elixir.HoldLedger.Exposure.«step/2»,accepted,step,issued_effects]
  · exact (ExposureValidity.view next remaining entries next_issued next_records next_valid located).mpr
      ⟨preserved,unique_issued,unique_records,coupling⟩

@[expose] def Safe (initial event : Lynx.Term) : Prop :=
  ∃ next, Elixir.HoldLedger.Exposure.«step/2» initial event = Except.ok next ∧
    Elixir.HoldLedger.Spec.«exposure_valid?/1» next = Except.ok Lynx.Term.true

theorem local_passive (al hl ua uh : Int) (obligations event result : Lynx.Term) (entries issued records : List Entry)
    (valid : Elixir.HoldLedger.Spec.«composite_valid?/1» (.tuple #[.tuple #[.integer al,.integer hl,.integer ua,.integer uh,entriesTerm entries],obligations]) = Except.ok Lynx.Term.true)
    (accepted : Elixir.HoldLedger.Exposure.«local?/1» event = Except.ok Lynx.Term.true)
    (applied : Elixir.HoldLedger.Ledger.«step/2» (.tuple #[.integer al,.integer hl,.integer ua,.integer uh,entriesTerm entries]) event =
      Except.ok (.tuple #[.tuple #[.integer al,.integer hl,.integer ua,.integer uh,entriesTerm entries],result,.nil]))
    (unique_issued : (issued.map Entry.key).Nodup) (unique_records : (records.map Entry.key).Nodup)
    (coupling : Coupled entries issued records) :
    Safe (state (.tuple #[.integer al,.integer hl,.integer ua,.integer uh,entriesTerm entries]) obligations issued records) (.tuple #[.atom "local",event]) := by
  exact local_glue _ obligations event _ result .nil entries issued records issued records valid accepted applied rfl rfl unique_issued unique_records coupling

theorem dispatch_cell (entry : Entry) (intent remote : Option Entry)
    (reserved : entry.status = .atom "reserved") (cell : Cell (some entry) intent remote) : intent = none ∧ remote = none := by
  cases intent <;> cases remote <;> simp_all [Cell]

theorem local_dispatch (al hl ua uh key : Int) (obligations : Lynx.Term) (entries issued records : List Entry)
    (valid : Elixir.HoldLedger.Spec.«composite_valid?/1» (.tuple #[.tuple #[.integer al,.integer hl,.integer ua,.integer uh,entriesTerm entries],obligations]) = Except.ok Lynx.Term.true)
    (proper : Elixir.HoldLedger.Spec.«proper_entries?/1» (entriesTerm entries) = Except.ok Lynx.Term.true)
    (unique_issued : (issued.map Entry.key).Nodup) (unique_records : (records.map Entry.key).Nodup)
    (coupling : Coupled entries issued records) :
    Safe (state (.tuple #[.integer al,.integer hl,.integer ua,.integer uh,entriesTerm entries]) obligations issued records)
      (.tuple #[.atom "local",.tuple #[.atom "dispatch",.integer key]]) := by
  have accepted : Elixir.HoldLedger.Exposure.«local?/1» (.tuple #[.atom "dispatch",.integer key]) = Except.ok Lynx.Term.true := by simp [Elixir.HoldLedger.Exposure.«local?/1»]
  cases found : lookup entries key with
  | none =>
      apply local_passive al hl ua uh obligations _ (.atom "not_found") entries issued records valid accepted _ unique_issued unique_records coupling
      simp [Elixir.HoldLedger.Ledger.«step/2»,Elixir.HoldLedger.Ledger.«dispatch/2»,ledger_lookup,found,observed]
  | some entry =>
      by_cases reserved : entry.status = .atom "reserved"
      · have key_equal := lookup_key found
        have positive := Exposure.encoded_positive proper entry (lookup_member found)
        obtain ⟨issued_absent,remote_absent⟩ := dispatch_cell entry _ _ reserved (by simpa [found] using coupling key)
        have not_issued := (lookup_none issued key).mp issued_absent
        have next_coupling : Coupled (update entries key (.atom "sent")) (⟨key,entry.amount,.atom "issued"⟩ :: issued) records := by
          apply replace_cell entries _ issued _ records records key coupling
          · intro query different
            simp [update_lookup,lookup,Ne.symm different]
          · simp [update_lookup,lookup,found,remote_absent,Cell]
        apply local_glue _ obligations (.tuple #[.atom "dispatch",.integer key])
          (.tuple #[.integer al,.integer hl,.integer ua,.integer uh,entriesTerm (update entries key (.atom "sent"))])
          (.atom "dispatched") (.cons (.tuple #[.atom "authorize",.integer key,.integer entry.amount]) .nil)
          (update entries key (.atom "sent")) issued records (⟨key,entry.amount,.atom "issued"⟩ :: issued) records valid accepted
          _ rfl _ (by simpa using And.intro not_issued unique_issued) unique_records next_coupling
        · simp [Elixir.HoldLedger.Ledger.«step/2»,Elixir.HoldLedger.Ledger.«dispatch/2»,ledger_lookup,found,observed,reserved,
            key_equal,update_bridge]
        · simp [Elixir.HoldLedger.Exposure.«issue_all/2»,Elixir.HoldLedger.Environment.«issue/2»,environment_lookup,issued_absent,raw,
            entriesTerm,positive,Erlang.erlang.«is_integer/1»,Erlang.erlang.«>/2»,Int.compare_eq_gt,Ordering.isGT_iff_eq_gt]
      · apply local_passive al hl ua uh obligations _ (.atom "stale") entries issued records valid accepted _ unique_issued unique_records coupling
        simp [Elixir.HoldLedger.Ledger.«step/2»,Elixir.HoldLedger.Ledger.«dispatch/2»,ledger_lookup,found,observed,reserved]

theorem local_request (al hl ua uh key amount : Int) (obligations : Lynx.Term) (entries issued records : List Entry)
    (valid : Elixir.HoldLedger.Spec.«composite_valid?/1» (.tuple #[.tuple #[.integer al,.integer hl,.integer ua,.integer uh,entriesTerm entries],obligations]) = Except.ok Lynx.Term.true)
    (unique_issued : (issued.map Entry.key).Nodup) (unique_records : (records.map Entry.key).Nodup)
    (coupling : Coupled entries issued records) :
    Safe (state (.tuple #[.integer al,.integer hl,.integer ua,.integer uh,entriesTerm entries]) obligations issued records)
      (.tuple #[.atom "local",.tuple #[.atom "request",.integer key,.integer amount]]) := by
  have accepted : Elixir.HoldLedger.Exposure.«local?/1» (.tuple #[.atom "request",.integer key,.integer amount]) = Except.ok Lynx.Term.true := rfl
  have passive (result : Lynx.Term)
      (step : Elixir.HoldLedger.Ledger.«step/2» (.tuple #[.integer al,.integer hl,.integer ua,.integer uh,entriesTerm entries])
        (.tuple #[.atom "request",.integer key,.integer amount]) = Except.ok (.tuple #[.tuple #[.integer al,.integer hl,.integer ua,.integer uh,entriesTerm entries],result,.nil])) :=
    local_passive al hl ua uh obligations _ result entries issued records valid accepted step unique_issued unique_records coupling
  by_cases positive : 0 < amount
  · cases found : lookup entries key with
    | some entry =>
        by_cases equal : entry.amount = amount
        · apply passive (.atom "duplicate")
          simp [Elixir.HoldLedger.Ledger.«step/2»,Elixir.HoldLedger.Ledger.«request/3»,ledger_lookup,found,observed,equal,
            positive,Erlang.erlang.«is_integer/1»,Erlang.erlang.«=:=/2»,Erlang.erlang.«>/2»,Int.compare_eq_gt,Ordering.isGT_iff_eq_gt]
        · apply passive (.atom "conflict")
          simp [Elixir.HoldLedger.Ledger.«step/2»,Elixir.HoldLedger.Ledger.«request/3»,ledger_lookup,found,observed,equal,
            positive,Erlang.erlang.«is_integer/1»,Erlang.erlang.«=:=/2»,Erlang.erlang.«>/2»,Int.compare_eq_gt,Ordering.isGT_iff_eq_gt]
    | none =>
        by_cases holds : hl ≤ uh
        · apply passive (.atom "insufficient_holds")
          simp [Elixir.HoldLedger.Ledger.«step/2»,Elixir.HoldLedger.Ledger.«request/3»,ledger_lookup,found,observed,
            positive,holds,Erlang.erlang.«is_integer/1»,Erlang.erlang.«>/2»,Erlang.erlang.«>=/2»,Int.isGE_compare,Int.compare_eq_gt,Ordering.isGT_iff_eq_gt]
        · by_cases exceeded : al - ua < amount
          · apply passive (.atom "insufficient_amount")
            simp [Elixir.HoldLedger.Ledger.«step/2»,Elixir.HoldLedger.Ledger.«request/3»,ledger_lookup,found,observed,
              positive,holds,exceeded,Erlang.erlang.«is_integer/1»,Erlang.erlang.«>/2»,Erlang.erlang.«>=/2»,Int.isGE_compare,Int.compare_eq_gt,Ordering.isGT_iff_eq_gt]
          · apply local_glue _ obligations (.tuple #[.atom "request",.integer key,.integer amount])
              (.tuple #[.integer al,.integer hl,.integer (ua+amount),.integer (uh+1),entriesTerm (⟨key,amount,.atom "reserved"⟩ :: entries)])
              (.atom "admitted") .nil (⟨key,amount,.atom "reserved"⟩ :: entries) issued records issued records valid accepted
              _ rfl rfl unique_issued unique_records (coupled_fresh entries issued records key amount coupling found)
            simp [Elixir.HoldLedger.Ledger.«step/2»,Elixir.HoldLedger.Ledger.«request/3»,ledger_lookup,found,observed,entriesTerm,
              positive,holds,exceeded,Erlang.erlang.«is_integer/1»,Erlang.erlang.«>/2»,Erlang.erlang.«>=/2»,Int.isGE_compare,Int.compare_eq_gt,Ordering.isGT_iff_eq_gt]
  · apply passive (.atom "malformed")
    simp [Elixir.HoldLedger.Ledger.«step/2»,Elixir.HoldLedger.Ledger.«request/3»,positive,
      Erlang.erlang.«is_integer/1»,Erlang.erlang.«>/2»,Int.compare_eq_gt,Ordering.isGT_iff_eq_gt]

theorem uncertain_cell (entry : Entry) (intent remote : Option Entry)
    (uncertain : entry.status = .atom "sent" ∨ entry.status = .atom "unknown")
    (cell : Cell (some entry) intent remote) :
    Cell (some {entry with status := .atom "sent"}) intent remote ∧
    Cell (some {entry with status := .atom "unknown"}) intent remote := by
  cases intent <;> cases remote <;> simp_all [Cell] <;> grind

theorem local_timeout (al hl ua uh key : Int) (obligations : Lynx.Term) (entries issued records : List Entry)
    (valid : Elixir.HoldLedger.Spec.«composite_valid?/1» (.tuple #[.tuple #[.integer al,.integer hl,.integer ua,.integer uh,entriesTerm entries],obligations]) = Except.ok Lynx.Term.true)
    (unique_issued : (issued.map Entry.key).Nodup) (unique_records : (records.map Entry.key).Nodup)
    (coupling : Coupled entries issued records) :
    Safe (state (.tuple #[.integer al,.integer hl,.integer ua,.integer uh,entriesTerm entries]) obligations issued records)
      (.tuple #[.atom "local",.tuple #[.atom "timeout",.integer key]]) := by
  have accepted : Elixir.HoldLedger.Exposure.«local?/1» (.tuple #[.atom "timeout",.integer key]) = Except.ok Lynx.Term.true := by
    simp [Elixir.HoldLedger.Exposure.«local?/1»]
  cases found : lookup entries key with
  | none =>
      apply local_passive al hl ua uh obligations _ (.atom "not_found") entries issued records valid accepted _ unique_issued unique_records coupling
      simp [Elixir.HoldLedger.Ledger.«step/2»,Elixir.HoldLedger.Ledger.«timeout/2»,ledger_lookup,found,observed]
  | some entry =>
      by_cases sent : entry.status = .atom "sent"
      · have key_equal := lookup_key found
        have selected := (uncertain_cell entry _ _ (Or.inl sent) (by simpa [found] using coupling key)).2
        have next_coupling := coupled_update entries issued records key entry (.atom "unknown") coupling found selected
        apply local_glue _ obligations (.tuple #[.atom "timeout",.integer key])
          (.tuple #[.integer al,.integer hl,.integer ua,.integer uh,entriesTerm (update entries key (.atom "unknown"))])
          (.atom "marked_unknown") .nil (update entries key (.atom "unknown")) issued records issued records valid accepted
          _ rfl rfl unique_issued unique_records next_coupling
        simp [Elixir.HoldLedger.Ledger.«step/2»,Elixir.HoldLedger.Ledger.«timeout/2»,ledger_lookup,found,observed,sent,
          key_equal,update_bridge]
      · apply local_passive al hl ua uh obligations _ (.atom "stale") entries issued records valid accepted _ unique_issued unique_records coupling
        simp [Elixir.HoldLedger.Ledger.«step/2»,Elixir.HoldLedger.Ledger.«timeout/2»,ledger_lookup,found,observed,sent]

theorem local_retry (al hl ua uh key : Int) (obligations : Lynx.Term) (entries issued records : List Entry)
    (valid : Elixir.HoldLedger.Spec.«composite_valid?/1» (.tuple #[.tuple #[.integer al,.integer hl,.integer ua,.integer uh,entriesTerm entries],obligations]) = Except.ok Lynx.Term.true)
    (proper : Elixir.HoldLedger.Spec.«proper_entries?/1» (entriesTerm entries) = Except.ok Lynx.Term.true)
    (unique_issued : (issued.map Entry.key).Nodup) (unique_records : (records.map Entry.key).Nodup)
    (coupling : Coupled entries issued records) :
    Safe (state (.tuple #[.integer al,.integer hl,.integer ua,.integer uh,entriesTerm entries]) obligations issued records)
      (.tuple #[.atom "local",.tuple #[.atom "retry",.integer key]]) := by
  have accepted : Elixir.HoldLedger.Exposure.«local?/1» (.tuple #[.atom "retry",.integer key]) = Except.ok Lynx.Term.true := by
    simp [Elixir.HoldLedger.Exposure.«local?/1»]
  cases found : lookup entries key with
  | none =>
      apply local_passive al hl ua uh obligations _ (.atom "not_found") entries issued records valid accepted _ unique_issued unique_records coupling
      simp [Elixir.HoldLedger.Ledger.«step/2»,Elixir.HoldLedger.Ledger.«retry/2»,ledger_lookup,found,observed]
  | some entry =>
      by_cases unknown : entry.status = .atom "unknown"
      · have key_equal := lookup_key found
        have positive := Exposure.encoded_positive proper entry (lookup_member found)
        have old_cell : Cell (some entry) (lookup issued key) (lookup records key) := by simpa [found] using coupling key
        have selected := (uncertain_cell entry _ _ (Or.inr unknown) old_cell).1
        have next_coupling := coupled_update entries issued records key entry (.atom "sent") coupling found selected
        cases intent_lookup : lookup issued key with
        | none =>
            cases remote_lookup : lookup records key <;> simp_all [Cell]
        | some intent =>
            obtain ⟨intent_amount,intent_status,_⟩ := ExposureValidity.cell_issued entry intent _ (by simpa [intent_lookup] using old_cell)
            have intent_key := lookup_key intent_lookup
            apply local_glue _ obligations (.tuple #[.atom "retry",.integer key])
              (.tuple #[.integer al,.integer hl,.integer ua,.integer uh,entriesTerm (update entries key (.atom "sent"))])
              (.atom "retried") (.cons (.tuple #[.atom "authorize",.integer key,.integer entry.amount]) .nil)
              (update entries key (.atom "sent")) issued records issued records valid accepted
              _ rfl _ unique_issued unique_records next_coupling
            · simp [Elixir.HoldLedger.Ledger.«step/2»,Elixir.HoldLedger.Ledger.«retry/2»,ledger_lookup,found,observed,unknown,
                key_equal,update_bridge]
            · simp [Elixir.HoldLedger.Exposure.«issue_all/2»,Elixir.HoldLedger.Environment.«issue/2»,environment_lookup,intent_lookup,raw,
                intent_key,intent_amount,intent_status,positive,Erlang.erlang.«is_integer/1»,Erlang.erlang.«>/2»,Erlang.erlang.«=:=/2»,
                Int.compare_eq_gt,Ordering.isGT_iff_eq_gt,Erlang.erlang.«and/2»]
      · apply local_passive al hl ua uh obligations _ (.atom "stale") entries issued records valid accepted _ unique_issued unique_records coupling
        simp [Elixir.HoldLedger.Ledger.«step/2»,Elixir.HoldLedger.Ledger.«retry/2»,ledger_lookup,found,observed,unknown]

theorem void_cell (entry : Entry) (intent remote : Option Entry) (cell : Cell (some entry) intent remote) :
    (entry.status = .atom "reserved" → Cell (some {entry with status := .atom "voided"}) intent remote) ∧
    (entry.status = .atom "authorized" → Cell (some {entry with status := .atom "voiding"}) intent remote) := by
  cases intent <;> cases remote <;> simp_all [Cell] <;> grind

theorem local_void (al hl ua uh key : Int) (obligations : Lynx.Term) (entries issued records : List Entry)
    (valid : Elixir.HoldLedger.Spec.«composite_valid?/1» (.tuple #[.tuple #[.integer al,.integer hl,.integer ua,.integer uh,entriesTerm entries],obligations]) = Except.ok Lynx.Term.true)
    (unique_issued : (issued.map Entry.key).Nodup) (unique_records : (records.map Entry.key).Nodup)
    (coupling : Coupled entries issued records) :
    Safe (state (.tuple #[.integer al,.integer hl,.integer ua,.integer uh,entriesTerm entries]) obligations issued records)
      (.tuple #[.atom "local",.tuple #[.atom "void",.integer key]]) := by
  have accepted : Elixir.HoldLedger.Exposure.«local?/1» (.tuple #[.atom "void",.integer key]) = Except.ok Lynx.Term.true := by
    simp [Elixir.HoldLedger.Exposure.«local?/1»]
  cases found : lookup entries key with
  | none =>
      apply local_passive al hl ua uh obligations _ (.atom "not_found") entries issued records valid accepted _ unique_issued unique_records coupling
      simp [Elixir.HoldLedger.Ledger.«step/2»,Elixir.HoldLedger.Ledger.«void/2»,ledger_lookup,found,observed]
  | some entry =>
      have key_equal := lookup_key found
      have old_cell : Cell (some entry) (lookup issued key) (lookup records key) := by simpa [found] using coupling key
      by_cases reserved : entry.status = .atom "reserved"
      · have selected := (void_cell entry _ _ old_cell).1 reserved
        have next_coupling := coupled_update entries issued records key entry (.atom "voided") coupling found selected
        apply local_glue _ obligations (.tuple #[.atom "void",.integer key])
          (.tuple #[.integer al,.integer hl,.integer (ua-entry.amount),.integer (uh-1),entriesTerm (update entries key (.atom "voided"))])
          (.atom "voided") .nil (update entries key (.atom "voided")) issued records issued records valid accepted
          _ rfl rfl unique_issued unique_records next_coupling
        simp [Elixir.HoldLedger.Ledger.«step/2»,Elixir.HoldLedger.Ledger.«void/2»,ledger_lookup,found,observed,reserved,
          key_equal,update_bridge]
      · by_cases authorized : entry.status = .atom "authorized"
        · have selected := (void_cell entry _ _ old_cell).2 authorized
          have next_coupling := coupled_update entries issued records key entry (.atom "voiding") coupling found selected
          apply local_glue _ obligations (.tuple #[.atom "void",.integer key])
            (.tuple #[.integer al,.integer hl,.integer ua,.integer uh,entriesTerm (update entries key (.atom "voiding"))])
            (.atom "voiding") (.cons (.tuple #[.atom "void",.integer key]) .nil)
            (update entries key (.atom "voiding")) issued records issued records valid accepted
            _ rfl _ unique_issued unique_records next_coupling
          · simp [Elixir.HoldLedger.Ledger.«step/2»,Elixir.HoldLedger.Ledger.«void/2»,ledger_lookup,found,observed,authorized,
              key_equal,update_bridge]
          · simp [Elixir.HoldLedger.Exposure.«issue_all/2»,Elixir.HoldLedger.Environment.«issue/2»]
        · apply local_passive al hl ua uh obligations _ (.atom "stale") entries issued records valid accepted _ unique_issued unique_records coupling
          simp [Elixir.HoldLedger.Ledger.«step/2»,Elixir.HoldLedger.Ledger.«void/2»,ledger_lookup,found,observed,reserved,authorized]

theorem local_restart (al hl ua uh : Int) (obligations : Lynx.Term) (entries issued records : List Entry)
    (valid : Elixir.HoldLedger.Spec.«composite_valid?/1» (.tuple #[.tuple #[.integer al,.integer hl,.integer ua,.integer uh,entriesTerm entries],obligations]) = Except.ok Lynx.Term.true)
    (unique_issued : (issued.map Entry.key).Nodup) (unique_records : (records.map Entry.key).Nodup)
    (coupling : Coupled entries issued records) :
    Safe (state (.tuple #[.integer al,.integer hl,.integer ua,.integer uh,entriesTerm entries]) obligations issued records)
      (.tuple #[.atom "local",.atom "restart"]) := by
  apply local_glue _ obligations (.atom "restart")
    (.tuple #[.integer al,.integer hl,.integer ua,.integer uh,entriesTerm (restart entries)])
    (.atom "restarted") .nil (restart entries) issued records issued records valid rfl _ rfl rfl unique_issued unique_records
    (coupled_restart entries issued records coupling)
  simp [Elixir.HoldLedger.Ledger.«step/2»,Elixir.HoldLedger.Ledger.«restart/1»,restart_bridge]

theorem pair_valid (al hl ua uh : Int) (obligations : Lynx.Term) (entries issued records : List Entry)
    (valid : Elixir.HoldLedger.Spec.«composite_valid?/1» (.tuple #[.tuple #[.integer al,.integer hl,.integer ua,.integer uh,entriesTerm entries],obligations]) = Except.ok Lynx.Term.true)
    (unique_issued : (issued.map Entry.key).Nodup) (unique_records : (records.map Entry.key).Nodup)
    (coupling : Coupled entries issued records) :
    Elixir.HoldLedger.Spec.«exposure_valid?/1» (state (.tuple #[.integer al,.integer hl,.integer ua,.integer uh,entriesTerm entries]) obligations issued records) = Except.ok Lynx.Term.true := by
  obtain ⟨_,_,_,shape,ledger_valid,_,_,_⟩ := CompositeInvariant.components _ valid
  simp only [Lynx.Term.tuple.injEq,Array.mk.injEq,List.cons.injEq,and_true] at shape
  obtain ⟨rfl,rfl⟩ := shape
  exact (ExposureValidity.view _ obligations entries issued records ledger_valid rfl).mpr ⟨valid,unique_issued,unique_records,coupling⟩

theorem remote_authorize (al hl ua uh key : Int) (obligations decision : Lynx.Term) (entries issued records : List Entry)
    (valid : Elixir.HoldLedger.Spec.«composite_valid?/1» (.tuple #[.tuple #[.integer al,.integer hl,.integer ua,.integer uh,entriesTerm entries],obligations]) = Except.ok Lynx.Term.true)
    (unique_issued : (issued.map Entry.key).Nodup) (unique_records : (records.map Entry.key).Nodup)
    (coupling : Coupled entries issued records)
    (decision_allowed : decision = .atom "approved" ∨ decision = .atom "declined") :
    Safe (state (.tuple #[.integer al,.integer hl,.integer ua,.integer uh,entriesTerm entries]) obligations issued records)
      (.tuple #[.atom "authorize",.integer key,decision]) := by
  have original := pair_valid al hl ua uh obligations entries issued records valid unique_issued unique_records coupling
  have cell := coupling key
  cases remote_lookup : lookup records key with
  | some record =>
      have record_key := lookup_key remote_lookup
      cases local_lookup : lookup entries key with
      | none => simp [local_lookup,remote_lookup,Cell] at cell
      | some entry =>
          cases intent_lookup : lookup issued key with
          | none => simp [local_lookup,intent_lookup,remote_lookup,Cell] at cell
          | some intent =>
              have detail := ExposureValidity.cell_remote entry intent record (by simpa [local_lookup,intent_lookup,remote_lookup] using cell)
              rcases detail.2.2.2 with approved | declined | voided
              all_goals refine ⟨_,?_,original⟩
              all_goals rcases decision_allowed with rfl | rfl
              all_goals simp [*,state,Elixir.HoldLedger.Exposure.«step/2»,Elixir.HoldLedger.Environment.«deliver/2»,
                environment_lookup,raw,Erlang.erlang.«is_integer/1»,
                Erlang.erlang.«=:=/2»]
  | none =>
      cases intent_lookup : lookup issued key with
      | none =>
          refine ⟨_,?_,original⟩
          rcases decision_allowed with rfl | rfl
          all_goals simp [state,Elixir.HoldLedger.Exposure.«step/2»,Elixir.HoldLedger.Environment.«deliver/2»,
            environment_lookup,remote_lookup,intent_lookup,raw,Erlang.erlang.«is_integer/1»]
      | some intent =>
          have intent_key := lookup_key intent_lookup
          have fresh := (lookup_none records key).mp remote_lookup
          have next_coupling : Coupled entries issued (⟨key,intent.amount,decision⟩ :: records) := by
            apply replace_cell entries entries issued issued records _ key coupling
            · intro query different
              simp [lookup,Ne.symm different]
            · cases local_lookup : lookup entries key
              all_goals simp_all [Cell,lookup]
              all_goals grind
          have next_unique : ((⟨key,intent.amount,decision⟩ :: records).map Entry.key).Nodup := by simpa using And.intro fresh unique_records
          refine ⟨state _ obligations issued (⟨key,intent.amount,decision⟩ :: records),?_,
            pair_valid al hl ua uh obligations entries issued _ valid unique_issued next_unique next_coupling⟩
          have intent_status : intent.status = .atom "issued" := by
            cases local_lookup : lookup entries key
            all_goals simp_all [Cell]
          rcases decision_allowed with rfl | rfl
          all_goals simp [state,Elixir.HoldLedger.Exposure.«step/2»,Elixir.HoldLedger.Environment.«deliver/2»,
            environment_lookup,remote_lookup,intent_lookup,raw,intent_key,intent_status,entriesTerm,Erlang.erlang.«is_integer/1»,
            Erlang.erlang.«=:=/2»]

theorem remote_void (al hl ua uh key : Int) (items : List Outbox.Obligation) (entries issued records : List Entry)
    (valid : Elixir.HoldLedger.Spec.«composite_valid?/1» (.tuple #[.tuple #[.integer al,.integer hl,.integer ua,.integer uh,entriesTerm entries],Outbox.encode items]) = Except.ok Lynx.Term.true)
    (unique_issued : (issued.map Entry.key).Nodup) (unique_records : (records.map Entry.key).Nodup)
    (coupling : Coupled entries issued records) :
    Safe (state (.tuple #[.integer al,.integer hl,.integer ua,.integer uh,entriesTerm entries]) (Outbox.encode items) issued records)
      (.tuple #[.atom "void",.integer key]) := by
  have original := pair_valid al hl ua uh (Outbox.encode items) entries issued records valid unique_issued unique_records coupling
  rcases Outbox.fetch_shape items key with absent | ⟨count,outcome,found,member⟩
  · refine ⟨_,?_,original⟩
    simp [state,Elixir.HoldLedger.Exposure.«step/2»,absent]
  · obtain ⟨_,_,_,shape,ledger_valid,_,_,_⟩ := CompositeInvariant.components _ valid
    simp only [Lynx.Term.tuple.injEq,Array.mk.injEq,List.cons.injEq,and_true] at shape
    obtain ⟨rfl,rfl⟩ := shape
    have ⟨_,physical⟩ := (CompositeInvariant.full_view _ items (entriesTerm entries) ledger_valid rfl).mp valid
    obtain ⟨amount,located⟩ := (physical key).mpr member
    rw [lookup_bridge] at located
    cases local_lookup : lookup entries key with
    | none => simp [local_lookup,observed] at located
    | some entry =>
        simp [local_lookup,observed] at located
        have cell := coupling key
        cases intent_lookup : lookup issued key with
        | none => cases remote_lookup : lookup records key <;> simp_all [Cell]
        | some intent =>
          cases remote_lookup : lookup records key with
          | none => simp_all [Cell]
          | some record =>
            have detail := ExposureValidity.cell_remote entry intent record (by simpa [local_lookup,intent_lookup,remote_lookup] using coupling key)
            have intent_key := lookup_key intent_lookup
            have record_key := lookup_key remote_lookup
            have next_coupling : Coupled entries issued (put records key intent.amount (.atom "voided")) := by
              apply replace_cell entries entries issued issued records _ key coupling
              · intro query different
                simp [put_lookup,Ne.symm different]
              · simp [local_lookup,intent_lookup,remote_lookup,put_lookup,Cell] at *
                grind
            refine ⟨state _ (Outbox.encode items) issued (put records key intent.amount (.atom "voided")),?_,
              pair_valid al hl ua uh (Outbox.encode items) entries issued _ valid unique_issued (put_unique records key intent.amount (.atom "voided") unique_records) next_coupling⟩
            simp [state,Elixir.HoldLedger.Exposure.«step/2»,Elixir.HoldLedger.Environment.«deliver/2»,found,
              environment_lookup,intent_lookup,raw,intent_key,detail.2.2.1,put_bridge,Erlang.erlang.«=:=/2»]

theorem completion_glue (ledger obligations event next result effects : Lynx.Term) (key amount : Int) (tag : String) (decision : Lynx.Term)
    (entries issued records : List Entry)
    (valid : Elixir.HoldLedger.Spec.«composite_valid?/1» (.tuple #[ledger,obligations]) = Except.ok Lynx.Term.true)
    (lookup : Elixir.HoldLedger.Environment.«lookup/2» (entriesTerm records) (.integer key) = Except.ok (.tuple #[.integer key,.integer amount,decision]))
    (command : (tag = "observe" ∧ (decision = .atom "approved" ∨ decision = .atom "declined") ∧
        event = .tuple #[.atom "processor_result",.integer key,decision]) ∨
      (tag = "confirm" ∧ decision = .atom "voided" ∧ event = .tuple #[.atom "void_confirmed",.integer key]))
    (applied : Elixir.HoldLedger.Ledger.«step/2» ledger event = Except.ok (.tuple #[next,result,effects]))
    (located : Erlang.erlang.«element/2» (.integer 5) next = Except.ok (entriesTerm entries))
    (unique_issued : (issued.map Entry.key).Nodup) (unique_records : (records.map Entry.key).Nodup)
    (coupling : Coupled entries issued records) : Safe (state ledger obligations issued records) (.tuple #[.atom tag,.integer key]) := by
  obtain ⟨remaining,step,preserved⟩ := composite_projection ledger obligations event next result effects valid applied
  obtain ⟨_,_,_,shape,next_valid,_,_,_⟩ := CompositeInvariant.components _ preserved
  simp only [Lynx.Term.tuple.injEq,Array.mk.injEq,List.cons.injEq,and_true] at shape
  obtain ⟨rfl,rfl⟩ := shape
  refine ⟨state next remaining issued records,?_,?_⟩
  · rcases command with ⟨rfl,allowed,rfl⟩ | ⟨rfl,rfl,rfl⟩
    · rcases allowed with rfl | rfl
      all_goals simp [state,Elixir.HoldLedger.Exposure.«step/2»,lookup,step,
        Erlang.erlang.«=:=/2»,Erlang.erlang.«and/2»]
    · simp [state,Elixir.HoldLedger.Exposure.«step/2»,lookup,step,
        Erlang.erlang.«=:=/2»]
  · exact (ExposureValidity.view next remaining entries issued records next_valid located).mpr ⟨preserved,unique_issued,unique_records,coupling⟩

theorem observed_cell (entry : Entry) (intent remote : Option Entry) (decision : Lynx.Term)
    (cell : Cell (some entry) intent remote)
    (uncertain : entry.status = .atom "sent" ∨ entry.status = .atom "unknown")
    (truth : ∃ record, remote = some record ∧ record.status = decision)
    (allowed : decision = .atom "approved" ∨ decision = .atom "declined") :
    (decision = .atom "approved" → Cell (some {entry with status := .atom "authorized"}) intent remote) ∧
    (decision = .atom "declined" → Cell (some {entry with status := .atom "declined"}) intent remote) := by
  obtain ⟨record,rfl,status⟩ := truth
  cases intent <;> simp_all [Cell] <;> grind

theorem remote_observe_known (al hl ua uh key : Int) (obligations : Lynx.Term) (entries issued records : List Entry) (record : Entry)
    (valid : Elixir.HoldLedger.Spec.«composite_valid?/1» (.tuple #[.tuple #[.integer al,.integer hl,.integer ua,.integer uh,entriesTerm entries],obligations]) = Except.ok Lynx.Term.true)
    (unique_issued : (issued.map Entry.key).Nodup) (unique_records : (records.map Entry.key).Nodup)
    (coupling : Coupled entries issued records) (remote_lookup : lookup records key = some record)
    (allowed : record.status = .atom "approved" ∨ record.status = .atom "declined") :
    Safe (state (.tuple #[.integer al,.integer hl,.integer ua,.integer uh,entriesTerm entries]) obligations issued records)
      (.tuple #[.atom "observe",.integer key]) := by
  have record_key := lookup_key remote_lookup
  have actual_lookup : Elixir.HoldLedger.Environment.«lookup/2» (entriesTerm records) (.integer key) =
      Except.ok (.tuple #[.integer key,.integer record.amount,record.status]) := by simp [environment_lookup,remote_lookup,raw,record_key]
  have cell := coupling key
  cases found : lookup entries key with
  | none => simp [found,remote_lookup,Cell] at cell
  | some entry =>
      have key_equal := lookup_key found
      have old_cell : Cell (some entry) (lookup issued key) (lookup records key) := by simpa [found] using cell
      by_cases uncertain : entry.status = .atom "sent" ∨ entry.status = .atom "unknown"
      · have choices := observed_cell entry _ _ record.status old_cell uncertain ⟨record,remote_lookup,rfl⟩ allowed
        rcases allowed with approved | declined
        · have selected := choices.1 approved
          apply completion_glue _ obligations (.tuple #[.atom "processor_result",.integer key,.atom "approved"])
            (.tuple #[.integer al,.integer hl,.integer ua,.integer uh,entriesTerm (update entries key (.atom "authorized"))])
            (.atom "authorized") .nil key record.amount "observe" (.atom "approved") (update entries key (.atom "authorized")) issued records
            valid (by simpa [approved] using actual_lookup) (Or.inl ⟨rfl,Or.inl rfl,rfl⟩) _ rfl unique_issued unique_records
            (coupled_update entries issued records key entry (.atom "authorized") coupling found selected)
          rcases uncertain with sent | unknown
          all_goals simp [*,Elixir.HoldLedger.Ledger.«step/2»,Elixir.HoldLedger.Ledger.«processor_result/3»,ledger_lookup,observed,
            update_bridge,Erlang.erlang.«is_integer/1»]
        · have selected := choices.2 declined
          apply completion_glue _ obligations (.tuple #[.atom "processor_result",.integer key,.atom "declined"])
            (.tuple #[.integer al,.integer hl,.integer (ua-entry.amount),.integer (uh-1),entriesTerm (update entries key (.atom "declined"))])
            (.atom "declined") .nil key record.amount "observe" (.atom "declined") (update entries key (.atom "declined")) issued records
            valid (by simpa [declined] using actual_lookup) (Or.inl ⟨rfl,Or.inr rfl,rfl⟩) _ rfl unique_issued unique_records
            (coupled_update entries issued records key entry (.atom "declined") coupling found selected)
          rcases uncertain with sent | unknown
          all_goals simp [*,Elixir.HoldLedger.Ledger.«step/2»,Elixir.HoldLedger.Ledger.«processor_result/3»,ledger_lookup,observed,
            update_bridge,Erlang.erlang.«is_integer/1»]
      · apply completion_glue _ obligations (.tuple #[.atom "processor_result",.integer key,record.status])
          (.tuple #[.integer al,.integer hl,.integer ua,.integer uh,entriesTerm entries]) (.atom "stale") .nil key record.amount "observe" record.status
          entries issued records valid actual_lookup (Or.inl ⟨rfl,allowed,rfl⟩) _ rfl unique_issued unique_records coupling
        have not_sent : entry.status ≠ .atom "sent" := by intro equal; exact uncertain (Or.inl equal)
        have not_unknown : entry.status ≠ .atom "unknown" := by intro equal; exact uncertain (Or.inr equal)
        rcases allowed with approved | declined
        all_goals simp [*,Elixir.HoldLedger.Ledger.«step/2»,Elixir.HoldLedger.Ledger.«processor_result/3»,ledger_lookup,observed,
          Erlang.erlang.«is_integer/1»]

theorem remote_confirm_known (al hl ua uh key : Int) (obligations : Lynx.Term) (entries issued records : List Entry) (record : Entry)
    (valid : Elixir.HoldLedger.Spec.«composite_valid?/1» (.tuple #[.tuple #[.integer al,.integer hl,.integer ua,.integer uh,entriesTerm entries],obligations]) = Except.ok Lynx.Term.true)
    (unique_issued : (issued.map Entry.key).Nodup) (unique_records : (records.map Entry.key).Nodup)
    (coupling : Coupled entries issued records) (remote_lookup : lookup records key = some record)
    (voided : record.status = .atom "voided") :
    Safe (state (.tuple #[.integer al,.integer hl,.integer ua,.integer uh,entriesTerm entries]) obligations issued records)
      (.tuple #[.atom "confirm",.integer key]) := by
  have record_key := lookup_key remote_lookup
  have actual_lookup : Elixir.HoldLedger.Environment.«lookup/2» (entriesTerm records) (.integer key) =
      Except.ok (.tuple #[.integer key,.integer record.amount,.atom "voided"]) := by simp [environment_lookup,remote_lookup,raw,record_key,voided]
  have cell := coupling key
  cases found : lookup entries key with
  | none => simp [found,remote_lookup,Cell] at cell
  | some entry =>
      have key_equal := lookup_key found
      by_cases voiding : entry.status = .atom "voiding"
      · have selected : Cell (some {entry with status := .atom "voided"}) (lookup issued key) (lookup records key) := by
          cases intent_lookup : lookup issued key
          all_goals simp_all [Cell]
        apply completion_glue _ obligations (.tuple #[.atom "void_confirmed",.integer key])
          (.tuple #[.integer al,.integer hl,.integer (ua-entry.amount),.integer (uh-1),entriesTerm (update entries key (.atom "voided"))])
          (.atom "voided") .nil key record.amount "confirm" (.atom "voided") (update entries key (.atom "voided")) issued records
          valid actual_lookup (Or.inr ⟨rfl,rfl,rfl⟩) _ rfl unique_issued unique_records
          (coupled_update entries issued records key entry (.atom "voided") coupling found selected)
        simp [Elixir.HoldLedger.Ledger.«step/2»,Elixir.HoldLedger.Ledger.«void_confirmed/2»,ledger_lookup,found,observed,voiding,
          key_equal,update_bridge]
      · apply completion_glue _ obligations (.tuple #[.atom "void_confirmed",.integer key])
          (.tuple #[.integer al,.integer hl,.integer ua,.integer uh,entriesTerm entries]) (.atom "stale") .nil key record.amount "confirm" (.atom "voided")
          entries issued records valid actual_lookup (Or.inr ⟨rfl,rfl,rfl⟩) _ rfl unique_issued unique_records coupling
        simp [Elixir.HoldLedger.Ledger.«step/2»,Elixir.HoldLedger.Ledger.«void_confirmed/2»,ledger_lookup,found,observed,voiding]

theorem remote_observe (al hl ua uh key : Int) (obligations : Lynx.Term) (entries issued records : List Entry)
    (valid : Elixir.HoldLedger.Spec.«composite_valid?/1» (.tuple #[.tuple #[.integer al,.integer hl,.integer ua,.integer uh,entriesTerm entries],obligations]) = Except.ok Lynx.Term.true)
    (unique_issued : (issued.map Entry.key).Nodup) (unique_records : (records.map Entry.key).Nodup)
    (coupling : Coupled entries issued records) :
    Safe (state (.tuple #[.integer al,.integer hl,.integer ua,.integer uh,entriesTerm entries]) obligations issued records)
      (.tuple #[.atom "observe",.integer key]) := by
  have original := pair_valid al hl ua uh obligations entries issued records valid unique_issued unique_records coupling
  cases found : lookup records key with
  | none =>
      refine ⟨_,?_,original⟩
      simp [state,Elixir.HoldLedger.Exposure.«step/2»,environment_lookup,found,raw]
  | some record =>
      have key_equal := lookup_key found
      by_cases eligible : record.status = .atom "approved" ∨ record.status = .atom "declined"
      · exact remote_observe_known al hl ua uh key obligations entries issued records record valid unique_issued unique_records coupling found eligible
      · refine ⟨_,?_,original⟩
        have not_approved : record.status ≠ .atom "approved" := by intro equal; exact eligible (Or.inl equal)
        have not_declined : record.status ≠ .atom "declined" := by intro equal; exact eligible (Or.inr equal)
        simp [*,state,Elixir.HoldLedger.Exposure.«step/2»,environment_lookup,raw,Erlang.erlang.«=:=/2»,Erlang.erlang.«and/2»]

theorem remote_confirm (al hl ua uh key : Int) (obligations : Lynx.Term) (entries issued records : List Entry)
    (valid : Elixir.HoldLedger.Spec.«composite_valid?/1» (.tuple #[.tuple #[.integer al,.integer hl,.integer ua,.integer uh,entriesTerm entries],obligations]) = Except.ok Lynx.Term.true)
    (unique_issued : (issued.map Entry.key).Nodup) (unique_records : (records.map Entry.key).Nodup)
    (coupling : Coupled entries issued records) :
    Safe (state (.tuple #[.integer al,.integer hl,.integer ua,.integer uh,entriesTerm entries]) obligations issued records)
      (.tuple #[.atom "confirm",.integer key]) := by
  have original := pair_valid al hl ua uh obligations entries issued records valid unique_issued unique_records coupling
  cases found : lookup records key with
  | none =>
      refine ⟨_,?_,original⟩
      simp [state,Elixir.HoldLedger.Exposure.«step/2»,environment_lookup,found,raw]
  | some record =>
      have key_equal := lookup_key found
      by_cases eligible : record.status = .atom "voided"
      · exact remote_confirm_known al hl ua uh key obligations entries issued records record valid unique_issued unique_records coupling found eligible
      · refine ⟨_,?_,original⟩
        simp [*,state,Elixir.HoldLedger.Exposure.«step/2»,environment_lookup,raw]

theorem local_total (al hl ua uh : Int) (obligations event : Lynx.Term) (entries issued records : List Entry)
    (valid : Elixir.HoldLedger.Spec.«composite_valid?/1» (.tuple #[.tuple #[.integer al,.integer hl,.integer ua,.integer uh,entriesTerm entries],obligations]) = Except.ok Lynx.Term.true)
    (proper : Elixir.HoldLedger.Spec.«proper_entries?/1» (entriesTerm entries) = Except.ok Lynx.Term.true)
    (unique_issued : (issued.map Entry.key).Nodup) (unique_records : (records.map Entry.key).Nodup)
    (coupling : Coupled entries issued records)
    (accepted : Elixir.HoldLedger.Exposure.«local?/1» event = Except.ok Lynx.Term.true) :
    Safe (state (.tuple #[.integer al,.integer hl,.integer ua,.integer uh,entriesTerm entries]) obligations issued records)
      (.tuple #[.atom "local",event]) := by
  by_cases restarting : event = .atom "restart"
  · subst event
    exact local_restart al hl ua uh obligations entries issued records valid unique_issued unique_records coupling
  · by_cases request : ∃ key amount, event = .tuple #[.atom "request",key,amount]
    · obtain ⟨key,amount,rfl⟩ := request
      cases key <;> try solve |
        apply local_passive al hl ua uh obligations _ (.atom "malformed") entries issued records valid accepted _ unique_issued unique_records coupling
        simp [Elixir.HoldLedger.Ledger.«step/2»,Elixir.HoldLedger.Ledger.«request/3»,Erlang.erlang.«is_integer/1»,
          Lynx.Except.guard,Lynx.Except.tryWith,bind,Except.bind]
      rename_i key
      cases amount <;> try solve |
        apply local_passive al hl ua uh obligations _ (.atom "malformed") entries issued records valid accepted _ unique_issued unique_records coupling
        simp [Elixir.HoldLedger.Ledger.«step/2»,Elixir.HoldLedger.Ledger.«request/3»,Erlang.erlang.«is_integer/1»,
          Lynx.Except.guard,Lynx.Except.tryWith,bind,Except.bind]
      rename_i amount
      exact local_request al hl ua uh key amount obligations entries issued records valid unique_issued unique_records coupling
    · by_cases dispatch : ∃ key, event = .tuple #[.atom "dispatch",key]
      · obtain ⟨key,rfl⟩ := dispatch
        cases key <;> try solve |
          apply local_passive al hl ua uh obligations _ (.atom "malformed") entries issued records valid accepted _ unique_issued unique_records coupling
          simp [Elixir.HoldLedger.Ledger.«step/2»,Elixir.HoldLedger.Ledger.«dispatch/2»,
            bind,Except.bind]
        rename_i key
        exact local_dispatch al hl ua uh key obligations entries issued records valid proper unique_issued unique_records coupling
      · by_cases timeout : ∃ key, event = .tuple #[.atom "timeout",key]
        · obtain ⟨key,rfl⟩ := timeout
          cases key <;> try solve |
            apply local_passive al hl ua uh obligations _ (.atom "malformed") entries issued records valid accepted _ unique_issued unique_records coupling
            simp [Elixir.HoldLedger.Ledger.«step/2»,Elixir.HoldLedger.Ledger.«timeout/2»,
              bind,Except.bind]
          rename_i key
          exact local_timeout al hl ua uh key obligations entries issued records valid unique_issued unique_records coupling
        · by_cases retry : ∃ key, event = .tuple #[.atom "retry",key]
          · obtain ⟨key,rfl⟩ := retry
            cases key <;> try solve |
              apply local_passive al hl ua uh obligations _ (.atom "malformed") entries issued records valid accepted _ unique_issued unique_records coupling
              simp [Elixir.HoldLedger.Ledger.«step/2»,Elixir.HoldLedger.Ledger.«retry/2»,
                bind,Except.bind]
            rename_i key
            exact local_retry al hl ua uh key obligations entries issued records valid proper unique_issued unique_records coupling
          · by_cases void : ∃ key, event = .tuple #[.atom "void",key]
            · obtain ⟨key,rfl⟩ := void
              cases key <;> try solve |
                apply local_passive al hl ua uh obligations _ (.atom "malformed") entries issued records valid accepted _ unique_issued unique_records coupling
                simp [Elixir.HoldLedger.Ledger.«step/2»,Elixir.HoldLedger.Ledger.«void/2»,
                  bind,Except.bind]
              rename_i key
              exact local_void al hl ua uh key obligations entries issued records valid unique_issued unique_records coupling
            · simp only [Elixir.HoldLedger.Exposure.«local?/1»,Lynx.Except.guard,Lynx.Except.tryWith] at accepted
              repeat' (split at accepted <;> try simp_all [Lynx.Term.true])

theorem local_boolean (event : Lynx.Term) :
    Elixir.HoldLedger.Exposure.«local?/1» event = Except.ok Lynx.Term.true ∨
    Elixir.HoldLedger.Exposure.«local?/1» event = Except.ok Lynx.Term.false := by
  unfold Elixir.HoldLedger.Exposure.«local?/1»
  split
  · exact Or.inl rfl
  · exact Or.inl rfl
  · split
    · rename_i tag argument not_restart not_request
      rcases Outbox.member_boolean tag [.atom "dispatch",.atom "timeout",.atom "retry",.atom "void"] with yes | no
      all_goals simp [*]
    · exact Or.inr rfl

theorem all_events (al hl ua uh : Int) (items : List Outbox.Obligation) (entries issued records : List Entry) (event : Lynx.Term)
    (valid : Elixir.HoldLedger.Spec.«composite_valid?/1» (.tuple #[.tuple #[.integer al,.integer hl,.integer ua,.integer uh,entriesTerm entries],Outbox.encode items]) = Except.ok Lynx.Term.true)
    (proper : Elixir.HoldLedger.Spec.«proper_entries?/1» (entriesTerm entries) = Except.ok Lynx.Term.true)
    (unique_issued : (issued.map Entry.key).Nodup) (unique_records : (records.map Entry.key).Nodup)
    (coupling : Coupled entries issued records) :
    Safe (state (.tuple #[.integer al,.integer hl,.integer ua,.integer uh,entriesTerm entries]) (Outbox.encode items) issued records) event := by
  have original := pair_valid al hl ua uh (Outbox.encode items) entries issued records valid unique_issued unique_records coupling
  by_cases local_event : ∃ operation, event = .tuple #[.atom "local",operation]
  · obtain ⟨operation,rfl⟩ := local_event
    rcases local_boolean operation with accepted | rejected
    · exact local_total al hl ua uh (Outbox.encode items) operation entries issued records valid proper unique_issued unique_records coupling accepted
    · refine ⟨_,?_,original⟩
      simp [state,Elixir.HoldLedger.Exposure.«step/2»,rejected]
  · by_cases authorization : ∃ key decision, event = .tuple #[.atom "authorize",key,decision]
    · obtain ⟨key,decision,rfl⟩ := authorization
      cases key <;> try solve |
        refine ⟨_,?_,original⟩
        simp [state,Elixir.HoldLedger.Exposure.«step/2»,Erlang.erlang.«is_integer/1»,
          bind,Except.bind]
      rename_i key
      by_cases allowed : decision = .atom "approved" ∨ decision = .atom "declined"
      · exact remote_authorize al hl ua uh key (Outbox.encode items) decision entries issued records valid unique_issued unique_records coupling allowed
      · have not_approved : decision ≠ .atom "approved" := by intro equal; exact allowed (Or.inl equal)
        have not_declined : decision ≠ .atom "declined" := by intro equal; exact allowed (Or.inr equal)
        refine ⟨_,?_,original⟩
        simp [state,Elixir.HoldLedger.Exposure.«step/2»,not_approved,not_declined,Erlang.erlang.«is_integer/1»]
    · by_cases observe : ∃ key, event = .tuple #[.atom "observe",key]
      · obtain ⟨key,rfl⟩ := observe
        cases key <;> try solve |
          refine ⟨_,?_,original⟩
          simp [state,Elixir.HoldLedger.Exposure.«step/2»,
            Lynx.Except.guard,Lynx.Except.tryWith,bind,Except.bind]
        rename_i key
        exact remote_observe al hl ua uh key (Outbox.encode items) entries issued records valid unique_issued unique_records coupling
      · by_cases void : ∃ key, event = .tuple #[.atom "void",key]
        · obtain ⟨key,rfl⟩ := void
          cases key <;> try solve |
            refine ⟨_,?_,original⟩
            simp [state,Elixir.HoldLedger.Exposure.«step/2»,
              Lynx.Except.guard,Lynx.Except.tryWith,bind,Except.bind]
          rename_i key
          exact remote_void al hl ua uh key items entries issued records valid unique_issued unique_records coupling
        · by_cases confirm : ∃ key, event = .tuple #[.atom "confirm",key]
          · obtain ⟨key,rfl⟩ := confirm
            cases key <;> try solve |
              refine ⟨_,?_,original⟩
              simp [state,Elixir.HoldLedger.Exposure.«step/2»,
                Lynx.Except.guard,Lynx.Except.tryWith,bind,Except.bind]
            rename_i key
            exact remote_confirm al hl ua uh key (Outbox.encode items) entries issued records valid unique_issued unique_records coupling
          · refine ⟨_,?_,original⟩
            simp only [state,Elixir.HoldLedger.Exposure.«step/2»]
            repeat' (split <;> try simp_all [])

end HoldLedgerProof.ExposureTransitions
