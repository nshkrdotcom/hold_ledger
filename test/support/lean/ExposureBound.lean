module
public import HoldLedgerProof.ExposureTrace
public import HoldLedgerProof.Capacity
public import HoldLedgerProof.Terminal
import Lean

public section
set_option maxHeartbeats 16000000
namespace HoldLedgerProof.Exposure

structure Entry where
  key : Int
  amount : Int
  status : Lynx.Term

@[expose] def entriesTerm : List Entry → Lynx.Term
  | [] => .nil
  | entry :: rest => .cons (.tuple #[.integer entry.key,.integer entry.amount,entry.status]) (entriesTerm rest)

def holdingPairs : List Entry → List (Int × Int)
  | [] => []
  | entry :: rest =>
      if HoldLedgerProof.held entry.status then (entry.key,entry.amount) :: holdingPairs rest
      else holdingPairs rest

theorem encoded_lookup_member {entries : List Entry} {key amount : Int} {status : Lynx.Term}
    (found : Elixir.HoldLedger.Spec.«lookup/2» (entriesTerm entries) (.integer key) =
      Except.ok (.tuple #[.atom "ok",.tuple #[.integer key,.integer amount,status]])) :
    ∃ entry ∈ entries, entry.key = key ∧ entry.amount = amount ∧ entry.status = status := by
  induction entries with
  | nil => simp [entriesTerm,Elixir.HoldLedger.Spec.«lookup/2»] at found
  | cons entry rest ih =>
      by_cases same : entry.key = key
      · simp [entriesTerm,Elixir.HoldLedger.Spec.«lookup/2»,same,Erlang.erlang.«==/2»] at found
        exact ⟨entry,by simp,same,found.1,found.2⟩
      · have tail : Elixir.HoldLedger.Spec.«lookup/2» (entriesTerm rest) (.integer key) =
            Except.ok (.tuple #[.atom "ok",.tuple #[.integer key,.integer amount,status]]) := by
          simpa [entriesTerm,Elixir.HoldLedger.Spec.«lookup/2»,same,Erlang.erlang.«==/2»,
            Lynx.Term.compare_integers,Int.compare_eq_eq,bind,Except.bind] using found
        obtain ⟨selected,member,hkey,hamount,hstatus⟩ := ih tail
        exact ⟨selected,by simp [member],hkey,hamount,hstatus⟩

theorem holding_pair_member {entries : List Entry} {entry : Entry}
    (member : entry ∈ entries) (holding : HoldLedgerProof.held entry.status = true) :
    (entry.key,entry.amount) ∈ holdingPairs entries := by
  induction entries with
  | nil => simp at member
  | cons head rest ih =>
      rcases List.mem_cons.mp member with rfl | tail
      · simp [holdingPairs,holding]
      · simp only [holdingPairs]
        split
        · exact List.mem_cons_of_mem _ (ih tail)
        · exact ih tail

theorem holding_pair_origin {entries : List Entry} {pair : Int × Int}
    (member : pair ∈ holdingPairs entries) :
    ∃ entry ∈ entries, pair = (entry.key,entry.amount) := by
  induction entries with
  | nil => simp [holdingPairs] at member
  | cons entry rest ih =>
      simp only [holdingPairs] at member
      split at member
      · rcases List.mem_cons.mp member with equal | tail
        · exact ⟨entry,by simp,equal⟩
        · obtain ⟨e,h,eq⟩ := ih tail
          exact ⟨e,by simp [h],eq⟩
      · obtain ⟨e,h,eq⟩ := ih member
        exact ⟨e,by simp [h],eq⟩

theorem encoded_positive {entries : List Entry}
    (proper : Elixir.HoldLedger.Spec.«proper_entries?/1» (entriesTerm entries) = Except.ok Lynx.Term.true) :
    ∀ entry ∈ entries, 0 < entry.amount := by
  induction entries with
  | nil => simp
  | cons head rest ih =>
      simp only [entriesTerm,Elixir.HoldLedger.Spec.«proper_entries?/1»,
        Erlang.erlang.«is_integer/1»,Lynx.Except.guard,Lynx.Except.tryWith,
        bind,Except.bind] at proper
      repeat' (split at proper <;> try simp_all [Lynx.Term.true])
      all_goals simp_all [Erlang.erlang.«>/2»,Ordering.isGT_iff_eq_gt,Int.compare_eq_gt,
        Lynx.Term.true,Lynx.Term.false]
      all_goals repeat' (split at * <;> try simp_all [Lynx.Term.true,Lynx.Term.false])

theorem encoded_amount (entries : List Entry) :
    Elixir.HoldLedger.Spec.«hold_amount/1» (entriesTerm entries) =
      Except.ok (.integer (HoldLedgerProof.Capacity.amount (holdingPairs entries))) := by
  induction entries with
  | nil => rfl
  | cons entry rest ih =>
      cases held : HoldLedgerProof.held entry.status <;>
        simp [entriesTerm,holdingPairs,held,Elixir.HoldLedger.Spec.«hold_amount/1»,
          HoldLedgerProof.holding_model,HoldLedgerProof.Capacity.amount,ih,
          Lynx.Term.true,Lynx.Term.false]

theorem encoded_count (entries : List Entry) :
    Elixir.HoldLedger.Spec.«hold_count/1» (entriesTerm entries) =
      Except.ok (.integer (holdingPairs entries).length) := by
  induction entries with
  | nil => rfl
  | cons entry rest ih =>
      cases held : HoldLedgerProof.held entry.status <;>
        simp [entriesTerm,holdingPairs,held,Elixir.HoldLedger.Spec.«hold_count/1»,
          HoldLedgerProof.holding_model,ih,Lynx.Term.true,Lynx.Term.false]
      all_goals omega

/-- A live processor authorization has an issued-intent witness and no truthful
    terminal evidence since that intent. These are environmental causality,
    truthful-decline and non-resurrection hypotheses, not the desired final bound. -/
def CausalLive (final : Lynx.Term) (authorization : Int × Int) : Prop :=
  ∃ issued events,
    Elixir.HoldLedger.Spec.«valid?/1» issued = Except.ok Lynx.Term.true ∧
    Elixir.HoldLedger.Spec.«effect_valid?/2» issued
      (.tuple #[.atom "authorize",.integer authorization.1,.integer authorization.2]) = Except.ok Lynx.Term.true ∧
    NoRelease authorization.1 events ∧
    Elixir.HoldLedger.Ledger.«run/2» issued (Lynx.Term.list events) = Except.ok final

theorem issued_protected {state : Lynx.Term} {key amount : Int}
    (valid : Elixir.HoldLedger.Spec.«valid?/1» state = Except.ok Lynx.Term.true)
    (issued : Elixir.HoldLedger.Spec.«effect_valid?/2» state
      (.tuple #[.atom "authorize",.integer key,.integer amount]) = Except.ok Lynx.Term.true) :
    Protected state key amount := by
  obtain ⟨al,hl,ua,uh,entries,rfl,hp,hu,ha,hc,hal,hhl,hua,huh,hacap,hhcap⟩ := valid_view_1 state valid
  rcases lookup_shape_1 entries (.integer key) hp with absent | ⟨stored,amt,status,found,known⟩
  · simp [Elixir.HoldLedger.Spec.«effect_valid?/2»,absent,Erlang.erlang.«==/2»,
      HoldLedgerProof.atom_tuple,Lynx.Term.true,Lynx.Term.false] at issued
  · simp [Elixir.HoldLedger.Spec.«effect_valid?/2»,found,Erlang.erlang.«==/2»,
      HoldLedgerProof.lookup_compare_status,Lynx.Term.compare_integers,
      Lynx.Term.true,Lynx.Term.false] at issued
    obtain ⟨rfl,rfl,rfl⟩ := issued
    exact ⟨valid,al,hl,ua,uh,entries,.atom "sent",rfl,found,Or.inl rfl⟩

theorem live_is_protected {final : Lynx.Term} {authorization : Int × Int}
    (causal : CausalLive final authorization) : Protected final authorization.1 authorization.2 := by
  obtain ⟨issued,events,valid,intent,processor,replayed⟩ := causal
  obtain ⟨actual,applied,held⟩ := retained_history (issued_protected valid intent) processor
  have same : actual = final := Except.ok.inj (applied.symm.trans replayed)
  simpa [same] using held

/-- Remote live amount and count stay within both limits, under explicit
    processor causality, terminal truth/fencing and identity deduplication.
    All ledger functions referenced here are the actual translated definitions. -/
theorem exposure_bounds (al hl ua uh : Int) (entries : List Entry) (remote : List (Int × Int))
    (valid : Elixir.HoldLedger.Spec.«valid?/1»
      (.tuple #[.integer al,.integer hl,.integer ua,.integer uh,entriesTerm entries]) = Except.ok Lynx.Term.true)
    (deduplicated : (remote.map Prod.fst).Nodup)
    (processor : ∀ authorization ∈ remote,
      CausalLive (.tuple #[.integer al,.integer hl,.integer ua,.integer uh,entriesTerm entries]) authorization) :
    HoldLedgerProof.Capacity.amount remote ≤ al ∧ (remote.length : Int) ≤ hl := by
  have unique : remote.Nodup := deduplicated.of_map Prod.fst (by intro a b different equal; exact different (congrArg Prod.fst equal))
  have covered : ∀ authorization ∈ remote, authorization ∈ holdingPairs entries := by
    intro authorization member
    obtain ⟨_,_,_,_,_,es,status,shape,found,holding⟩ := live_is_protected (processor authorization member)
    simp at shape
    obtain ⟨rfl,rfl,rfl,rfl,rfl⟩ := shape
    obtain ⟨entry,entry_member,hkey,hamount,hstatus⟩ := encoded_lookup_member found
    have included := holding_pair_member entry_member (by rw [hstatus]; rcases holding with rfl | rfl | rfl | rfl <;> rfl)
    simpa [hkey,hamount] using included
  obtain ⟨_,_,_,_,_,shape,proper,_,amount,count,_,_,_,_,amount_cap,count_cap⟩ := valid_view_1 _ valid
  simp at shape
  obtain ⟨rfl,rfl,rfl,rfl,rfl⟩ := shape
  have nonnegative : ∀ entry ∈ holdingPairs entries, 0 ≤ entry.2 := by
    intro pair member
    obtain ⟨entry,hentry,equal⟩ := holding_pair_origin member
    rw [equal]
    exact Int.le_of_lt (encoded_positive proper entry hentry)
  obtain ⟨used,slots⟩ := HoldLedgerProof.Capacity.subset_bounds unique covered nonnegative
  have amounts := encoded_amount entries
  have counts := encoded_count entries
  rw [amount] at amounts
  rw [count] at counts
  simp only [Except.ok.injEq,Lynx.Term.integer.injEq] at amounts counts
  omega

end HoldLedgerProof.Exposure
