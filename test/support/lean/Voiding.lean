module
public import HoldLedgerProof.Oracle
import Lean

public section
set_option maxHeartbeats 4000000
namespace HoldLedgerProof.Voiding

theorem integer_lookup_shape : ∀ es (k : Int), Elixir.HoldLedger.Spec.«proper_entries?/1» es = Except.ok Lynx.Term.true →
    (Elixir.HoldLedger.Ledger.«find/2» es (Lynx.Term.integer k) = Except.ok (Lynx.Term.atom "not_found") ∧
      Elixir.HoldLedger.Spec.«lookup/2» es (Lynx.Term.integer k) = Except.ok (Lynx.Term.atom "not_found")) ∨
    ∃ (a : Int) (st : Lynx.Term),
      Elixir.HoldLedger.Ledger.«find/2» es (Lynx.Term.integer k) =
        Except.ok (Lynx.Term.tuple #[Lynx.Term.atom "ok", Lynx.Term.tuple #[Lynx.Term.integer k, Lynx.Term.integer a, st]]) ∧
      Elixir.HoldLedger.Spec.«lookup/2» es (Lynx.Term.integer k) =
        Except.ok (Lynx.Term.tuple #[Lynx.Term.atom "ok", Lynx.Term.tuple #[Lynx.Term.integer k, Lynx.Term.integer a, st]]) ∧
      Elixir.HoldLedger.Spec.«known_status?/1» st = Except.ok Lynx.Term.true := by
  intro es k h
  fun_induction Elixir.HoldLedger.Ledger.«find/2» es (Lynx.Term.integer k)
  all_goals simp only [Elixir.HoldLedger.Spec.«proper_entries?/1»,
    Lynx.Except.guard, Lynx.Except.tryWith, Lynx.Except.andAlso,  bind, Except.bind] at h
  all_goals repeat' (split at h <;> try simp_all [Lynx.Term.true])
  all_goals simp_all [ Elixir.HoldLedger.Spec.«lookup/2»,
    Erlang.erlang.«is_integer/1», Erlang.erlang.«==/2»,  Lynx.Term.true, Lynx.Term.false]
  all_goals repeat' (split at * <;> subst_vars <;> try simp_all [])
  all_goals first | assumption | exact ⟨_, _, ⟨rfl, rfl⟩, by assumption⟩

theorem selected_status : ∀ es k a old to,
    Elixir.HoldLedger.Spec.«proper_entries?/1» es = Except.ok Lynx.Term.true →
    Elixir.HoldLedger.Spec.«lookup/2» es k =
      Except.ok (Lynx.Term.tuple #[Lynx.Term.atom "ok", Lynx.Term.tuple #[k,a,old]]) →
    ∃ out, Elixir.HoldLedger.Ledger.«set_status/3» es k to = Except.ok out ∧
      Elixir.HoldLedger.Spec.«lookup/2» out k =
        Except.ok (Lynx.Term.tuple #[Lynx.Term.atom "ok", Lynx.Term.tuple #[k,a,to]]) := by
  intro es k a old to hp hf
  fun_induction Elixir.HoldLedger.Spec.«lookup/2» es k generalizing a old to
  case case1 => simp [] at hf
  case case3 => simp [] at hf
  case case2 ek av st rest ih =>
    have recur := ih a old to
    all_goals simp only [Elixir.HoldLedger.Spec.«proper_entries?/1»,
      Lynx.Except.guard, Lynx.Except.tryWith, Lynx.Except.andAlso,  bind, Except.bind] at hp
    all_goals repeat' (split at hp <;> try simp_all [Lynx.Term.true])
    all_goals simp_all [Erlang.erlang.«==/2», Erlang.erlang.«is_integer/1», Lynx.Term.true, Lynx.Term.false]
    all_goals repeat' (split at * <;> subst_vars <;> try simp_all [])
    all_goals try obtain ⟨out, hm, hl⟩ := recur
    all_goals try obtain ⟨out, hm, hl⟩ := recur rfl rfl
    all_goals try obtain ⟨out, hm, hl⟩ := ih a old to rfl rfl
    all_goals simp_all [Elixir.HoldLedger.Ledger.«set_status/3», Elixir.HoldLedger.Spec.«lookup/2»,
      Erlang.erlang.«==/2»,
      Lynx.Term.true, Lynx.Term.false]
    all_goals repeat' (split <;> try simp_all [Lynx.Term.true, Lynx.Term.false])
    all_goals try first | rfl | exact ⟨_,rfl,rfl⟩ | solve_by_elim

/-- Replacing a status does not introduce a previously absent identity. -/
theorem set_absent : ∀ entries (changed query : Int) status,
    Elixir.HoldLedger.Spec.«proper_entries?/1» entries = Except.ok Lynx.Term.true →
    Elixir.HoldLedger.Spec.«lookup/2» entries (.integer query) = Except.ok (.atom "not_found") →
    ∃ out, Elixir.HoldLedger.Ledger.«set_status/3» entries (.integer changed) status = Except.ok out ∧
      Elixir.HoldLedger.Spec.«lookup/2» out (.integer query) = Except.ok (.atom "not_found") := by
  intro entries changed query status proper absent
  fun_induction Elixir.HoldLedger.Spec.«lookup/2» entries (.integer query) generalizing changed status
  all_goals simp only [Elixir.HoldLedger.Spec.«proper_entries?/1»,Lynx.Except.guard,Lynx.Except.tryWith,
    Lynx.Except.andAlso,bind,Except.bind] at proper
  all_goals repeat' (split at proper <;> try simp_all [Lynx.Term.true])
  all_goals simp_all [Erlang.erlang.«is_integer/1»,Erlang.erlang.«==/2»,Lynx.Term.true,Lynx.Term.false]
  all_goals repeat' (split at * <;> try simp_all [])
  all_goals try obtain ⟨out,replaced,missing⟩ := (by assumption : ∀ changed status, _) changed status rfl rfl
  all_goals try obtain ⟨out,replaced,missing⟩ := (by assumption : ∀ changed status, _) changed status
  all_goals simp_all [Elixir.HoldLedger.Ledger.«set_status/3»,Elixir.HoldLedger.Spec.«lookup/2»,
    Erlang.erlang.«==/2»]
  all_goals repeat' (split <;> try simp_all [])
  all_goals try simp_all [Elixir.HoldLedger.Spec.«lookup/2»,
    Erlang.erlang.«==/2»,Lynx.Term.compare_integers]
  all_goals repeat' (split <;> try simp_all [Elixir.HoldLedger.Spec.«lookup/2»,
    Erlang.erlang.«==/2»,Lynx.Term.compare_integers,Int.compare_eq_eq,bind,Except.bind])
  all_goals first | rfl | exact ⟨_,by assumption,by assumption⟩

/-- Restart marking likewise introduces no identity. -/
theorem mark_absent : ∀ entries (query : Int),
    Elixir.HoldLedger.Spec.«proper_entries?/1» entries = Except.ok Lynx.Term.true →
    Elixir.HoldLedger.Spec.«lookup/2» entries (.integer query) = Except.ok (.atom "not_found") →
    ∃ out, Elixir.HoldLedger.Ledger.«mark_unknown/1» entries = Except.ok out ∧
      Elixir.HoldLedger.Spec.«lookup/2» out (.integer query) = Except.ok (.atom "not_found") := by
  intro entries query proper absent
  fun_induction Elixir.HoldLedger.Spec.«lookup/2» entries (.integer query)
  all_goals simp only [Elixir.HoldLedger.Spec.«proper_entries?/1»,Lynx.Except.guard,Lynx.Except.tryWith,
    Lynx.Except.andAlso,bind,Except.bind] at proper
  all_goals repeat' (split at proper <;> try simp_all [Lynx.Term.true])
  all_goals simp_all [Erlang.erlang.«is_integer/1»,Erlang.erlang.«==/2»,Lynx.Term.true,Lynx.Term.false]
  all_goals repeat' (split at * <;> try simp_all [])
  all_goals try obtain ⟨out,marked,missing⟩ := (by assumption : _ → _ → ∃ _, _) rfl rfl
  all_goals try obtain ⟨out,marked,missing⟩ := (by assumption : ∃ _, _)
  all_goals simp_all [Elixir.HoldLedger.Ledger.«mark_unknown/1»,Elixir.HoldLedger.Spec.«lookup/2»]
  all_goals try unfold Elixir.HoldLedger.Ledger.«mark_unknown/1»
  all_goals repeat' (split <;> try simp_all [])
  all_goals try simp_all [Elixir.HoldLedger.Spec.«lookup/2»,
    Erlang.erlang.«==/2»]
  all_goals repeat' (split <;> try simp_all [])
  all_goals try grind [Lynx.Term.compare_integers,Int.compare_eq_eq]
  all_goals rename_i shape
  all_goals rcases shape with ⟨rfl,rfl⟩
  all_goals simp_all [Elixir.HoldLedger.Spec.«lookup/2»,Erlang.erlang.«==/2»,
    Lynx.Term.compare_integers]

@[expose] def At (entries : Lynx.Term) (key : Int) : Prop :=
  ∃ amount : Int, Elixir.HoldLedger.Spec.«lookup/2» entries (.integer key) =
    Except.ok (.tuple #[.atom "ok",.tuple #[.integer key,.integer amount,.atom "voiding"]])

theorem at_found (entries : Lynx.Term) (key amount : Int) (status : Lynx.Term)
    (found : Elixir.HoldLedger.Spec.«lookup/2» entries (.integer key) =
      Except.ok (.tuple #[.atom "ok",.tuple #[.integer key,.integer amount,status]])) :
    At entries key ↔ status = .atom "voiding" := by
  simp [At,found]

theorem at_absent (entries : Lynx.Term) (key : Int)
    (absent : Elixir.HoldLedger.Spec.«lookup/2» entries (.integer key) = Except.ok (.atom "not_found")) :
    ¬ At entries key := by simp [At,absent]

/-- A concrete status replacement changes voiding membership only for its key. -/
theorem set_frame (entries : Lynx.Term) (key amount : Int) (old status : Lynx.Term)
    (proper : Elixir.HoldLedger.Spec.«proper_entries?/1» entries = Except.ok Lynx.Term.true)
    (found : Elixir.HoldLedger.Spec.«lookup/2» entries (.integer key) =
      Except.ok (.tuple #[.atom "ok",.tuple #[.integer key,.integer amount,old]])) :
    ∃ out, Elixir.HoldLedger.Ledger.«set_status/3» entries (.integer key) status = Except.ok out ∧
      ∀ query, At out query ↔ (query = key ∧ status = .atom "voiding") ∨ (query ≠ key ∧ At entries query) := by
  obtain ⟨out,replaced,frame⟩ := replaced_3 entries key status proper
  refine ⟨out,replaced,?_⟩
  intro query
  by_cases same : query = key
  · subst query
    obtain ⟨actual,hm,hl⟩ := selected_status entries (.integer key) (.integer amount) old status proper found
    have equal : actual = out := Except.ok.inj (hm.symm.trans replaced)
    subst actual
    simp [at_found out key amount status hl]
  · rcases integer_lookup_shape entries query proper with ⟨_,absent⟩ | ⟨amount,previous,_,lookup,_⟩
    · obtain ⟨actual,hm,hl⟩ := set_absent entries key query status proper absent
      have equal : actual = out := Except.ok.inj (hm.symm.trans replaced)
      subst actual
      simp [same,at_absent entries query absent,at_absent out query hl]
    · obtain ⟨newer,located,unchanged | ⟨_,matched⟩⟩ := frame (.integer query) (.integer query) (.integer amount) previous lookup
      · simp [same,at_found entries query amount previous lookup,at_found out query amount newer located,unchanged]
      · have equal : key = query := by simpa [Lynx.Term.compare_integers,Int.compare_eq_eq] using matched
        exact False.elim (same equal.symm)

/-- Recovery marking preserves the exact set of voiding identities. -/
theorem mark_frame (entries : Lynx.Term)
    (proper : Elixir.HoldLedger.Spec.«proper_entries?/1» entries = Except.ok Lynx.Term.true) :
    ∃ out, Elixir.HoldLedger.Ledger.«mark_unknown/1» entries = Except.ok out ∧
      ∀ query, At out query ↔ At entries query := by
  obtain ⟨out,marked,frame⟩ := marked_3 entries proper
  refine ⟨out,marked,?_⟩
  intro query
  rcases integer_lookup_shape entries query proper with ⟨_,absent⟩ | ⟨amount,status,_,lookup,_⟩
  · obtain ⟨actual,hm,hl⟩ := mark_absent entries query proper absent
    have equal : actual = out := Except.ok.inj (hm.symm.trans marked)
    subst actual
    simp [at_absent entries query absent,at_absent out query hl]
  · obtain ⟨newer,located,unchanged | ⟨was_sent,new_unknown⟩⟩ := frame (.integer query) (.integer query) (.integer amount) status lookup
    · simp [at_found entries query amount status lookup,at_found out query amount newer located,unchanged]
    · simp [at_found entries query amount status lookup,at_found out query amount newer located,was_sent,new_unknown]

/-- The only changes to voiding membership are successful opening/confirmation. -/
@[expose] def Frame (before after event result : Lynx.Term) : Prop :=
  ∀ query : Int, At after query ↔
    (At before query ∧ ¬(event = .tuple #[.atom "void_confirmed",.integer query] ∧ result = .atom "voided")) ∨
    (event = .tuple #[.atom "void",.integer query] ∧ result = .atom "voiding")

theorem frame_passive (before after event result : Lynx.Term)
    (same : ∀ query, At after query ↔ At before query)
    (no_open : result ≠ .atom "voiding")
    (no_close : ∀ query, event ≠ .tuple #[.atom "void_confirmed",.integer query] ∨ result ≠ .atom "voided") :
    Frame before after event result := by
  intro query
  rw [same query]
  have none := no_close query
  rcases none with different | different <;> simp [different,no_open]

/-- Changing between non-voiding statuses preserves voiding membership. -/
theorem set_passive (entries : Lynx.Term) (key amount : Int) (old status : Lynx.Term)
    (proper : Elixir.HoldLedger.Spec.«proper_entries?/1» entries = Except.ok Lynx.Term.true)
    (found : Elixir.HoldLedger.Spec.«lookup/2» entries (.integer key) =
      Except.ok (.tuple #[.atom "ok",.tuple #[.integer key,.integer amount,old]]))
    (old_not_voiding : old ≠ .atom "voiding") (new_not_voiding : status ≠ .atom "voiding") :
    ∃ out, Elixir.HoldLedger.Ledger.«set_status/3» entries (.integer key) status = Except.ok out ∧
      ∀ query, At out query ↔ At entries query := by
  obtain ⟨out,replaced,frame⟩ := set_frame entries key amount old status proper found
  refine ⟨out,replaced,?_⟩
  intro query
  rw [frame query]
  by_cases same : query = key
  · subst query
    simp [new_not_voiding,at_found entries key amount old found,old_not_voiding]
  · simp [same,new_not_voiding]

@[expose] def Observed (before event output : Lynx.Term) : Prop :=
  ∃ next result effects entries,
    output = .tuple #[next,result,effects] ∧
    Erlang.erlang.«element/2» (.integer 5) next = Except.ok entries ∧
    Frame before entries event result

theorem observed_passive (al hl ua uh : Int) (before after event result effects : Lynx.Term)
    (same : ∀ query, At after query ↔ At before query)
    (no_open : result ≠ .atom "voiding")
    (no_close : ∀ query, event ≠ .tuple #[.atom "void_confirmed",.integer query] ∨ result ≠ .atom "voided") :
    Observed before event (.tuple #[.tuple #[.integer al,.integer hl,.integer ua,.integer uh,after],result,effects]) :=
  ⟨_,_,_,_,rfl,rfl,frame_passive before after event result same no_open no_close⟩

theorem fresh_frame (entries : Lynx.Term) (key amount : Int)
    (absent : Elixir.HoldLedger.Spec.«lookup/2» entries (.integer key) = Except.ok (.atom "not_found")) :
    ∀ query, At (.cons (.tuple #[.integer key,.integer amount,.atom "reserved"]) entries) query ↔ At entries query := by
  intro query
  by_cases same : query = key
  · subst query
    simp [At,Elixir.HoldLedger.Spec.«lookup/2»,Erlang.erlang.«==/2»,absent]
  · simp [At,Elixir.HoldLedger.Spec.«lookup/2»,Erlang.erlang.«==/2»,
      Lynx.Term.compare_integers,Ne.symm same]

theorem open_frame (entries : Lynx.Term) (key amount : Int)
    (proper : Elixir.HoldLedger.Spec.«proper_entries?/1» entries = Except.ok Lynx.Term.true)
    (found : Elixir.HoldLedger.Spec.«lookup/2» entries (.integer key) =
      Except.ok (.tuple #[.atom "ok",.tuple #[.integer key,.integer amount,.atom "authorized"]])) :
    ∃ out, Elixir.HoldLedger.Ledger.«set_status/3» entries (.integer key) (.atom "voiding") = Except.ok out ∧
      Frame entries out (.tuple #[.atom "void",.integer key]) (.atom "voiding") := by
  obtain ⟨out,replaced,frame⟩ := set_frame entries key amount (.atom "authorized") (.atom "voiding") proper found
  refine ⟨out,replaced,?_⟩
  intro query
  rw [frame query]
  by_cases same : query = key
  · subst query
    simp [at_found entries key amount (.atom "authorized") found]
  · simp [same,Ne.symm same]

theorem confirm_frame (entries : Lynx.Term) (key amount : Int)
    (proper : Elixir.HoldLedger.Spec.«proper_entries?/1» entries = Except.ok Lynx.Term.true)
    (found : Elixir.HoldLedger.Spec.«lookup/2» entries (.integer key) =
      Except.ok (.tuple #[.atom "ok",.tuple #[.integer key,.integer amount,.atom "voiding"]])) :
    ∃ out, Elixir.HoldLedger.Ledger.«set_status/3» entries (.integer key) (.atom "voided") = Except.ok out ∧
      Frame entries out (.tuple #[.atom "void_confirmed",.integer key]) (.atom "voided") := by
  obtain ⟨out,replaced,frame⟩ := set_frame entries key amount (.atom "voiding") (.atom "voided") proper found
  refine ⟨out,replaced,?_⟩
  intro query
  rw [frame query]
  by_cases same : query = key
  · subst query
    simp [at_found entries key amount (.atom "voiding") found]
  · simp [same,Ne.symm same]

theorem dispatch_observed (al hl ua uh : Int) (entries key output : Lynx.Term)
    (proper : Elixir.HoldLedger.Spec.«proper_entries?/1» entries = Except.ok Lynx.Term.true)
    (applied : Elixir.HoldLedger.Ledger.«dispatch/2»
      (.tuple #[.integer al,.integer hl,.integer ua,.integer uh,entries]) key = Except.ok output) :
    Observed entries (.tuple #[.atom "dispatch",key]) output := by
  cases key <;> try solve |
    simp [Elixir.HoldLedger.Ledger.«dispatch/2»,
      bind,Except.bind] at applied
    subst output
    apply observed_passive <;> intros <;> simp
  rename_i key
  rcases integer_lookup_shape entries key proper with ⟨absent,_⟩ | ⟨amount,status,found,lookup,_⟩
  · simp [Elixir.HoldLedger.Ledger.«dispatch/2»,absent] at applied
    subst output
    apply observed_passive <;> intros <;> simp
  · by_cases eligible : status = .atom "reserved"
    · subst status
      obtain ⟨out,changed,same⟩ := set_passive entries key amount (.atom "reserved") (.atom "sent") proper lookup (by simp) (by simp)
      simp [Elixir.HoldLedger.Ledger.«dispatch/2»,found,changed] at applied
      subst output
      apply observed_passive <;> intros <;> simp [same]
    · simp [Elixir.HoldLedger.Ledger.«dispatch/2»,found,eligible] at applied
      subst output
      apply observed_passive <;> intros <;> simp

theorem timeout_observed (al hl ua uh : Int) (entries key output : Lynx.Term)
    (proper : Elixir.HoldLedger.Spec.«proper_entries?/1» entries = Except.ok Lynx.Term.true)
    (applied : Elixir.HoldLedger.Ledger.«timeout/2»
      (.tuple #[.integer al,.integer hl,.integer ua,.integer uh,entries]) key = Except.ok output) :
    Observed entries (.tuple #[.atom "timeout",key]) output := by
  cases key <;> try solve |
    simp [Elixir.HoldLedger.Ledger.«timeout/2»,
      bind,Except.bind] at applied
    subst output
    apply observed_passive <;> intros <;> simp
  rename_i key
  rcases integer_lookup_shape entries key proper with ⟨absent,_⟩ | ⟨amount,status,found,lookup,_⟩
  · simp [Elixir.HoldLedger.Ledger.«timeout/2»,absent] at applied
    subst output
    apply observed_passive <;> intros <;> simp
  · by_cases eligible : status = .atom "sent"
    · subst status
      obtain ⟨out,changed,same⟩ := set_passive entries key amount (.atom "sent") (.atom "unknown") proper lookup (by simp) (by simp)
      simp [Elixir.HoldLedger.Ledger.«timeout/2»,found,changed] at applied
      subst output
      apply observed_passive <;> intros <;> simp [same]
    · simp [Elixir.HoldLedger.Ledger.«timeout/2»,found,eligible] at applied
      subst output
      apply observed_passive <;> intros <;> simp

theorem retry_observed (al hl ua uh : Int) (entries key output : Lynx.Term)
    (proper : Elixir.HoldLedger.Spec.«proper_entries?/1» entries = Except.ok Lynx.Term.true)
    (applied : Elixir.HoldLedger.Ledger.«retry/2»
      (.tuple #[.integer al,.integer hl,.integer ua,.integer uh,entries]) key = Except.ok output) :
    Observed entries (.tuple #[.atom "retry",key]) output := by
  cases key <;> try solve |
    simp [Elixir.HoldLedger.Ledger.«retry/2»,
      bind,Except.bind] at applied
    subst output
    apply observed_passive <;> intros <;> simp
  rename_i key
  rcases integer_lookup_shape entries key proper with ⟨absent,_⟩ | ⟨amount,status,found,lookup,_⟩
  · simp [Elixir.HoldLedger.Ledger.«retry/2»,absent] at applied
    subst output
    apply observed_passive <;> intros <;> simp
  · by_cases eligible : status = .atom "unknown"
    · subst status
      obtain ⟨out,changed,same⟩ := set_passive entries key amount (.atom "unknown") (.atom "sent") proper lookup (by simp) (by simp)
      simp [Elixir.HoldLedger.Ledger.«retry/2»,found,changed] at applied
      subst output
      apply observed_passive <;> intros <;> simp [same]
    · simp [Elixir.HoldLedger.Ledger.«retry/2»,found,eligible] at applied
      subst output
      apply observed_passive <;> intros <;> simp

theorem request_observed (al hl ua uh : Int) (entries key amount output : Lynx.Term)
    (proper : Elixir.HoldLedger.Spec.«proper_entries?/1» entries = Except.ok Lynx.Term.true)
    (applied : Elixir.HoldLedger.Ledger.«request/3»
      (.tuple #[.integer al,.integer hl,.integer ua,.integer uh,entries]) key amount = Except.ok output) :
    Observed entries (.tuple #[.atom "request",key,amount]) output := by
  cases key <;> try solve |
    simp [Elixir.HoldLedger.Ledger.«request/3»,Erlang.erlang.«is_integer/1»,
      Lynx.Except.guard,Lynx.Except.tryWith,bind,Except.bind] at applied
    subst output
    apply observed_passive <;> intros <;> simp
  cases amount <;> try solve |
    simp [Elixir.HoldLedger.Ledger.«request/3»,Erlang.erlang.«is_integer/1»,
      Lynx.Except.guard,Lynx.Except.tryWith,bind,Except.bind] at applied
    subst output
    apply observed_passive <;> intros <;> simp
  rename_i key amount
  rcases integer_lookup_shape entries key proper with ⟨absent,_⟩ | ⟨stored,status,found,_,_⟩
  all_goals simp [*,Elixir.HoldLedger.Ledger.«request/3»,Erlang.erlang.«is_integer/1»,
    Erlang.erlang.«>/2»,Erlang.erlang.«>=/2»,Erlang.erlang.«=:=/2»] at applied
  all_goals repeat' (split at applied <;> try simp_all [Lynx.Term.true])
  all_goals try simp only [Except.ok.injEq] at applied
  all_goals try subst output
  all_goals apply observed_passive
  all_goals try solve | intro query; rfl
  all_goals try solve | intros; simp
  all_goals intro query
  all_goals exact fresh_frame entries key amount (by assumption) query

theorem void_observed (al hl ua uh : Int) (entries key output : Lynx.Term)
    (proper : Elixir.HoldLedger.Spec.«proper_entries?/1» entries = Except.ok Lynx.Term.true)
    (applied : Elixir.HoldLedger.Ledger.«void/2»
      (.tuple #[.integer al,.integer hl,.integer ua,.integer uh,entries]) key = Except.ok output) :
    Observed entries (.tuple #[.atom "void",key]) output := by
  cases key <;> try solve |
    simp [Elixir.HoldLedger.Ledger.«void/2»,
      bind,Except.bind] at applied
    subst output
    apply observed_passive <;> intros <;> simp
  rename_i key
  rcases integer_lookup_shape entries key proper with ⟨absent,_⟩ | ⟨amount,status,found,lookup,_⟩
  · simp [Elixir.HoldLedger.Ledger.«void/2»,absent] at applied
    subst output
    apply observed_passive <;> intros <;> simp
  · by_cases reserved : status = .atom "reserved"
    · subst status
      obtain ⟨out,changed,same⟩ := set_passive entries key amount (.atom "reserved") (.atom "voided") proper lookup (by simp) (by simp)
      simp [Elixir.HoldLedger.Ledger.«void/2»,found,changed] at applied
      subst output
      apply observed_passive <;> intros <;> simp [same]
    · by_cases authorized : status = .atom "authorized"
      · subst status
        obtain ⟨out,changed,frame⟩ := open_frame entries key amount proper lookup
        simp [Elixir.HoldLedger.Ledger.«void/2»,found,changed] at applied
        subst output
        exact ⟨_,_,_,out,rfl,rfl,frame⟩
      · simp [Elixir.HoldLedger.Ledger.«void/2»,found,reserved,authorized] at applied
        subst output
        apply observed_passive <;> intros <;> simp

theorem void_confirmed_observed (al hl ua uh : Int) (entries key output : Lynx.Term)
    (proper : Elixir.HoldLedger.Spec.«proper_entries?/1» entries = Except.ok Lynx.Term.true)
    (applied : Elixir.HoldLedger.Ledger.«void_confirmed/2»
      (.tuple #[.integer al,.integer hl,.integer ua,.integer uh,entries]) key = Except.ok output) :
    Observed entries (.tuple #[.atom "void_confirmed",key]) output := by
  cases key <;> try solve |
    simp [Elixir.HoldLedger.Ledger.«void_confirmed/2»,
      bind,Except.bind] at applied
    subst output
    apply observed_passive <;> intros <;> simp
  rename_i key
  rcases integer_lookup_shape entries key proper with ⟨absent,_⟩ | ⟨amount,status,found,lookup,_⟩
  · simp [Elixir.HoldLedger.Ledger.«void_confirmed/2»,absent] at applied
    subst output
    apply observed_passive <;> intros <;> simp
  · by_cases voiding : status = .atom "voiding"
    · subst status
      obtain ⟨out,changed,frame⟩ := confirm_frame entries key amount proper lookup
      simp [Elixir.HoldLedger.Ledger.«void_confirmed/2»,found,changed] at applied
      subst output
      exact ⟨_,_,_,out,rfl,rfl,frame⟩
    · simp [Elixir.HoldLedger.Ledger.«void_confirmed/2»,found,voiding] at applied
      subst output
      apply observed_passive <;> intros <;> simp

theorem approved_observed (al hl ua uh : Int) (entries key output : Lynx.Term)
    (proper : Elixir.HoldLedger.Spec.«proper_entries?/1» entries = Except.ok Lynx.Term.true)
    (applied : Elixir.HoldLedger.Ledger.«processor_result/3»
      (.tuple #[.integer al,.integer hl,.integer ua,.integer uh,entries]) key (.atom "approved") = Except.ok output) :
    Observed entries (.tuple #[.atom "processor_result",key,.atom "approved"]) output := by
  cases key <;> try solve |
    simp [Elixir.HoldLedger.Ledger.«processor_result/3»,Erlang.erlang.«is_integer/1»,
      bind,Except.bind] at applied
    subst output
    apply observed_passive <;> intros <;> simp
  rename_i key
  rcases integer_lookup_shape entries key proper with ⟨absent,_⟩ | ⟨amount,status,found,lookup,_⟩
  · simp [Elixir.HoldLedger.Ledger.«processor_result/3»,absent,Erlang.erlang.«is_integer/1»] at applied
    subst output
    apply observed_passive <;> intros <;> simp
  · by_cases eligible : status = .atom "sent" ∨ status = .atom "unknown"
    · obtain ⟨out,changed,same⟩ := set_passive entries key amount status (.atom "authorized") proper lookup
        (by rcases eligible with rfl | rfl <;> simp) (by simp)
      rcases eligible with rfl | rfl
      all_goals simp [Elixir.HoldLedger.Ledger.«processor_result/3»,found,changed,Erlang.erlang.«is_integer/1»] at applied
      all_goals subst output
      all_goals apply observed_passive <;> intros <;> simp [same]
    · have not_sent : status ≠ .atom "sent" := by intro equal; exact eligible (Or.inl equal)
      have not_unknown : status ≠ .atom "unknown" := by intro equal; exact eligible (Or.inr equal)
      simp [Elixir.HoldLedger.Ledger.«processor_result/3»,found,not_sent,not_unknown,Erlang.erlang.«is_integer/1»] at applied
      subst output
      apply observed_passive <;> intros <;> simp

theorem declined_observed (al hl ua uh : Int) (entries key output : Lynx.Term)
    (proper : Elixir.HoldLedger.Spec.«proper_entries?/1» entries = Except.ok Lynx.Term.true)
    (applied : Elixir.HoldLedger.Ledger.«processor_result/3»
      (.tuple #[.integer al,.integer hl,.integer ua,.integer uh,entries]) key (.atom "declined") = Except.ok output) :
    Observed entries (.tuple #[.atom "processor_result",key,.atom "declined"]) output := by
  cases key <;> try solve |
    simp [Elixir.HoldLedger.Ledger.«processor_result/3»,Erlang.erlang.«is_integer/1»,
      bind,Except.bind] at applied
    subst output
    apply observed_passive <;> intros <;> simp
  rename_i key
  rcases integer_lookup_shape entries key proper with ⟨absent,_⟩ | ⟨amount,status,found,lookup,_⟩
  · simp [Elixir.HoldLedger.Ledger.«processor_result/3»,absent,Erlang.erlang.«is_integer/1»] at applied
    subst output
    apply observed_passive <;> intros <;> simp
  · by_cases eligible : status = .atom "sent" ∨ status = .atom "unknown"
    · obtain ⟨out,changed,same⟩ := set_passive entries key amount status (.atom "declined") proper lookup
        (by rcases eligible with rfl | rfl <;> simp) (by simp)
      rcases eligible with rfl | rfl
      all_goals simp [Elixir.HoldLedger.Ledger.«processor_result/3»,found,changed,Erlang.erlang.«is_integer/1»] at applied
      all_goals subst output
      all_goals apply observed_passive <;> intros <;> simp [same]
    · have not_sent : status ≠ .atom "sent" := by intro equal; exact eligible (Or.inl equal)
      have not_unknown : status ≠ .atom "unknown" := by intro equal; exact eligible (Or.inr equal)
      simp [Elixir.HoldLedger.Ledger.«processor_result/3»,found,not_sent,not_unknown,Erlang.erlang.«is_integer/1»] at applied
      subst output
      apply observed_passive <;> intros <;> simp

theorem processor_observed (al hl ua uh : Int) (entries key decision output : Lynx.Term)
    (proper : Elixir.HoldLedger.Spec.«proper_entries?/1» entries = Except.ok Lynx.Term.true)
    (applied : Elixir.HoldLedger.Ledger.«processor_result/3»
      (.tuple #[.integer al,.integer hl,.integer ua,.integer uh,entries]) key decision = Except.ok output) :
    Observed entries (.tuple #[.atom "processor_result",key,decision]) output := by
  by_cases approved : decision = .atom "approved"
  · subst decision
    exact approved_observed al hl ua uh entries key output proper applied
  · by_cases declined : decision = .atom "declined"
    · subst decision
      exact declined_observed al hl ua uh entries key output proper applied
    · cases key
      all_goals simp [Elixir.HoldLedger.Ledger.«processor_result/3»,approved,declined,Erlang.erlang.«is_integer/1»] at applied
      all_goals subst output
      all_goals apply observed_passive <;> intros <;> simp

/-- Event-by-event characterization of the actual translated reducer's voiding
    footprint. No native ledger transition is used. -/
theorem ledger_frame (state event next result effects : Lynx.Term)
    (valid : Elixir.HoldLedger.Spec.«valid?/1» state = Except.ok Lynx.Term.true)
    (applied : Elixir.HoldLedger.Ledger.«step/2» state event = Except.ok (.tuple #[next,result,effects])) :
    ∃ before after,
      Erlang.erlang.«element/2» (.integer 5) state = Except.ok before ∧
      Erlang.erlang.«element/2» (.integer 5) next = Except.ok after ∧
      Frame before after event result := by
  obtain ⟨al,hl,ua,uh,entries,rfl,proper,_,_,_,_,_,_,_,_,_⟩ := valid_view_1 state valid
  have output : Observed entries event (.tuple #[next,result,effects]) := by
    simp only [Elixir.HoldLedger.Ledger.«step/2»] at applied
    split at applied
    case h_1 ev key amount => exact request_observed al hl ua uh entries key amount _ proper applied
    case h_2 ev key => exact dispatch_observed al hl ua uh entries key _ proper applied
    case h_3 ev key => exact timeout_observed al hl ua uh entries key _ proper applied
    case h_4 =>
      obtain ⟨out,marked,same⟩ := mark_frame entries proper
      simp [Elixir.HoldLedger.Ledger.«restart/1»,marked] at applied
      obtain ⟨rfl,rfl,rfl⟩ := applied
      apply observed_passive <;> intros <;> simp [same]
    case h_5 ev key => exact retry_observed al hl ua uh entries key _ proper applied
    case h_6 ev key decision => exact processor_observed al hl ua uh entries key decision _ proper applied
    case h_7 ev key => exact void_observed al hl ua uh entries key _ proper applied
    case h_8 ev key => exact void_confirmed_observed al hl ua uh entries key _ proper applied
    case h_9 ev key =>
      cases key
      all_goals simp [Elixir.HoldLedger.Ledger.«transport_ack/2»] at applied
      all_goals obtain ⟨rfl,rfl,rfl⟩ := applied
      all_goals apply observed_passive <;> intros <;> simp
    case h_10 =>
      simp only [pure,Except.pure,Except.ok.injEq,Lynx.Term.tuple.injEq,Array.mk.injEq,List.cons.injEq,and_true] at applied
      obtain ⟨rfl,rfl,rfl⟩ := applied
      apply observed_passive <;> intros <;> simp
  obtain ⟨actual,res,fx,after,shape,located,frame⟩ := output
  simp only [Lynx.Term.tuple.injEq,Array.mk.injEq,List.cons.injEq,and_true] at shape
  obtain ⟨rfl,rfl,rfl⟩ := shape
  exact ⟨entries,after,rfl,located,frame⟩

@[expose] def EffectForm (entries event result effects : Lynx.Term) : Prop :=
  (effects = .nil ∧ result ≠ .atom "voiding") ∨
  (∃ key amount, effects = .cons (.tuple #[.atom "authorize",key,amount]) .nil ∧ result ≠ .atom "voiding") ∨
  (∃ (key amount : Int), event = .tuple #[.atom "void",.integer key] ∧ result = .atom "voiding" ∧
    effects = .cons (.tuple #[.atom "void",.integer key]) .nil ∧
    Elixir.HoldLedger.Spec.«lookup/2» entries (.integer key) =
      Except.ok (.tuple #[.atom "ok",.tuple #[.integer key,.integer amount,.atom "authorized"]]))

theorem effect_form (state event next result effects : Lynx.Term)
    (valid : Elixir.HoldLedger.Spec.«valid?/1» state = Except.ok Lynx.Term.true)
    (applied : Elixir.HoldLedger.Ledger.«step/2» state event = Except.ok (.tuple #[next,result,effects])) :
    ∃ entries, Erlang.erlang.«element/2» (.integer 5) state = Except.ok entries ∧
      EffectForm entries event result effects := by
  obtain ⟨al,hl,ua,uh,entries,rfl,proper,_,_,_,_,_,_,_,_,_⟩ := valid_view_1 state valid
  refine ⟨entries,rfl,?_⟩
  simp only [Elixir.HoldLedger.Ledger.«step/2»] at applied
  split at applied
  case h_7 ev key =>
    cases key <;> try solve |
      simp [Elixir.HoldLedger.Ledger.«void/2»,
        bind,Except.bind] at applied
      repeat' split_conjunction
      subst_vars
      exact Or.inl ⟨rfl,by simp⟩
    rename_i key
    rcases integer_lookup_shape entries key proper with ⟨absent,_⟩ | ⟨amount,status,found,lookup,known⟩
    · simp [Elixir.HoldLedger.Ledger.«void/2»,absent] at applied
      obtain ⟨rfl,rfl,rfl⟩ := applied
      exact Or.inl ⟨rfl,by simp⟩
    · by_cases reserved : status = .atom "reserved"
      all_goals by_cases authorized : status = .atom "authorized"
      all_goals simp [Elixir.HoldLedger.Ledger.«void/2»,found,reserved,authorized,
        bind,Except.bind] at applied
      all_goals repeat' (split at applied <;> try simp_all [EffectForm])
      all_goals repeat' split_conjunction
      all_goals subst_vars
      all_goals simp_all [EffectForm]
  all_goals try simp only [Elixir.HoldLedger.Ledger.«request/3»,Elixir.HoldLedger.Ledger.«dispatch/2»,
    Elixir.HoldLedger.Ledger.«timeout/2»,Elixir.HoldLedger.Ledger.«restart/1»,
    Elixir.HoldLedger.Ledger.«retry/2»,Elixir.HoldLedger.Ledger.«processor_result/3»,
    Elixir.HoldLedger.Ledger.«void_confirmed/2»,Elixir.HoldLedger.Ledger.«transport_ack/2»,
    Lynx.Except.guard,Lynx.Except.tryWith,bind,Except.bind] at applied
  all_goals repeat' (split at applied <;> try simp_all [EffectForm])
  all_goals try simp only [Except.ok.injEq, Lynx.Term.tuple.injEq, Array.mk.injEq, List.cons.injEq,  and_true] at applied
  all_goals rcases applied with ⟨rfl,rfl,rfl⟩
  all_goals simp [EffectForm]

end HoldLedgerProof.Voiding
