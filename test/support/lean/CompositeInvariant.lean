module
public import HoldLedgerProof.CompositeEntries
public import Elixir.HoldLedger.Spec
import Lean

public section
set_option maxHeartbeats 4000000
namespace HoldLedgerProof.CompositeInvariant
open HoldLedgerProof.Outbox

theorem components (state : Lynx.Term)
    (valid : Elixir.HoldLedger.Spec.«composite_valid?/1» state = Except.ok Lynx.Term.true) :
    ∃ ledger obligations entries,
      state = .tuple #[ledger,obligations] ∧
      Elixir.HoldLedger.Spec.«valid?/1» ledger = Except.ok Lynx.Term.true ∧
      Erlang.erlang.«element/2» (.integer 5) ledger = Except.ok entries ∧
      Elixir.HoldLedger.Spec.«obligations_valid?/3» obligations entries .nil = Except.ok Lynx.Term.true ∧
      Elixir.HoldLedger.Spec.«all_voiding_present?/2» entries obligations = Except.ok Lynx.Term.true := by
  simp only [Elixir.HoldLedger.Spec.«composite_valid?/1»,bind,Except.bind] at valid
  repeat' (split at * <;> try simp_all [Lynx.Term.true])
  all_goals exact ⟨_,_,⟨rfl,rfl⟩,by assumption,_,by assumption,by assumption,by assumption⟩

theorem obligation_shape (items entries seen : Lynx.Term)
    (valid : Elixir.HoldLedger.Spec.«obligations_valid?/3» items entries seen = Except.ok Lynx.Term.true) :
    ∃ obligations : List Obligation, items = encode obligations := by
  fun_induction Elixir.HoldLedger.Spec.«obligations_valid?/3» items entries seen
  all_goals try simp only [Erlang.erlang.«is_integer/1»,
    Lynx.Except.guard,Lynx.Except.tryWith,Lynx.Except.andAlso,bind,Except.bind] at valid
  all_goals repeat' (split at * <;> try simp_all [Lynx.Term.true,Lynx.Term.false])
  all_goals try exact ⟨[],rfl⟩
  all_goals obtain ⟨rest,equal⟩ := (by assumption : ∃ os : List Obligation, _)
  all_goals subst_vars
  all_goals exact ⟨⟨_,_,_⟩ :: rest,rfl⟩

theorem obligations_cons (item : Obligation) (rest : List Obligation) (entries : Lynx.Term) (visited : List Int)
    (proper : Elixir.HoldLedger.Spec.«proper_entries?/1» entries = Except.ok Lynx.Term.true) :
    Elixir.HoldLedger.Spec.«obligations_valid?/3» (encode (item :: rest)) entries (CompositeEntries.keysTerm visited) =
      Except.ok Lynx.Term.true ↔
    0 ≤ item.count ∧ item.key ∉ visited ∧
      Elixir.HoldLedger.Spec.«outcome_valid?/1» item.outcome = Except.ok Lynx.Term.true ∧
      Voiding.At entries item.key ∧
      Elixir.HoldLedger.Spec.«obligations_valid?/3» (encode rest) entries (CompositeEntries.keysTerm (item.key :: visited)) =
        Except.ok Lynx.Term.true := by
  rcases valid_outcome_boolean item.outcome with outcome | outcome
  all_goals rcases Voiding.integer_lookup_shape entries item.key proper with ⟨_,absent⟩ | ⟨amount,status,_,located,_⟩
  all_goals by_cases nonnegative : 0 ≤ item.count
  all_goals by_cases visited_before : item.key ∈ visited
  all_goals try solve | simp [absent,encode,Elixir.HoldLedger.Spec.«obligations_valid?/3»,CompositeEntries.seen,
    outcome,visited_before,nonnegative,Erlang.erlang.«is_integer/1»,Erlang.erlang.«>=/2»,
    Int.isGE_compare,Elixir.HoldLedger.Spec.«voiding_entry?/1»,
    Voiding.at_absent entries item.key (by assumption),
    Lynx.Except.andAlso,
    Lynx.Term.true,Lynx.Term.false]
  all_goals by_cases voiding : status = .atom "voiding"
  all_goals simp [encode,Elixir.HoldLedger.Spec.«obligations_valid?/3»,CompositeEntries.seen,
    outcome,visited_before,nonnegative,Erlang.erlang.«is_integer/1»,Erlang.erlang.«>=/2»,
    Int.isGE_compare,Elixir.HoldLedger.Spec.«voiding_entry?/1»,located,voiding,
    Voiding.at_found entries item.key amount status located,
    Lynx.Except.andAlso,
    Lynx.Term.true,Lynx.Term.false]
  all_goals rfl

