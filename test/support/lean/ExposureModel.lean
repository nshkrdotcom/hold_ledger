module
public import Elixir.HoldLedger.Exposure
public import Elixir.HoldLedger.Spec
public import HoldLedgerProof.CompositeSafety
public import HoldLedgerProof.ExposureTransitions

public section
set_option maxHeartbeats 4000000
namespace HoldLedgerProof.ExposureModel

theorem model_init_valid (amount slots : Int) (amount_nonnegative : 0 ≤ amount) (slots_nonnegative : 0 ≤ slots) :
    (do let state ← Elixir.HoldLedger.Exposure.«init/2» (.integer amount) (.integer slots)
        Elixir.HoldLedger.Spec.«exposure_valid?/1» state) = Except.ok Lynx.Term.true := by
  have initialized := CompositeSafety.init_valid amount slots amount_nonnegative slots_nonnegative
  simp [Elixir.HoldLedger.Exposure.«init/2»,Elixir.HoldLedger.Environment.«init/0»,
    Elixir.HoldLedger.Composite.«init/2»,Elixir.HoldLedger.Ledger.«init/2»,
    Elixir.HoldLedger.Spec.«exposure_valid?/1»,Elixir.HoldLedger.Spec.«issued_valid?/3»,
    Elixir.HoldLedger.Spec.«remote_valid?/3»,Elixir.HoldLedger.Spec.«local_remote_agree?/3»,
    Elixir.HoldLedger.Spec.«composite_valid?/1»,Elixir.HoldLedger.Spec.«valid?/1»,
    Elixir.HoldLedger.Spec.«nonnegative_state_valid?/5»,Elixir.HoldLedger.Spec.«proper_entries?/1»,
    Elixir.HoldLedger.Spec.«unique_keys?/1»,Elixir.HoldLedger.Spec.«unique_keys_seen?/2»,
    Elixir.HoldLedger.Spec.«hold_amount/1»,Elixir.HoldLedger.Spec.«hold_count/1»,
    Elixir.HoldLedger.Spec.«obligations_valid?/3»,Elixir.HoldLedger.Spec.«all_voiding_present?/2»,
    Erlang.erlang.«is_integer/1»,Erlang.erlang.«is_list/1»,Erlang.erlang.«==/2»,Erlang.erlang.«>=/2»,
    Erlang.erlang.«element/2»,Int.isGE_compare,
    amount_nonnegative,slots_nonnegative,
    Lynx.Term.true]

