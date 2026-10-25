module

public import Elixir.HoldLedger.ProofContracts
public import HoldLedgerProof.Induction
public import HoldLedgerProof.CoreAccounting
public import HoldLedgerProof.CoreLookup
public import HoldLedgerProof.CoreShape
public import HoldLedgerProof.CoreStructure

public section
set_option maxHeartbeats 16000000
namespace Elixir.HoldLedger.ProofContracts

theorem «po_b1_dispatch/2» (s key : Lynx.Term)
    (requires : «po_b1_dispatch:requires/2» s key = Except.ok Lynx.Term.true) :
    «po_b1_dispatch:ensures/2» s key = Except.ok Lynx.Term.true := by
  have totals := HoldLedgerProof.totals_1
  have valid_view := HoldLedgerProof.valid_view_1
  have delta := HoldLedgerProof.delta_2
  have structural := HoldLedgerProof.structural_1
  have lookup_shape := HoldLedgerProof.lookup_shape_2
  have hv : Elixir.HoldLedger.Spec.«valid?/1» s = Except.ok Lynx.Term.true := requires
  obtain ⟨al, hl, ua, uh, es, rfl, hp, hu, ha, hc, hal, hhl, hua, huh, hacap, hhcap⟩ := valid_view s hv
  have changing : ∀ ek a old,
      Elixir.HoldLedger.Ledger.«find/2» es key = Except.ok (Lynx.Term.tuple #[Lynx.Term.atom "ok", Lynx.Term.tuple #[ek, Lynx.Term.integer a, old]]) →
      old = Lynx.Term.atom "reserved" →
      ∃ out, Elixir.HoldLedger.Ledger.«set_status/3» es key (Lynx.Term.atom "sent") = Except.ok out ∧
      Elixir.HoldLedger.Spec.«valid?/1» (Lynx.Term.tuple #[Lynx.Term.integer al, Lynx.Term.integer hl, Lynx.Term.integer ua, Lynx.Term.integer uh, out]) = Except.ok Lynx.Term.true := by
    intro ek a old hk ho
    subst old
    obtain ⟨out, ba, bc, aa, ac, hm, hba, hbc, haa, hac, hea, hec⟩ := delta es key ek a (Lynx.Term.atom "reserved") (Lynx.Term.atom "sent") hp hk
    obtain ⟨out2, hm2, hp2, hl2, hu2⟩ := structural es key (Lynx.Term.atom "sent") hp (by rfl)
    clear requires totals valid_view delta structural lookup_shape hv
    simp_all [HoldLedgerProof.held, Elixir.HoldLedger.Spec.«valid?/1», Elixir.HoldLedger.Spec.«nonnegative_state_valid?/5», Elixir.HoldLedger.Spec.«unique_keys?/1»,
      Erlang.erlang.«is_integer/1», Erlang.erlang.«==/2»,
      Lynx.Except.guard, Lynx.Except.tryWith, bind, Except.bind, Lynx.Term.true, Lynx.Term.false]
    all_goals repeat' (split at * <;> try simp_all [Lynx.Term.true, Lynx.Term.false])
  have shape := lookup_shape es key hp
  clear requires totals valid_view delta structural lookup_shape
  cases key <;> try simp [«po_b1_dispatch:ensures/2», Elixir.HoldLedger.Ledger.«dispatch/2»,
    Erlang.erlang.«element/2», Erlang.erlang.«is_integer/1»,
    Lynx.Except.guard, Lynx.Except.tryWith, bind, Except.bind, hv]
  rcases shape with hn | ⟨ek, a, st, hk, hs⟩
  · simp [«po_b1_dispatch:ensures/2», Elixir.HoldLedger.Ledger.«dispatch/2», hn,
      Erlang.erlang.«element/2», Erlang.erlang.«is_integer/1»,
      Lynx.Except.guard, Lynx.Except.tryWith, bind, Except.bind, hv]
  · simp only [Elixir.HoldLedger.Spec.«known_status?/1», Elixir.HoldLedger.Spec.«holding?/1», Elixir.HoldLedger.Spec.«terminal?/1»] at hs
    repeat' (split at hs <;> try simp_all [Lynx.Term.true, Lynx.Term.false])
    all_goals subst_vars
    all_goals try first
      | obtain ⟨out, hm, hvo⟩ := changing _ _ _ hk rfl
      | obtain ⟨out, hm, hvo⟩ := changing rfl
      | obtain ⟨out, hm, hvo⟩ := changing
    all_goals try simp_all [«po_b1_dispatch:ensures/2», Elixir.HoldLedger.Ledger.«dispatch/2»,
      Erlang.erlang.«element/2», Erlang.erlang.«is_integer/1»,
      Lynx.Except.guard, Lynx.Except.tryWith, bind, Except.bind]

theorem «po_b1_timeout/2» (s key : Lynx.Term)
    (requires : «po_b1_timeout:requires/2» s key = Except.ok Lynx.Term.true) :
    «po_b1_timeout:ensures/2» s key = Except.ok Lynx.Term.true := by
  have totals := HoldLedgerProof.totals_1
  have valid_view := HoldLedgerProof.valid_view_1
  have delta := HoldLedgerProof.delta_2
  have structural := HoldLedgerProof.structural_1
  have lookup_shape := HoldLedgerProof.lookup_shape_2
  have hv : Elixir.HoldLedger.Spec.«valid?/1» s = Except.ok Lynx.Term.true := requires
  obtain ⟨al, hl, ua, uh, es, rfl, hp, hu, ha, hc, hal, hhl, hua, huh, hacap, hhcap⟩ := valid_view s hv
  have changing : ∀ ek a old,
      Elixir.HoldLedger.Ledger.«find/2» es key = Except.ok (Lynx.Term.tuple #[Lynx.Term.atom "ok", Lynx.Term.tuple #[ek, Lynx.Term.integer a, old]]) →
      old = Lynx.Term.atom "sent" →
      ∃ out, Elixir.HoldLedger.Ledger.«set_status/3» es key (Lynx.Term.atom "unknown") = Except.ok out ∧
      Elixir.HoldLedger.Spec.«valid?/1» (Lynx.Term.tuple #[Lynx.Term.integer al, Lynx.Term.integer hl, Lynx.Term.integer ua, Lynx.Term.integer uh, out]) = Except.ok Lynx.Term.true := by
    intro ek a old hk ho
    subst old
    obtain ⟨out, ba, bc, aa, ac, hm, hba, hbc, haa, hac, hea, hec⟩ := delta es key ek a (Lynx.Term.atom "sent") (Lynx.Term.atom "unknown") hp hk
    obtain ⟨out2, hm2, hp2, hl2, hu2⟩ := structural es key (Lynx.Term.atom "unknown") hp (by rfl)
    clear requires totals valid_view delta structural lookup_shape hv
    simp_all [HoldLedgerProof.held, Elixir.HoldLedger.Spec.«valid?/1», Elixir.HoldLedger.Spec.«nonnegative_state_valid?/5», Elixir.HoldLedger.Spec.«unique_keys?/1»,
      Erlang.erlang.«is_integer/1», Erlang.erlang.«==/2»,
      Lynx.Except.guard, Lynx.Except.tryWith, bind, Except.bind, Lynx.Term.true, Lynx.Term.false]
    all_goals repeat' (split at * <;> try simp_all [Lynx.Term.true, Lynx.Term.false])
  have shape := lookup_shape es key hp
  clear requires totals valid_view delta structural lookup_shape
  cases key <;> try simp [«po_b1_timeout:ensures/2», Elixir.HoldLedger.Ledger.«timeout/2»,
    Erlang.erlang.«element/2», Erlang.erlang.«is_integer/1»,
    Lynx.Except.guard, Lynx.Except.tryWith, bind, Except.bind, hv]
  rcases shape with hn | ⟨ek, a, st, hk, hs⟩
  · simp [«po_b1_timeout:ensures/2», Elixir.HoldLedger.Ledger.«timeout/2», hn,
      Erlang.erlang.«element/2», Erlang.erlang.«is_integer/1»,
      Lynx.Except.guard, Lynx.Except.tryWith, bind, Except.bind, hv]
  · simp only [Elixir.HoldLedger.Spec.«known_status?/1», Elixir.HoldLedger.Spec.«holding?/1», Elixir.HoldLedger.Spec.«terminal?/1»] at hs
    repeat' (split at hs <;> try simp_all [Lynx.Term.true, Lynx.Term.false])
    all_goals subst_vars
    all_goals try first
      | obtain ⟨out, hm, hvo⟩ := changing _ _ _ hk rfl
      | obtain ⟨out, hm, hvo⟩ := changing rfl
      | obtain ⟨out, hm, hvo⟩ := changing
    all_goals try simp_all [«po_b1_timeout:ensures/2», Elixir.HoldLedger.Ledger.«timeout/2»,
      Erlang.erlang.«element/2», Erlang.erlang.«is_integer/1»,
      Lynx.Except.guard, Lynx.Except.tryWith, bind, Except.bind]

theorem «po_b1_restart/1» (s : Lynx.Term)
    (requires : «po_b1_restart:requires/1» s = Except.ok Lynx.Term.true) :
    «po_b1_restart:ensures/1» s = Except.ok Lynx.Term.true := by
  have totals := HoldLedgerProof.totals_1
  have valid_view := HoldLedgerProof.valid_view_1
  have accounting := HoldLedgerProof.accounting_1
  have restarted_structure := HoldLedgerProof.restarted_structure_1
  have hvalid : Elixir.HoldLedger.Spec.«valid?/1» s = Except.ok Lynx.Term.true := requires
  obtain ⟨al, hl, ua, uh, es, rfl, hp, hu, ha, hc, hal, hhl, hua, huh, hacap, hhcap⟩ := valid_view s hvalid
  obtain ⟨out, hm, a, hba, haa, c, hbc, hac⟩ := accounting es hp
  obtain ⟨out2, hm2, hp2, hl2, hu2⟩ := restarted_structure es hp
  clear requires totals valid_view accounting restarted_structure
  simp_all [«po_b1_restart:ensures/1», Elixir.HoldLedger.Ledger.«restart/1»,
    Elixir.HoldLedger.Spec.«valid?/1», Elixir.HoldLedger.Spec.«nonnegative_state_valid?/5», Elixir.HoldLedger.Spec.«unique_keys?/1»,
    Erlang.erlang.«element/2», Erlang.erlang.«is_integer/1», Erlang.erlang.«==/2»,
    Lynx.Except.guard, Lynx.Except.tryWith, bind, Except.bind, Lynx.Term.true, Lynx.Term.false]
  all_goals repeat' (split at * <;> try simp_all [Lynx.Term.true, Lynx.Term.false])

theorem «po_b1_retry/2» (s key : Lynx.Term)
    (requires : «po_b1_retry:requires/2» s key = Except.ok Lynx.Term.true) :
    «po_b1_retry:ensures/2» s key = Except.ok Lynx.Term.true := by
  have totals := HoldLedgerProof.totals_1
  have valid_view := HoldLedgerProof.valid_view_1
  have delta := HoldLedgerProof.delta_2
  have structural := HoldLedgerProof.structural_1
  have lookup_shape := HoldLedgerProof.lookup_shape_2
  have hv : Elixir.HoldLedger.Spec.«valid?/1» s = Except.ok Lynx.Term.true := requires
  obtain ⟨al, hl, ua, uh, es, rfl, hp, hu, ha, hc, hal, hhl, hua, huh, hacap, hhcap⟩ := valid_view s hv
  have changing : ∀ ek a old,
      Elixir.HoldLedger.Ledger.«find/2» es key = Except.ok (Lynx.Term.tuple #[Lynx.Term.atom "ok", Lynx.Term.tuple #[ek, Lynx.Term.integer a, old]]) →
      old = Lynx.Term.atom "unknown" →
      ∃ out, Elixir.HoldLedger.Ledger.«set_status/3» es key (Lynx.Term.atom "sent") = Except.ok out ∧
      Elixir.HoldLedger.Spec.«valid?/1» (Lynx.Term.tuple #[Lynx.Term.integer al, Lynx.Term.integer hl, Lynx.Term.integer ua, Lynx.Term.integer uh, out]) = Except.ok Lynx.Term.true := by
    intro ek a old hk ho
    subst old
    obtain ⟨out, ba, bc, aa, ac, hm, hba, hbc, haa, hac, hea, hec⟩ := delta es key ek a (Lynx.Term.atom "unknown") (Lynx.Term.atom "sent") hp hk
    obtain ⟨out2, hm2, hp2, hl2, hu2⟩ := structural es key (Lynx.Term.atom "sent") hp (by rfl)
    clear requires totals valid_view delta structural lookup_shape hv
    simp_all [HoldLedgerProof.held, Elixir.HoldLedger.Spec.«valid?/1», Elixir.HoldLedger.Spec.«nonnegative_state_valid?/5», Elixir.HoldLedger.Spec.«unique_keys?/1»,
      Erlang.erlang.«is_integer/1», Erlang.erlang.«==/2»,
      Lynx.Except.guard, Lynx.Except.tryWith, bind, Except.bind, Lynx.Term.true, Lynx.Term.false]
    all_goals repeat' (split at * <;> try simp_all [Lynx.Term.true, Lynx.Term.false])
  have shape := lookup_shape es key hp
  clear requires totals valid_view delta structural lookup_shape
  cases key <;> try simp [«po_b1_retry:ensures/2», Elixir.HoldLedger.Ledger.«retry/2»,
    Erlang.erlang.«element/2», Erlang.erlang.«is_integer/1»,
    Lynx.Except.guard, Lynx.Except.tryWith, bind, Except.bind, hv]
  rcases shape with hn | ⟨ek, a, st, hk, hs⟩
  · simp [«po_b1_retry:ensures/2», Elixir.HoldLedger.Ledger.«retry/2», hn,
      Erlang.erlang.«element/2», Erlang.erlang.«is_integer/1»,
      Lynx.Except.guard, Lynx.Except.tryWith, bind, Except.bind, hv]
  · simp only [Elixir.HoldLedger.Spec.«known_status?/1», Elixir.HoldLedger.Spec.«holding?/1», Elixir.HoldLedger.Spec.«terminal?/1»] at hs
    repeat' (split at hs <;> try simp_all [Lynx.Term.true, Lynx.Term.false])
    all_goals subst_vars
    all_goals try first
      | obtain ⟨out, hm, hvo⟩ := changing _ _ _ hk rfl
      | obtain ⟨out, hm, hvo⟩ := changing rfl
      | obtain ⟨out, hm, hvo⟩ := changing
    all_goals try simp_all [«po_b1_retry:ensures/2», Elixir.HoldLedger.Ledger.«retry/2»,
      Erlang.erlang.«element/2», Erlang.erlang.«is_integer/1»,
      Lynx.Except.guard, Lynx.Except.tryWith, bind, Except.bind]

theorem «po_b1_processor_result/3» (s key outcome : Lynx.Term)
    (requires : «po_b1_processor_result:requires/3» s key outcome = Except.ok Lynx.Term.true) :
    «po_b1_processor_result:ensures/3» s key outcome = Except.ok Lynx.Term.true := by
  have totals := HoldLedgerProof.totals_1
  have valid_view := HoldLedgerProof.valid_view_1
  have delta := HoldLedgerProof.delta_2
  have structural := HoldLedgerProof.structural_1
  have lookup_shape := HoldLedgerProof.lookup_shape_2
  have nonnegative := HoldLedgerProof.nonnegative_1
  have selected_bound := HoldLedgerProof.selected_bound_1
  have positive := HoldLedgerProof.positive_1
  have hv : Elixir.HoldLedger.Spec.«valid?/1» s = Except.ok Lynx.Term.true := requires
  obtain ⟨al, hl, ua, uh, es, rfl, hp, hu, ha, hc, hal, hhl, hua, huh, hacap, hhcap⟩ := valid_view s hv
  have changing : ∀ ek a old to,
      Elixir.HoldLedger.Ledger.«find/2» es key = Except.ok (Lynx.Term.tuple #[Lynx.Term.atom "ok", Lynx.Term.tuple #[ek, Lynx.Term.integer a, old]]) →
      Elixir.HoldLedger.Spec.«holding?/1» old = Except.ok Lynx.Term.true →
      Elixir.HoldLedger.Spec.«known_status?/1» to = Except.ok Lynx.Term.true →
      ∃ out, Elixir.HoldLedger.Ledger.«set_status/3» es key to = Except.ok out ∧
      Elixir.HoldLedger.Spec.«valid?/1» (Lynx.Term.tuple #[Lynx.Term.integer al, Lynx.Term.integer hl,
        Lynx.Term.integer (if HoldLedgerProof.held to then ua else ua-a), Lynx.Term.integer (if HoldLedgerProof.held to then uh else uh-1), out]) = Except.ok Lynx.Term.true := by
    intro ek a old to hk ho ht
    obtain ⟨out, ba, bc, aa, ac, hm, hba, hbc, haa, hac, hea, hec⟩ := delta es key ek a old to hp hk
    obtain ⟨out2, hm2, hp2, hl2, hu2⟩ := structural es key to hp ht
    obtain ⟨ba2, bc2, hba2, hbc2, hab, hcb⟩ := selected_bound es key ek a old hp hk ho
    have hpos := positive es key ek a old hp hk
    simp only [HoldLedgerProof.holding_model] at ho
    clear requires totals valid_view delta structural lookup_shape nonnegative selected_bound positive hv
    refine ⟨out, hm, ?_⟩
    by_cases hto : HoldLedgerProof.held to
    all_goals simp_all [Elixir.HoldLedger.Spec.«valid?/1», Elixir.HoldLedger.Spec.«nonnegative_state_valid?/5», Elixir.HoldLedger.Spec.«unique_keys?/1»,
      Erlang.erlang.«is_integer/1», Erlang.erlang.«==/2»,
      Lynx.Except.guard, Lynx.Except.tryWith, bind, Except.bind, Lynx.Term.true, Lynx.Term.false]
    all_goals repeat' (split at * <;> subst_vars <;> try simp_all [Lynx.Term.true, Lynx.Term.false])
    all_goals omega
  have shape := lookup_shape es key hp
  clear requires totals valid_view delta structural lookup_shape nonnegative selected_bound positive
  cases key <;> try simp [«po_b1_processor_result:ensures/3», Elixir.HoldLedger.Ledger.«processor_result/3»,
    Erlang.erlang.«element/2», Erlang.erlang.«is_integer/1»,
    Lynx.Except.guard, Lynx.Except.tryWith, bind, Except.bind, hv]
  cases outcome <;> try simp [«po_b1_processor_result:ensures/3», Elixir.HoldLedger.Ledger.«processor_result/3»,
    Erlang.erlang.«element/2», Erlang.erlang.«is_integer/1»,
    Lynx.Except.guard, Lynx.Except.tryWith, bind, Except.bind, hv]
  rename_i resultname
  by_cases happroved : resultname = "approved"
  · subst resultname
    rcases shape with hn | ⟨ek, a, st, hk, hs⟩
    · simp [«po_b1_processor_result:ensures/3», Elixir.HoldLedger.Ledger.«processor_result/3», hn,
        Erlang.erlang.«element/2», Erlang.erlang.«is_integer/1»,
        Lynx.Except.guard, Lynx.Except.tryWith, bind, Except.bind, hv]
    · have changing_here := changing (Lynx.Term.integer ek) a st (Lynx.Term.atom "authorized") hk
      simp only [Elixir.HoldLedger.Spec.«known_status?/1», Elixir.HoldLedger.Spec.«holding?/1»,
        Elixir.HoldLedger.Spec.«terminal?/1»] at hs
      repeat' (split at hs <;> try simp_all [Lynx.Term.true, Lynx.Term.false])
      all_goals subst_vars
      all_goals try first
        | obtain ⟨out, hm, hvo⟩ := changing_here (by rfl) (by rfl)
        | obtain ⟨out, hm, hvo⟩ := changing_here
        | obtain ⟨out, hm, hvo⟩ := changing _ _ _ (Lynx.Term.atom "authorized") rfl rfl rfl (by rfl) (by rfl)
      all_goals try simp_all [HoldLedgerProof.held, «po_b1_processor_result:ensures/3», Elixir.HoldLedger.Ledger.«processor_result/3»,
        Erlang.erlang.«element/2», Erlang.erlang.«is_integer/1»,
        Lynx.Except.guard, Lynx.Except.tryWith, bind, Except.bind, hv]
  · by_cases hdeclined : resultname = "declined"
    · subst resultname
      rcases shape with hn | ⟨ek, a, st, hk, hs⟩
      · simp [«po_b1_processor_result:ensures/3», Elixir.HoldLedger.Ledger.«processor_result/3», hn,
          Erlang.erlang.«element/2», Erlang.erlang.«is_integer/1»,
          Lynx.Except.guard, Lynx.Except.tryWith, bind, Except.bind, hv]
      · have changing_here := changing (Lynx.Term.integer ek) a st (Lynx.Term.atom "declined") hk
        simp only [Elixir.HoldLedger.Spec.«known_status?/1», Elixir.HoldLedger.Spec.«holding?/1»,
          Elixir.HoldLedger.Spec.«terminal?/1»] at hs
        repeat' (split at hs <;> try simp_all [Lynx.Term.true, Lynx.Term.false])
        all_goals subst_vars
        all_goals try first
          | obtain ⟨out, hm, hvo⟩ := changing_here (by rfl) (by rfl)
          | obtain ⟨out, hm, hvo⟩ := changing_here
          | obtain ⟨out, hm, hvo⟩ := changing _ _ _ (Lynx.Term.atom "declined") rfl rfl rfl (by rfl) (by rfl)
        all_goals try simp_all [HoldLedgerProof.held, «po_b1_processor_result:ensures/3», Elixir.HoldLedger.Ledger.«processor_result/3»,
          Erlang.erlang.«element/2», Erlang.erlang.«is_integer/1»,
          Lynx.Except.guard, Lynx.Except.tryWith, bind, Except.bind, hv]
    · simp [«po_b1_processor_result:ensures/3», Elixir.HoldLedger.Ledger.«processor_result/3»,
        happroved, hdeclined, Erlang.erlang.«element/2», Erlang.erlang.«is_integer/1»,
        Lynx.Except.guard, Lynx.Except.tryWith, bind, Except.bind, hv]

theorem «po_b1_void/2» (s key : Lynx.Term)
    (requires : «po_b1_void:requires/2» s key = Except.ok Lynx.Term.true) :
    «po_b1_void:ensures/2» s key = Except.ok Lynx.Term.true := by
  have totals := HoldLedgerProof.totals_1
  have valid_view := HoldLedgerProof.valid_view_1
  have delta := HoldLedgerProof.delta_2
  have structural := HoldLedgerProof.structural_1
  have lookup_shape := HoldLedgerProof.lookup_shape_2
  have nonnegative := HoldLedgerProof.nonnegative_1
  have selected_bound := HoldLedgerProof.selected_bound_1
  have positive := HoldLedgerProof.positive_1
  have hv : Elixir.HoldLedger.Spec.«valid?/1» s = Except.ok Lynx.Term.true := requires
  obtain ⟨al, hl, ua, uh, es, rfl, hp, hu, ha, hc, hal, hhl, hua, huh, hacap, hhcap⟩ := valid_view s hv
  have changing : ∀ ek a old to,
      Elixir.HoldLedger.Ledger.«find/2» es key = Except.ok (Lynx.Term.tuple #[Lynx.Term.atom "ok", Lynx.Term.tuple #[ek, Lynx.Term.integer a, old]]) →
      Elixir.HoldLedger.Spec.«holding?/1» old = Except.ok Lynx.Term.true →
      Elixir.HoldLedger.Spec.«known_status?/1» to = Except.ok Lynx.Term.true →
      ∃ out, Elixir.HoldLedger.Ledger.«set_status/3» es key to = Except.ok out ∧
      Elixir.HoldLedger.Spec.«valid?/1» (Lynx.Term.tuple #[Lynx.Term.integer al, Lynx.Term.integer hl,
        Lynx.Term.integer (if HoldLedgerProof.held to then ua else ua-a), Lynx.Term.integer (if HoldLedgerProof.held to then uh else uh-1), out]) = Except.ok Lynx.Term.true := by
    intro ek a old to hk ho ht
    obtain ⟨out, ba, bc, aa, ac, hm, hba, hbc, haa, hac, hea, hec⟩ := delta es key ek a old to hp hk
    obtain ⟨out2, hm2, hp2, hl2, hu2⟩ := structural es key to hp ht
    obtain ⟨ba2, bc2, hba2, hbc2, hab, hcb⟩ := selected_bound es key ek a old hp hk ho
    have hpos := positive es key ek a old hp hk
    simp only [HoldLedgerProof.holding_model] at ho
    clear requires totals valid_view delta structural lookup_shape nonnegative selected_bound positive hv
    refine ⟨out, hm, ?_⟩
    by_cases hto : HoldLedgerProof.held to
    all_goals simp_all [Elixir.HoldLedger.Spec.«valid?/1», Elixir.HoldLedger.Spec.«nonnegative_state_valid?/5», Elixir.HoldLedger.Spec.«unique_keys?/1»,
      Erlang.erlang.«is_integer/1», Erlang.erlang.«==/2»,
      Lynx.Except.guard, Lynx.Except.tryWith, bind, Except.bind, Lynx.Term.true, Lynx.Term.false]
    all_goals repeat' (split at * <;> subst_vars <;> try simp_all [Lynx.Term.true, Lynx.Term.false])
    all_goals omega
  have shape := lookup_shape es key hp
  clear requires totals valid_view delta structural lookup_shape nonnegative selected_bound positive
  cases key <;> try simp [«po_b1_void:ensures/2», Elixir.HoldLedger.Ledger.«void/2»,
    Erlang.erlang.«element/2», Erlang.erlang.«is_integer/1»,
    Lynx.Except.guard, Lynx.Except.tryWith, bind, Except.bind, hv]
  rcases shape with hn | ⟨ek, a, st, hk, hs⟩
  · simp [«po_b1_void:ensures/2», Elixir.HoldLedger.Ledger.«void/2», hn,
      Erlang.erlang.«element/2», Erlang.erlang.«is_integer/1»,
      Lynx.Except.guard, Lynx.Except.tryWith, bind, Except.bind, hv]
  · have changing_here := changing (Lynx.Term.integer ek) a st (Lynx.Term.atom "voided") hk
    simp only [Elixir.HoldLedger.Spec.«known_status?/1», Elixir.HoldLedger.Spec.«holding?/1»,
      Elixir.HoldLedger.Spec.«terminal?/1»] at hs
    repeat' (split at hs <;> try simp_all [Lynx.Term.true, Lynx.Term.false])
    all_goals subst_vars
    all_goals try first
      | obtain ⟨out, hm, hvo⟩ := changing_here (by rfl) (by rfl)
      | obtain ⟨out, hm, hvo⟩ := changing_here
      | obtain ⟨out, hm, hvo⟩ := changing _ _ _ (Lynx.Term.atom "voided") rfl rfl rfl (by rfl) (by rfl)
    all_goals try simp_all [HoldLedgerProof.held, «po_b1_void:ensures/2», Elixir.HoldLedger.Ledger.«void/2»,
      Erlang.erlang.«element/2», Erlang.erlang.«is_integer/1»,
      Lynx.Except.guard, Lynx.Except.tryWith, bind, Except.bind, hv]

end Elixir.HoldLedger.ProofContracts
