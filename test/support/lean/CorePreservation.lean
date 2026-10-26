module

public import Elixir.HoldLedger.ProofContracts
public import HoldLedgerProof.Induction
public import HoldLedgerProof.CoreLookup

public section
set_option maxHeartbeats 16000000

theorem HoldLedgerProof.replaced_1 : ∀ es k st seen,
    Elixir.HoldLedger.Spec.«unique_keys_seen?/2» es seen = Except.ok Lynx.Term.true →
    ∃ out, Elixir.HoldLedger.Ledger.«set_status/3» es k st = Except.ok out ∧
      ∀ q a old, Elixir.HoldLedger.Spec.«lookup/2» es q =
        Except.ok (Lynx.Term.tuple #[Lynx.Term.atom "ok", Lynx.Term.tuple #[q,a,old]]) →
        ∃ newer, Elixir.HoldLedger.Spec.«lookup/2» out q =
          Except.ok (Lynx.Term.tuple #[Lynx.Term.atom "ok", Lynx.Term.tuple #[q,a,newer]]) ∧
          (newer = old ∨ newer = st ∧ k.compare q = Ordering.eq) := by
  intro es k st seen h
  fun_induction Elixir.HoldLedger.Spec.«unique_keys_seen?/2» es seen generalizing k st
  all_goals try simp only [
     bind, Except.bind] at h
  all_goals repeat' (split at h <;> try simp_all [Lynx.Term.true])
  all_goals try simp_all [Elixir.HoldLedger.Ledger.«set_status/3»,
    Elixir.HoldLedger.Spec.«lookup/2», Erlang.erlang.«==/2»,
      bind, Except.bind,
    Lynx.Term.true, Lynx.Term.false]
  all_goals obtain ⟨out, hm, hu⟩ := (by assumption : ∀ k st : Lynx.Term, ∃ out : Lynx.Term,
    Elixir.HoldLedger.Ledger.«set_status/3» _ k st = Except.ok out ∧
    ∀ q a old : Lynx.Term, Elixir.HoldLedger.Spec.«lookup/2» _ q =
      Except.ok (Lynx.Term.tuple #[Lynx.Term.atom "ok", Lynx.Term.tuple #[q,a,old]]) →
      ∃ newer, Elixir.HoldLedger.Spec.«lookup/2» out q =
        Except.ok (Lynx.Term.tuple #[Lynx.Term.atom "ok", Lynx.Term.tuple #[q,a,newer]]) ∧
        (newer = old ∨ newer = st ∧ k.compare q = Ordering.eq)) k st
  all_goals simp only [hm]
  all_goals split
  all_goals refine ⟨_, rfl, ?_⟩
  all_goals intro q a old hl
  all_goals repeat' (split at hl <;> try simp_all [])
  all_goals try simp_all [Elixir.HoldLedger.Spec.«lookup/2», Erlang.erlang.«==/2»,
      Lynx.Term.true, Lynx.Term.false]
  all_goals repeat' (split <;> try simp_all [Lynx.Term.true, Lynx.Term.false])

  all_goals exact Or.inr (Std.OrientedCmp.eq_symm (cmp := Lynx.Term.compare) (by assumption))

theorem HoldLedgerProof.explained_1 : ∀ es seen dst ev,
    Elixir.HoldLedger.Spec.«unique_keys_seen?/2» es seen = Except.ok Lynx.Term.true →
    (∀ q a old, Elixir.HoldLedger.Spec.«seen?/2» seen q = Except.ok Lynx.Term.false →
      Elixir.HoldLedger.Spec.«lookup/2» es q =
        Except.ok (Lynx.Term.tuple #[Lynx.Term.atom "ok", Lynx.Term.tuple #[q,a,old]]) →
      ∃ newer, Elixir.HoldLedger.Spec.«lookup/2» dst q =
        Except.ok (Lynx.Term.tuple #[Lynx.Term.atom "ok", Lynx.Term.tuple #[q,a,newer]]) ∧
        (old = Lynx.Term.atom "authorized" ∨ newer ≠ Lynx.Term.atom "authorized" ∨
          ev = Lynx.Term.tuple #[Lynx.Term.atom "processor_result", q, Lynx.Term.atom "approved"] ∧
            (old = Lynx.Term.atom "sent" ∨ old = Lynx.Term.atom "unknown"))) →
    Elixir.HoldLedger.Spec.«authorizations_explained?/3» es dst ev = Except.ok Lynx.Term.true := by
  intro es seen dst ev h hmap
  fun_induction Elixir.HoldLedger.Spec.«unique_keys_seen?/2» es seen generalizing dst ev
  all_goals try simp only [ bind, Except.bind] at h
  all_goals repeat' (split at h <;> try simp_all [Lynx.Term.true, Lynx.Term.false])
  all_goals try simp_all [Elixir.HoldLedger.Spec.«authorizations_explained?/3»]
  rename_i seen n amount old rest x generated ih heq
  obtain ⟨newer, hlookup, hsafe⟩ := hmap (Lynx.Term.integer n) amount old heq
    (by simp [Elixir.HoldLedger.Spec.«lookup/2», Erlang.erlang.«==/2»])
  have htail : Elixir.HoldLedger.Spec.«authorizations_explained?/3» rest dst ev = Except.ok Lynx.Term.true := by
    apply ih dst ev
    intro q a old hs hl
    simp only [Elixir.HoldLedger.Spec.«seen?/2», Erlang.erlang.«==/2», bind, Except.bind] at hs
    by_cases he : (Lynx.Term.integer n).compare q = Ordering.eq
    · simp [he] at hs
    · have hs' : Elixir.HoldLedger.Spec.«seen?/2» seen q = Except.ok Lynx.Term.false := by
        simpa [he, Lynx.Term.false] using hs
      apply hmap q a old hs'
      simpa [Elixir.HoldLedger.Spec.«lookup/2», Erlang.erlang.«==/2»,
        bind, Except.bind, he] using hl
  rcases hsafe with hold | hnew | ⟨hevent, hold | hold⟩
  all_goals simp [
    Erlang.erlang.«=:=/2», Erlang.erlang.«==/2», Erlang.erlang.«/=/2», Erlang.erlang.«and/2»,
     Lynx.Except.tryWith, bind, Except.bind,
    Lynx.Term.true, Lynx.Term.false, HoldLedgerProof.compare_atoms, *]
  all_goals repeat' (split <;> try simp_all [Lynx.Term.true])

theorem HoldLedgerProof.marked_1 : ∀ es seen,
    Elixir.HoldLedger.Spec.«unique_keys_seen?/2» es seen = Except.ok Lynx.Term.true →
    ∃ out, Elixir.HoldLedger.Ledger.«mark_unknown/1» es = Except.ok out ∧
      ∀ q a old, Elixir.HoldLedger.Spec.«lookup/2» es q =
        Except.ok (Lynx.Term.tuple #[Lynx.Term.atom "ok", Lynx.Term.tuple #[q,a,old]]) →
        ∃ newer, Elixir.HoldLedger.Spec.«lookup/2» out q =
          Except.ok (Lynx.Term.tuple #[Lynx.Term.atom "ok", Lynx.Term.tuple #[q,a,newer]]) ∧
          (newer = old ∨ newer = Lynx.Term.atom "unknown") := by
  intro es seen h
  fun_induction Elixir.HoldLedger.Spec.«unique_keys_seen?/2» es seen
  all_goals try simp only [
     bind, Except.bind] at h
  all_goals repeat' (split at h <;> try simp_all [Lynx.Term.true])
  all_goals try simp_all [Elixir.HoldLedger.Ledger.«mark_unknown/1»,
    Elixir.HoldLedger.Spec.«lookup/2», Erlang.erlang.«==/2»,
      Lynx.Term.true, Lynx.Term.false]
  all_goals obtain ⟨out, hm, hu⟩ := (by assumption : ∃ out : Lynx.Term,
    Elixir.HoldLedger.Ledger.«mark_unknown/1» _ = Except.ok out ∧
    ∀ q a old : Lynx.Term, Elixir.HoldLedger.Spec.«lookup/2» _ q =
      Except.ok (Lynx.Term.tuple #[Lynx.Term.atom "ok", Lynx.Term.tuple #[q,a,old]]) →
      ∃ newer, Elixir.HoldLedger.Spec.«lookup/2» out q =
        Except.ok (Lynx.Term.tuple #[Lynx.Term.atom "ok", Lynx.Term.tuple #[q,a,newer]]) ∧
        (newer = old ∨ newer = Lynx.Term.atom "unknown"))
  all_goals try simp only [Elixir.HoldLedger.Ledger.«mark_unknown/1», hm, bind, Except.bind]
  all_goals repeat' (split <;> try simp_all [Lynx.Term.true, Lynx.Term.false])
  all_goals unfold Elixir.HoldLedger.Ledger.«mark_unknown/1»
  all_goals repeat' (split <;> try simp_all [])
  all_goals intro q a old hl
  all_goals repeat' (split at hl <;> try simp_all [])
  all_goals try simp_all [Elixir.HoldLedger.Spec.«lookup/2», Erlang.erlang.«==/2»,
      Lynx.Term.true, Lynx.Term.false]
  all_goals repeat' (split <;> try simp_all [Lynx.Term.true, Lynx.Term.false])
  all_goals obtain ⟨he, ht⟩ := (by assumption : Lynx.Term.tuple _ = _ ∧ _ = _)
  all_goals rw [← he]
  all_goals simp_all [Elixir.HoldLedger.Spec.«lookup/2», Erlang.erlang.«==/2»]

theorem HoldLedgerProof.reflexive_1 : ∀ es ev,
    Elixir.HoldLedger.Spec.«unique_keys_seen?/2» es Lynx.Term.nil = Except.ok Lynx.Term.true →
    Elixir.HoldLedger.Spec.«authorizations_explained?/3» es es ev = Except.ok Lynx.Term.true := by
  intro es ev hu
  apply HoldLedgerProof.explained_1 es Lynx.Term.nil es ev hu
  intro q a old _ hl
  refine ⟨old, hl, ?_⟩
  by_cases h : old = Lynx.Term.atom "authorized"
  · exact Or.inl h
  · exact Or.inr (Or.inl h)

theorem HoldLedgerProof.nonauthorized_1 : ∀ es k st ev,
    Elixir.HoldLedger.Spec.«unique_keys_seen?/2» es Lynx.Term.nil = Except.ok Lynx.Term.true →
    st ≠ Lynx.Term.atom "authorized" →
    ∃ out, Elixir.HoldLedger.Ledger.«set_status/3» es k st = Except.ok out ∧
      Elixir.HoldLedger.Spec.«authorizations_explained?/3» es out ev = Except.ok Lynx.Term.true := by
  intro es k st ev hu hs
  obtain ⟨out, hm, hmap⟩ := HoldLedgerProof.replaced_1 es k st Lynx.Term.nil hu
  refine ⟨out, hm, HoldLedgerProof.explained_1 es Lynx.Term.nil out ev hu ?_⟩
  intro q a old _ hl
  obtain ⟨newer, hn, he | ⟨he, _⟩⟩ := hmap q a old hl
  · refine ⟨newer, hn, ?_⟩
    by_cases h : old = Lynx.Term.atom "authorized"
    · exact Or.inl h
    · exact Or.inr (Or.inl (he ▸ h))
  · exact ⟨newer, hn, Or.inr (Or.inl (he ▸ hs))⟩

theorem HoldLedgerProof.marked_safe_1 : ∀ es ev,
    Elixir.HoldLedger.Spec.«unique_keys_seen?/2» es Lynx.Term.nil = Except.ok Lynx.Term.true →
    ∃ out, Elixir.HoldLedger.Ledger.«mark_unknown/1» es = Except.ok out ∧
      Elixir.HoldLedger.Spec.«authorizations_explained?/3» es out ev = Except.ok Lynx.Term.true := by
  intro es ev hu
  obtain ⟨out, hm, hmap⟩ := HoldLedgerProof.marked_1 es Lynx.Term.nil hu
  refine ⟨out, hm, HoldLedgerProof.explained_1 es Lynx.Term.nil out ev hu ?_⟩
  intro q a old _ hl
  obtain ⟨newer, hn, he | he⟩ := hmap q a old hl
  · refine ⟨newer, hn, ?_⟩
    by_cases h : old = Lynx.Term.atom "authorized"
    · exact Or.inl h
    · exact Or.inr (Or.inl (he ▸ h))
  · exact ⟨newer, hn, Or.inr (Or.inl (by simp [he]))⟩

theorem HoldLedgerProof.fresh_2 : ∀ es (k : Int) amount ev,
    Elixir.HoldLedger.Spec.«unique_keys_seen?/2» es Lynx.Term.nil = Except.ok Lynx.Term.true →
    Elixir.HoldLedger.Spec.«lookup/2» es (Lynx.Term.integer k) = Except.ok (Lynx.Term.atom "not_found") →
    Elixir.HoldLedger.Spec.«authorizations_explained?/3» es
      (Lynx.Term.cons (Lynx.Term.tuple #[Lynx.Term.integer k, amount, Lynx.Term.atom "reserved"]) es) ev =
        Except.ok Lynx.Term.true := by
  intro es k amount ev hu hf
  apply HoldLedgerProof.explained_1 es Lynx.Term.nil _ ev hu
  intro q a old _ hl
  obtain ⟨n, rfl⟩ := HoldLedgerProof.integer_key_1 es Lynx.Term.nil q a old hu hl
  by_cases he : k = n
  · subst n
    simp_all
  · refine ⟨old, ?_, ?_⟩
    · simpa [Elixir.HoldLedger.Spec.«lookup/2», Erlang.erlang.«==/2»,
        bind, Except.bind, Int.compare_eq_eq, he] using hl
    · by_cases h : old = Lynx.Term.atom "authorized"
      · exact Or.inl h
      · exact Or.inr (Or.inl h)

theorem HoldLedgerProof.authorized_1 : ∀ es (k : Int) ek amount old,
    Elixir.HoldLedger.Spec.«unique_keys_seen?/2» es Lynx.Term.nil = Except.ok Lynx.Term.true →
    Elixir.HoldLedger.Spec.«lookup/2» es (Lynx.Term.integer k) =
      Except.ok (Lynx.Term.tuple #[Lynx.Term.atom "ok", Lynx.Term.tuple #[ek,amount,old]]) →
    (old = Lynx.Term.atom "sent" ∨ old = Lynx.Term.atom "unknown") →
    ∃ out, Elixir.HoldLedger.Ledger.«set_status/3» es (Lynx.Term.integer k) (Lynx.Term.atom "authorized") = Except.ok out ∧
      Elixir.HoldLedger.Spec.«authorizations_explained?/3» es out
        (Lynx.Term.tuple #[Lynx.Term.atom "processor_result", Lynx.Term.integer k, Lynx.Term.atom "approved"]) =
          Except.ok Lynx.Term.true := by
  intro es k ek amount old hu hl hs
  obtain ⟨out, hm, hmap⟩ := HoldLedgerProof.replaced_1 es (Lynx.Term.integer k) (Lynx.Term.atom "authorized") Lynx.Term.nil hu
  refine ⟨out, hm, HoldLedgerProof.explained_1 es Lynx.Term.nil out _ hu ?_⟩
  intro q a original _ hq
  obtain ⟨newer, hn, he | ⟨he, hk⟩⟩ := hmap q a original hq
  · refine ⟨newer, hn, ?_⟩
    by_cases h : original = Lynx.Term.atom "authorized"
    · exact Or.inl h
    · exact Or.inr (Or.inl (he ▸ h))
  · obtain ⟨n, rfl⟩ := HoldLedgerProof.integer_key_1 es Lynx.Term.nil q a original hu hq
    have eqkey : k = n := by simpa [Int.compare_eq_eq] using hk
    subst n
    refine ⟨newer, hn, Or.inr (Or.inr ⟨rfl, ?_⟩)⟩
    have eqentry := hq.symm.trans hl
    simp_all

theorem HoldLedgerProof.replaced_2 : ∀ es k st seen,
    Elixir.HoldLedger.Spec.«unique_keys_seen?/2» es seen = Except.ok Lynx.Term.true →
    ∃ out, Elixir.HoldLedger.Ledger.«set_status/3» es k st = Except.ok out ∧
      ∀ q a old, Elixir.HoldLedger.Spec.«lookup/2» es q =
        Except.ok (Lynx.Term.tuple #[Lynx.Term.atom "ok", Lynx.Term.tuple #[q,a,old]]) →
        ∃ newer, Elixir.HoldLedger.Spec.«lookup/2» out q =
          Except.ok (Lynx.Term.tuple #[Lynx.Term.atom "ok", Lynx.Term.tuple #[q,a,newer]]) := by
  intro es k st seen h
  fun_induction Elixir.HoldLedger.Spec.«unique_keys_seen?/2» es seen generalizing k st
  all_goals try simp only [
     bind, Except.bind] at h
  all_goals repeat' (split at h <;> try simp_all [Lynx.Term.true])
  all_goals try simp_all [Elixir.HoldLedger.Ledger.«set_status/3»,
    Elixir.HoldLedger.Spec.«lookup/2», Erlang.erlang.«==/2»,
      bind, Except.bind,
    Lynx.Term.true, Lynx.Term.false]
  all_goals obtain ⟨out, hm, hu⟩ := (by assumption : ∀ k st : Lynx.Term, ∃ out : Lynx.Term,
    Elixir.HoldLedger.Ledger.«set_status/3» _ k st = Except.ok out ∧
    ∀ q a old : Lynx.Term, Elixir.HoldLedger.Spec.«lookup/2» _ q =
      Except.ok (Lynx.Term.tuple #[Lynx.Term.atom "ok", Lynx.Term.tuple #[q,a,old]]) →
      ∃ newer, Elixir.HoldLedger.Spec.«lookup/2» out q =
        Except.ok (Lynx.Term.tuple #[Lynx.Term.atom "ok", Lynx.Term.tuple #[q,a,newer]])) k st
  all_goals simp only [hm]
  all_goals split
  all_goals refine ⟨_, rfl, ?_⟩
  all_goals intro q a old hl
  all_goals repeat' (split at hl <;> try simp_all [])
  all_goals try simp_all [Elixir.HoldLedger.Spec.«lookup/2», Erlang.erlang.«==/2»,
      Lynx.Term.true, Lynx.Term.false]
  all_goals repeat' (split <;> try simp_all [Lynx.Term.true, Lynx.Term.false])

theorem HoldLedgerProof.identities_1 : ∀ es seen dst,
    Elixir.HoldLedger.Spec.«unique_keys_seen?/2» es seen = Except.ok Lynx.Term.true →
    (∀ q a old, Elixir.HoldLedger.Spec.«seen?/2» seen q = Except.ok Lynx.Term.false →
      Elixir.HoldLedger.Spec.«lookup/2» es q =
        Except.ok (Lynx.Term.tuple #[Lynx.Term.atom "ok", Lynx.Term.tuple #[q,a,old]]) →
      ∃ newer, Elixir.HoldLedger.Spec.«lookup/2» dst q =
        Except.ok (Lynx.Term.tuple #[Lynx.Term.atom "ok", Lynx.Term.tuple #[q,a,newer]])) →
    Elixir.HoldLedger.Spec.«identities_present?/2» es dst = Except.ok Lynx.Term.true := by
  intro es seen dst h hmap
  fun_induction Elixir.HoldLedger.Spec.«unique_keys_seen?/2» es seen generalizing dst
  all_goals try simp only [
    bind, Except.bind] at h
  all_goals repeat' (split at h <;> try simp_all [Lynx.Term.true, Lynx.Term.false])
  all_goals try simp_all [Elixir.HoldLedger.Spec.«identities_present?/2»]
  rename_i seen n amount old rest x generated ih heq
  obtain ⟨newer, hlookup⟩ := hmap (Lynx.Term.integer n) amount old heq
    (by simp [Elixir.HoldLedger.Spec.«lookup/2», Erlang.erlang.«==/2»])
  have htail : Elixir.HoldLedger.Spec.«identities_present?/2» rest dst = Except.ok Lynx.Term.true := by
    apply ih dst
    intro q a old hs hl
    simp only [Elixir.HoldLedger.Spec.«seen?/2», Erlang.erlang.«==/2», bind, Except.bind] at hs
    by_cases he : (Lynx.Term.integer n).compare q = Ordering.eq
    · simp [he] at hs
    · have hs' : Elixir.HoldLedger.Spec.«seen?/2» seen q = Except.ok Lynx.Term.false := by
        simpa [he, Lynx.Term.false] using hs
      apply hmap q a old hs'
      simpa [Elixir.HoldLedger.Spec.«lookup/2», Erlang.erlang.«==/2»,
        bind, Except.bind, he] using hl
  simp [hlookup, htail, Erlang.erlang.«=:=/2», Erlang.erlang.«and/2»]

theorem HoldLedgerProof.marked_2 : ∀ es seen,
    Elixir.HoldLedger.Spec.«unique_keys_seen?/2» es seen = Except.ok Lynx.Term.true →
    ∃ out, Elixir.HoldLedger.Ledger.«mark_unknown/1» es = Except.ok out ∧
      ∀ q a old, Elixir.HoldLedger.Spec.«lookup/2» es q =
        Except.ok (Lynx.Term.tuple #[Lynx.Term.atom "ok", Lynx.Term.tuple #[q,a,old]]) →
        ∃ newer, Elixir.HoldLedger.Spec.«lookup/2» out q =
          Except.ok (Lynx.Term.tuple #[Lynx.Term.atom "ok", Lynx.Term.tuple #[q,a,newer]]) := by
  intro es seen h
  fun_induction Elixir.HoldLedger.Spec.«unique_keys_seen?/2» es seen
  all_goals try simp only [
     bind, Except.bind] at h
  all_goals repeat' (split at h <;> try simp_all [Lynx.Term.true])
  all_goals try simp_all [Elixir.HoldLedger.Ledger.«mark_unknown/1»,
    Elixir.HoldLedger.Spec.«lookup/2», Erlang.erlang.«==/2»,
      Lynx.Term.true, Lynx.Term.false]
  all_goals obtain ⟨out, hm, hu⟩ := (by assumption : ∃ out : Lynx.Term,
    Elixir.HoldLedger.Ledger.«mark_unknown/1» _ = Except.ok out ∧
    ∀ q a old : Lynx.Term, Elixir.HoldLedger.Spec.«lookup/2» _ q =
      Except.ok (Lynx.Term.tuple #[Lynx.Term.atom "ok", Lynx.Term.tuple #[q,a,old]]) →
      ∃ newer, Elixir.HoldLedger.Spec.«lookup/2» out q =
        Except.ok (Lynx.Term.tuple #[Lynx.Term.atom "ok", Lynx.Term.tuple #[q,a,newer]]))
  all_goals try simp only [Elixir.HoldLedger.Ledger.«mark_unknown/1», hm, bind, Except.bind]
  all_goals repeat' (split <;> try simp_all [Lynx.Term.true, Lynx.Term.false])
  all_goals unfold Elixir.HoldLedger.Ledger.«mark_unknown/1»
  all_goals repeat' (split <;> try simp_all [])
  all_goals intro q a old hl
  all_goals repeat' (split at hl <;> try simp_all [])
  all_goals try simp_all [Elixir.HoldLedger.Spec.«lookup/2», Erlang.erlang.«==/2»,
      Lynx.Term.true, Lynx.Term.false]
  all_goals repeat' (split <;> try simp_all [Lynx.Term.true, Lynx.Term.false])
  all_goals obtain ⟨he, ht⟩ := (by assumption : Lynx.Term.tuple _ = _ ∧ _ = _)
  all_goals rw [← he]
  all_goals simp_all [Elixir.HoldLedger.Spec.«lookup/2», Erlang.erlang.«==/2»]

theorem HoldLedgerProof.fresh_3 : ∀ es (k : Int) amount,
    Elixir.HoldLedger.Spec.«unique_keys_seen?/2» es Lynx.Term.nil = Except.ok Lynx.Term.true →
    Elixir.HoldLedger.Spec.«lookup/2» es (Lynx.Term.integer k) = Except.ok (Lynx.Term.atom "not_found") →
    Elixir.HoldLedger.Spec.«identities_present?/2» es
      (Lynx.Term.cons (Lynx.Term.tuple #[Lynx.Term.integer k, amount, Lynx.Term.atom "reserved"]) es) =
        Except.ok Lynx.Term.true := by
  intro es k amount hu hf
  apply HoldLedgerProof.identities_1 es Lynx.Term.nil _ hu
  intro q a old _ hl
  obtain ⟨n, rfl⟩ := HoldLedgerProof.integer_key_1 es Lynx.Term.nil q a old hu hl
  by_cases he : k = n
  · subst n
    simp_all
  · refine ⟨old, ?_⟩
    simpa [Elixir.HoldLedger.Spec.«lookup/2», Erlang.erlang.«==/2»,
      bind, Except.bind, Int.compare_eq_eq, he] using hl

theorem HoldLedgerProof.clearing_1 : ∀ es, Elixir.HoldLedger.Spec.«proper_entries?/1» es = Except.ok Lynx.Term.true →
    ∃ out, Elixir.HoldLedger.Ledger.«mark_unknown/1» es = Except.ok out ∧
      Elixir.HoldLedger.Spec.«no_sent?/1» out = Except.ok Lynx.Term.true := by
  intro es h
  fun_induction Elixir.HoldLedger.Ledger.«mark_unknown/1» es
  all_goals simp only [Elixir.HoldLedger.Spec.«proper_entries?/1»,
    Lynx.Except.guard, Lynx.Except.tryWith, bind, Except.bind] at h
  all_goals repeat' (split at h <;> try simp_all [Lynx.Term.true])
  all_goals try simp_all [ Elixir.HoldLedger.Spec.«no_sent?/1»]
  all_goals repeat' (split at * <;> try simp_all [Lynx.Term.true, Lynx.Term.false])
  all_goals obtain ⟨out, hm, hn⟩ := (by assumption : ∃ out : Lynx.Term, _ ∧ _)
  all_goals try simp_all [ Elixir.HoldLedger.Spec.«no_sent?/1»]
  all_goals repeat' (split <;> try simp_all)

theorem HoldLedgerProof.replaced_3 : ∀ es (k : Int) to,
    Elixir.HoldLedger.Spec.«proper_entries?/1» es = Except.ok Lynx.Term.true →
    ∃ out, Elixir.HoldLedger.Ledger.«set_status/3» es (Lynx.Term.integer k) to = Except.ok out ∧
      ∀ query stored a old, Elixir.HoldLedger.Spec.«lookup/2» es query =
        Except.ok (Lynx.Term.tuple #[Lynx.Term.atom "ok", Lynx.Term.tuple #[stored,a,old]]) →
        ∃ newer, Elixir.HoldLedger.Spec.«lookup/2» out query =
          Except.ok (Lynx.Term.tuple #[Lynx.Term.atom "ok", Lynx.Term.tuple #[stored,a,newer]]) ∧
          (newer = old ∨ newer = to ∧ (Lynx.Term.integer k).compare query = Ordering.eq) := by
  intro es k to hp
  fun_induction Elixir.HoldLedger.Spec.«proper_entries?/1» es generalizing k to
  case case1 => simp [Elixir.HoldLedger.Ledger.«set_status/3», Elixir.HoldLedger.Spec.«lookup/2»]
  case case2 es hnil ih =>
    simp only [Lynx.Except.guard, Lynx.Except.tryWith, bind, Except.bind] at hp
    all_goals repeat' (split at hp <;> try simp_all [Lynx.Term.true])
    all_goals simp_all [Erlang.erlang.«is_integer/1», Lynx.Term.true, Lynx.Term.false]
    all_goals repeat' (split at * <;> try simp_all [])
    all_goals try obtain ⟨out, hm, hmap⟩ := ih k to
    all_goals try obtain ⟨out, hm, hmap⟩ := ih k to (by assumption)
    all_goals simp only [Elixir.HoldLedger.Ledger.«set_status/3», Erlang.erlang.«==/2», bind, Except.bind]
    all_goals split
    all_goals simp_all []
    all_goals repeat' split_conjunction
    all_goals subst_vars
    all_goals try refine ⟨_, rfl, ?_⟩
    all_goals intro query stored a old hq
    all_goals simp only [Elixir.HoldLedger.Spec.«lookup/2», Erlang.erlang.«==/2», bind, Except.bind] at hq
    all_goals repeat' (split at hq <;> try simp_all [Lynx.Term.true, Lynx.Term.false])
    all_goals repeat' split_conjunction
    all_goals subst_vars
    all_goals try simp_all [Elixir.HoldLedger.Spec.«lookup/2», Erlang.erlang.«==/2»]
    all_goals repeat' (split <;> try simp_all [Lynx.Term.true, Lynx.Term.false])
    all_goals try (apply hmap; assumption)
    all_goals try solve_by_elim (maxDepth := 20)

theorem HoldLedgerProof.marked_3 : ∀ es,
    Elixir.HoldLedger.Spec.«proper_entries?/1» es = Except.ok Lynx.Term.true →
    ∃ out, Elixir.HoldLedger.Ledger.«mark_unknown/1» es = Except.ok out ∧
      ∀ query stored a old, Elixir.HoldLedger.Spec.«lookup/2» es query =
        Except.ok (Lynx.Term.tuple #[Lynx.Term.atom "ok", Lynx.Term.tuple #[stored,a,old]]) →
        ∃ newer, Elixir.HoldLedger.Spec.«lookup/2» out query =
          Except.ok (Lynx.Term.tuple #[Lynx.Term.atom "ok", Lynx.Term.tuple #[stored,a,newer]]) ∧
          (newer = old ∨ old = Lynx.Term.atom "sent" ∧ newer = Lynx.Term.atom "unknown") := by
  intro es hp
  fun_induction Elixir.HoldLedger.Spec.«proper_entries?/1» es
  case case1 => simp [Elixir.HoldLedger.Ledger.«mark_unknown/1», Elixir.HoldLedger.Spec.«lookup/2»]
  case case2 es hnil ih =>
    simp only [Lynx.Except.guard, Lynx.Except.tryWith, bind, Except.bind] at hp
    all_goals repeat' (split at hp <;> try simp_all [Lynx.Term.true])
    all_goals simp_all [Erlang.erlang.«is_integer/1», Lynx.Term.true, Lynx.Term.false]
    all_goals repeat' (split at * <;> try simp_all [])
    all_goals try obtain ⟨out, hm, hmap⟩ := ih
    all_goals try obtain ⟨out, hm, hmap⟩ := ih (by assumption)
    all_goals simp only [Elixir.HoldLedger.Spec.«known_status?/1», Elixir.HoldLedger.Spec.«holding?/1», Elixir.HoldLedger.Spec.«terminal?/1»] at *
    all_goals repeat' (split at * <;> try simp_all [])
    all_goals try unfold Elixir.HoldLedger.Ledger.«mark_unknown/1»
    all_goals try simp only [hm, bind, Except.bind]
    all_goals repeat' (split <;> try simp_all [])
    all_goals try refine ⟨_, rfl, ?_⟩
    all_goals intro query stored a old hq
    all_goals try simp only [Elixir.HoldLedger.Spec.«lookup/2», Erlang.erlang.«==/2», bind, Except.bind] at hq
    all_goals repeat' (split at hq <;> try simp_all [Lynx.Term.true, Lynx.Term.false])
    all_goals repeat' split_conjunction
    all_goals subst_vars
    all_goals try simp_all [Elixir.HoldLedger.Spec.«lookup/2», Erlang.erlang.«==/2»]
    all_goals repeat' (split <;> try simp_all [])
    all_goals try (apply hmap; assumption)
    all_goals try solve_by_elim (maxDepth := 20)