/-- Extract the independent pair predicate without assuming its consequences. -/
theorem pair_view (state : Lynx.Term)
    (valid : Elixir.HoldLedger.Spec.«exposure_valid?/1» state = Except.ok Lynx.Term.true) :
    ∃ ledger obligations issued records entries,
      state = .tuple #[.tuple #[ledger,obligations],.tuple #[issued,records]] ∧
      Elixir.HoldLedger.Spec.«composite_valid?/1» (.tuple #[ledger,obligations]) = Except.ok Lynx.Term.true ∧
      Erlang.erlang.«element/2» (.integer 5) ledger = Except.ok entries ∧
      Elixir.HoldLedger.Spec.«issued_valid?/3» issued entries .nil = Except.ok Lynx.Term.true ∧
      Elixir.HoldLedger.Spec.«remote_valid?/3» records issued .nil = Except.ok Lynx.Term.true ∧
      Elixir.HoldLedger.Spec.«local_remote_agree?/3» entries issued records = Except.ok Lynx.Term.true := by
  simp only [Elixir.HoldLedger.Spec.«exposure_valid?/1»,bind,Except.bind] at valid
  repeat' (split at * <;> try simp_all [Lynx.Term.true])
  all_goals exact ⟨_,_,_,_,⟨⟨rfl,rfl⟩,rfl,rfl⟩,by assumption,_,by assumption,by assumption,by assumption,by assumption⟩

/-- All actual translated model transitions preserve the full independent pair
    invariant, including composite coupling, remote truth and identity fencing. -/
theorem model_preserves (initial event : Lynx.Term)
    (valid : Elixir.HoldLedger.Spec.«exposure_valid?/1» initial = Except.ok Lynx.Term.true) :
    ∃ next, Elixir.HoldLedger.Exposure.«step/2» initial event = Except.ok next ∧
      Elixir.HoldLedger.Spec.«exposure_valid?/1» next = Except.ok Lynx.Term.true := by
  obtain ⟨ledger,obligations,issued,records,entries,rfl,composite,located,issued_valid,remote_valid,agreement⟩ := pair_view initial valid
  obtain ⟨_,_,_,shape,ledger_valid,_,obligations_valid,_⟩ := CompositeInvariant.components _ composite
  simp only [Lynx.Term.tuple.injEq,Array.mk.injEq,List.cons.injEq,and_true] at shape
  obtain ⟨rfl,rfl⟩ := shape
  obtain ⟨al,hl,ua,uh,actual,rfl,proper,_,_,_,_,_,_,_,_,_⟩ := valid_view_1 ledger ledger_valid
  have equal : actual = entries := by simpa [Erlang.erlang.«element/2»] using located
  subst entries
  obtain ⟨native_entries,rfl⟩ := ExposureFacts.ledger_shape actual proper
  obtain ⟨native_issued,rfl⟩ := ExposureFacts.issued_shape issued _ .nil issued_valid
  obtain ⟨native_records,rfl⟩ := ExposureFacts.remote_shape records _ .nil remote_valid
  obtain ⟨native_items,rfl⟩ := CompositeInvariant.obligation_shape obligations _ .nil obligations_valid
  have issued_unique := (ExposureFacts.issued_unique native_issued _ [] issued_valid).1
  have remote_unique := (ExposureFacts.remote_unique native_records _ [] remote_valid).1
  have coupling := ExposureValidity.coupled native_entries native_issued native_records proper issued_valid remote_valid agreement
  exact ExposureTransitions.all_events al hl ua uh native_items native_entries native_issued native_records event
    composite proper issued_unique remote_unique coupling

/-- The environment fences an identity even when void precedes its first issued
    authorization. This is a processor-contract lemma, not a reachable pair state. -/
theorem void_before_issue (key amount : Int) (positive : 0 < amount) :
    (do let initial ← Elixir.HoldLedger.Environment.«init/0»
        let voided ← Elixir.HoldLedger.Environment.«deliver/2» initial (.tuple #[.atom "void",.integer key])
        let fenced ← Erlang.erlang.«element/2» (.integer 1) voided
        let issued ← Elixir.HoldLedger.Environment.«issue/2» fenced (.tuple #[.atom "authorize",.integer key,.integer amount])
        Elixir.HoldLedger.Environment.«deliver/2» issued (.tuple #[.atom "authorize",.integer key,.atom "approved"])) =
      Except.ok (.tuple #[.tuple #[.cons (.tuple #[.integer key,.integer amount,.atom "issued"]) .nil,
        .cons (.tuple #[.integer key,.integer 0,.atom "voided"]) .nil],.atom "declined"]) := by
  simp [Elixir.HoldLedger.Environment.«init/0»,Elixir.HoldLedger.Environment.«deliver/2»,
    Elixir.HoldLedger.Environment.«issue/2»,Elixir.HoldLedger.Environment.«lookup/2»,
    Elixir.HoldLedger.Environment.«put/4»,Erlang.erlang.«element/2»,Erlang.erlang.«is_integer/1»,
    Erlang.erlang.«>/2»,Erlang.erlang.«=:=/2»,Int.compare_eq_gt,Ordering.isGT_iff_eq_gt,positive]

theorem model_history (initial : Lynx.Term) (events : List Lynx.Term)
    (valid : Elixir.HoldLedger.Spec.«exposure_valid?/1» initial = Except.ok Lynx.Term.true) :
    ∃ final, Elixir.HoldLedger.Exposure.«run/2» initial (.list events) = Except.ok final ∧
      Elixir.HoldLedger.Spec.«exposure_valid?/1» final = Except.ok Lynx.Term.true := by
  induction events generalizing initial with
  | nil => exact ⟨initial,rfl,valid⟩
  | cons event rest ih =>
      obtain ⟨next,applied,preserved⟩ := model_preserves initial event valid
      obtain ⟨final,run,final_valid⟩ := ih next preserved
      refine ⟨final,?_,final_valid⟩
      simpa [Lynx.Term.list,Elixir.HoldLedger.Exposure.«run/2»,applied,bind,Except.bind] using run

/-- The pair invariant implies numerical remote live amount/count bounds;
    no history-shaped causality hypothesis is substituted for that invariant. -/
theorem model_bounds (al hl ua uh : Int) (entries issued records : List Exposure.Entry) (items : List Outbox.Obligation)
    (valid : Elixir.HoldLedger.Spec.«exposure_valid?/1»
      (.tuple #[.tuple #[.tuple #[.integer al,.integer hl,.integer ua,.integer uh,Exposure.entriesTerm entries],Outbox.encode items],
        .tuple #[Exposure.entriesTerm issued,Exposure.entriesTerm records]]) = Except.ok Lynx.Term.true) :
    Capacity.amount (ExposureFacts.livePairs records) ≤ al ∧ ((ExposureFacts.livePairs records).length : Int) ≤ hl := by
  have parts :
      Elixir.HoldLedger.Spec.«composite_valid?/1» (.tuple #[.tuple #[.integer al,.integer hl,.integer ua,.integer uh,Exposure.entriesTerm entries],Outbox.encode items]) = Except.ok Lynx.Term.true ∧
      Elixir.HoldLedger.Spec.«issued_valid?/3» (Exposure.entriesTerm issued) (Exposure.entriesTerm entries) .nil = Except.ok Lynx.Term.true ∧
      Elixir.HoldLedger.Spec.«remote_valid?/3» (Exposure.entriesTerm records) (Exposure.entriesTerm issued) .nil = Except.ok Lynx.Term.true ∧
      Elixir.HoldLedger.Spec.«local_remote_agree?/3» (Exposure.entriesTerm entries) (Exposure.entriesTerm issued) (Exposure.entriesTerm records) = Except.ok Lynx.Term.true := by
    simp only [Elixir.HoldLedger.Spec.«exposure_valid?/1»,Erlang.erlang.«element/2»,bind,Except.bind] at valid
    repeat' (split at * <;> try simp_all [Lynx.Term.true])
  obtain ⟨composite,issued_valid,remote_valid,agreement⟩ := parts
  obtain ⟨_,_,_,shape,ledger_valid,_,_,_⟩ := CompositeInvariant.components _ composite
  simp only [Lynx.Term.tuple.injEq,Array.mk.injEq,List.cons.injEq,and_true] at shape
  obtain ⟨rfl,rfl⟩ := shape
  obtain ⟨_,_,_,_,_,shape,proper,_,amount,count,_,_,_,_,amount_cap,count_cap⟩ := valid_view_1 _ ledger_valid
  simp only [Lynx.Term.tuple.injEq,Array.mk.injEq,List.cons.injEq,Lynx.Term.integer.injEq,and_true] at shape
  obtain ⟨rfl,rfl,rfl,rfl,rfl⟩ := shape
  have unique := (ExposureFacts.remote_unique records (Exposure.entriesTerm issued) [] remote_valid).1
  have covered : ∀ pair ∈ ExposureFacts.livePairs records, pair ∈ Exposure.holdingPairs entries := by
    intro pair member
    obtain ⟨record,remote_member,rfl,approved⟩ := ExposureFacts.live_origin records pair member
    have issued_lookup := (ExposureFacts.remote_member records issued .nil remote_valid record remote_member).2
    obtain ⟨intent,intent_member,intent_key,intent_amount,_⟩ := Exposure.encoded_lookup_member issued_lookup
    obtain ⟨_,_,status,local_lookup⟩ := ExposureFacts.issued_member issued (Exposure.entriesTerm entries) .nil proper issued_valid intent intent_member
    rw [intent_key,intent_amount] at local_lookup
    obtain ⟨entry,entry_member,entry_key,entry_amount,entry_status⟩ := Exposure.encoded_lookup_member local_lookup
    have agrees := (ExposureFacts.local_agree entries (Exposure.entriesTerm issued) (Exposure.entriesTerm records)).mp agreement entry entry_member
    have remote_lookup := ExposureFacts.lookup_of_member records record unique remote_member
    rw [entry_key,entry_amount,entry_status,issued_lookup,remote_lookup] at agrees
    simp only [approved,bind,Except.bind] at agrees
    have holds := (ExposureFacts.approved_holds record.key record.amount record.amount status agrees).2
    have included := Exposure.holding_pair_member entry_member (by simpa [entry_status] using holds)
    simpa [entry_key,entry_amount] using included
  have nonnegative : ∀ pair ∈ Exposure.holdingPairs entries, 0 ≤ pair.2 := by
    intro pair member
    obtain ⟨entry,entry_member,rfl⟩ := Exposure.holding_pair_origin member
    exact Int.le_of_lt (Exposure.encoded_positive proper entry entry_member)
  obtain ⟨used,slots⟩ := Capacity.subset_bounds (ExposureFacts.live_distinct records unique) covered nonnegative
  have amounts := Exposure.encoded_amount entries
  have counts := Exposure.encoded_count entries
  rw [amounts] at amount
  rw [counts] at count
  have same_amount : Capacity.amount (Exposure.holdingPairs entries) = ua := by simpa using amount
  have same_count : ((Exposure.holdingPairs entries).length : Int) = uh := by simpa using count
  rw [same_amount] at used
  exact ⟨Int.le_trans used amount_cap,by omega⟩

end HoldLedgerProof.ExposureModel