theorem obligations_view (items : List Obligation) (entries : Lynx.Term) (visited : List Int)
    (proper : Elixir.HoldLedger.Spec.«proper_entries?/1» entries = Except.ok Lynx.Term.true) :
    Elixir.HoldLedger.Spec.«obligations_valid?/3» (encode items) entries (CompositeEntries.keysTerm visited) = Except.ok Lynx.Term.true ↔
      (items.map Obligation.key).Nodup ∧ ∀ item ∈ items,
        item.key ∉ visited ∧ 0 ≤ item.count ∧
        Elixir.HoldLedger.Spec.«outcome_valid?/1» item.outcome = Except.ok Lynx.Term.true ∧ Voiding.At entries item.key := by
  induction items generalizing visited with
  | nil => simp [encode,Elixir.HoldLedger.Spec.«obligations_valid?/3»]
  | cons item rest ih =>
      rw [obligations_cons item rest entries visited proper,ih (item.key :: visited)]
      simp only [List.map_cons,List.nodup_cons,List.mem_cons,forall_eq_or_imp,not_or,List.mem_map]
      grind

abbrev Well := Outbox.Well

/-- Full metadata validity plus equality with the physical ledger's voiding keys. -/
theorem full_view (ledger : Lynx.Term) (items : List Obligation) (entries : Lynx.Term)
    (valid : Elixir.HoldLedger.Spec.«valid?/1» ledger = Except.ok Lynx.Term.true)
    (located : Erlang.erlang.«element/2» (.integer 5) ledger = Except.ok entries) :
    Elixir.HoldLedger.Spec.«composite_valid?/1» (.tuple #[ledger,encode items]) = Except.ok Lynx.Term.true ↔
      Well items ∧ ∀ key, Voiding.At entries key ↔ key ∈ items.map Obligation.key := by
  obtain ⟨al,hl,ua,uh,actual,shape,proper,distinct,_,_,_,_,_,_,_,_⟩ := valid_view_1 ledger valid
  have same : actual = entries := by subst ledger; simpa [Erlang.erlang.«element/2»] using located
  subst actual
  obtain ⟨physical,rfl⟩ := CompositeEntries.shape entries proper
  have physical_unique : (physical.map CompositeEntries.Entry.key).Nodup := by
    have listed : Erlang.erlang.«is_list/1» (CompositeEntries.encode physical) = Except.ok Lynx.Term.true := by cases physical <;> rfl
    have unique_seen : Elixir.HoldLedger.Spec.«unique_keys_seen?/2» (CompositeEntries.encode physical) .nil = Except.ok Lynx.Term.true := by
      simpa [Elixir.HoldLedger.Spec.«unique_keys?/1»,listed,Lynx.Except.tryWith,bind,Except.bind] using distinct
    exact ((CompositeEntries.unique physical []).mp unique_seen).1
  have all_present := CompositeEntries.all_present_lookup physical items physical_unique
  have metadata := obligations_view items (CompositeEntries.encode physical) [] proper
  simp only [Elixir.HoldLedger.Spec.«composite_valid?/1»,valid,located,bind,Except.bind]
  rw [show CompositeEntries.keysTerm [] = Lynx.Term.nil from rfl] at metadata
  constructor
  · intro combined
    have both : Elixir.HoldLedger.Spec.«obligations_valid?/3» (encode items) (CompositeEntries.encode physical) .nil = Except.ok Lynx.Term.true ∧
        Elixir.HoldLedger.Spec.«all_voiding_present?/2» (CompositeEntries.encode physical) (encode items) = Except.ok Lynx.Term.true := by
      repeat' (split at combined <;> try simp_all [Lynx.Term.true])
    obtain ⟨unique,each⟩ := metadata.mp both.1
    refine ⟨⟨unique,by intro item member; exact ⟨(each item member).2.1,(each item member).2.2.1⟩⟩,?_⟩
    intro key
    constructor
    · exact all_present.mp both.2 key
    · intro member
      obtain ⟨item,member,equal⟩ := List.mem_map.mp member
      simpa [equal] using (each item member).2.2.2
  · rintro ⟨⟨unique,each⟩,coupled⟩
    have good := metadata.mpr ⟨unique,by
      intro item member
      exact ⟨by simp,(each item member).1,(each item member).2,
        (coupled item.key).mpr (List.mem_map.mpr ⟨item,member,rfl⟩)⟩⟩
    have present := all_present.mpr (by intro key found; exact (coupled key).mp found)
    simp [good,present,Lynx.Term.true]

/-- Obligations cannot name a ledger entry in a non-voiding status. -/
theorem nonvoid_absent (items : List Obligation) (entries seen : Lynx.Term) (key amount : Int) (status : Lynx.Term)
    (valid : Elixir.HoldLedger.Spec.«obligations_valid?/3» (encode items) entries seen = Except.ok Lynx.Term.true)
    (located : Elixir.HoldLedger.Spec.«lookup/2» entries (.integer key) =
      Except.ok (.tuple #[.atom "ok",.tuple #[.integer key,.integer amount,status]]))
    (not_voiding : status ≠ .atom "voiding") : key ∉ items.map Obligation.key := by
  induction items generalizing seen with
  | nil => simp
  | cons item rest ih =>
      simp only [encode,Elixir.HoldLedger.Spec.«obligations_valid?/3»,
        Erlang.erlang.«is_integer/1»,Lynx.Except.guard,Lynx.Except.tryWith,
        Lynx.Except.andAlso,bind,Except.bind] at valid
      repeat' (split at valid <;> try simp_all [Lynx.Term.true,Lynx.Term.false])
      all_goals have tail : key ∉ rest.map Obligation.key := by simpa using ih _ (by assumption)
      all_goals by_cases same : key = item.key
      all_goals try solve | exact ⟨same,by simpa using tail⟩
      all_goals subst key
      all_goals simp_all [Elixir.HoldLedger.Spec.«voiding_entry?/1»]
      all_goals repeat' (split at * <;> try simp_all [])

theorem assemble (ledger obligations entries : Lynx.Term)
    (ledger_valid : Elixir.HoldLedger.Spec.«valid?/1» ledger = Except.ok Lynx.Term.true)
    (entries_eq : Erlang.erlang.«element/2» (.integer 5) ledger = Except.ok entries)
    (obligations_valid : Elixir.HoldLedger.Spec.«obligations_valid?/3» obligations entries .nil = Except.ok Lynx.Term.true)
    (all_present : Elixir.HoldLedger.Spec.«all_voiding_present?/2» entries obligations = Except.ok Lynx.Term.true) :
    Elixir.HoldLedger.Spec.«composite_valid?/1» (.tuple #[ledger,obligations]) = Except.ok Lynx.Term.true := by
  simp [Elixir.HoldLedger.Spec.«composite_valid?/1»,ledger_valid,entries_eq,obligations_valid,all_present]

end HoldLedgerProof.CompositeInvariant
