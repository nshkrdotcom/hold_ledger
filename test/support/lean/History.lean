module

public import HoldLedgerProof.Oracle
public import HoldLedgerProof.HistoryRelations
public import HoldLedgerProof.Authorization
public import HoldLedgerProof.Identity
public import HoldLedgerProof.Terminal

public section
set_option maxHeartbeats 6000000
namespace HoldLedgerProof

theorem history (events s : Lynx.Term)
    (proper : Elixir.HoldLedger.Spec.«proper_events?/1» events = Except.ok Lynx.Term.true)
    (valid : Elixir.HoldLedger.Spec.«valid?/1» s = Except.ok Lynx.Term.true) :
    ∃ final,
      Elixir.HoldLedger.Ledger.«run/2» s events = Except.ok final ∧
      Elixir.HoldLedger.Spec.«expected_run/2» s events = Except.ok final ∧
      Elixir.HoldLedger.Spec.«valid?/1» final = Except.ok Lynx.Term.true ∧
      Elixir.HoldLedger.Spec.«identity_preserved?/2» s final = Except.ok Lynx.Term.true ∧
      Elixir.HoldLedger.Spec.«history_authorizations_explained?/2» s events = Except.ok Lynx.Term.true ∧
      ∀ key amount status,
        (status = Lynx.Term.atom "declined" ∨ status = Lynx.Term.atom "voided") →
        (do let entries ← Erlang.erlang.«element/2» (Lynx.Term.integer 5) s
            Elixir.HoldLedger.Spec.«lookup/2» entries key) =
          Except.ok (Lynx.Term.tuple #[Lynx.Term.atom "ok",Lynx.Term.tuple #[key,amount,status]]) →
        (do let entries ← Erlang.erlang.«element/2» (Lynx.Term.integer 5) final
            Elixir.HoldLedger.Spec.«lookup/2» entries key) =
          Except.ok (Lynx.Term.tuple #[Lynx.Term.atom "ok",Lynx.Term.tuple #[key,amount,status]]) := by
  fun_induction Elixir.HoldLedger.Spec.«proper_events?/1» events generalizing s
  case case1 =>
    obtain ⟨al,hl,ua,uh,es,rfl,hp,hu,ha,hc,hal,hhl,hua,huh,hacap,hhcap⟩ := valid_view_1 s valid
    have unique : Elixir.HoldLedger.Spec.«unique_keys_seen?/2» es Lynx.Term.nil = Except.ok Lynx.Term.true := by
      exact unique_view es hu
    have ids := identities_1 es Lynx.Term.nil es unique (by intro key amount old _ hl; exact ⟨old,hl⟩)
    refine ⟨_,rfl,rfl,valid,?_,rfl,?_⟩
    · simpa [Elixir.HoldLedger.Spec.«identity_preserved?/2»] using ids
    · intro key amount status terminal lookup
      exact lookup
  case case2 event rest ih =>
    have tail_proper : Elixir.HoldLedger.Spec.«proper_events?/1» rest = Except.ok Lynx.Term.true := proper
    obtain ⟨next,result,effects,step,oracle,next_valid⟩ := step_agrees s event valid
    obtain ⟨final,run,expected,final_valid,ids_tail,explained_tail,terminals_tail⟩ := ih next tail_proper next_valid
    have ids_step := Elixir.HoldLedger.ProofContracts.«po_b6/2» s event valid
    have approved_step := Elixir.HoldLedger.ProofContracts.«po_b4/2» s event valid
    change (do let out ← Elixir.HoldLedger.Ledger.«step/2» s event
               let after_state ← Erlang.erlang.«element/2» (Lynx.Term.integer 1) out
               Elixir.HoldLedger.Spec.«identity_preserved?/2» s after_state) = Except.ok Lynx.Term.true at ids_step
    change (do let out ← Elixir.HoldLedger.Ledger.«step/2» s event
               let after_state ← Erlang.erlang.«element/2» (Lynx.Term.integer 1) out
               Elixir.HoldLedger.Spec.«authorized_only_on_result?/3» s event after_state) = Except.ok Lynx.Term.true at approved_step
    have first_ids : Elixir.HoldLedger.Spec.«identity_preserved?/2» s next = Except.ok Lynx.Term.true := by
      simpa [step,Erlang.erlang.«element/2»,bind,Except.bind] using ids_step
    have first_approval : Elixir.HoldLedger.Spec.«authorized_only_on_result?/3» s event next = Except.ok Lynx.Term.true := by
      simpa [step,Erlang.erlang.«element/2»,bind,Except.bind] using approved_step
    refine ⟨final,?_,?_,final_valid,?_,?_,?_⟩
    · simpa [Elixir.HoldLedger.Ledger.«run/2»,step,bind,Except.bind] using run
    · simpa [Elixir.HoldLedger.Spec.«expected_run/2»,oracle,bind,Except.bind] using expected
    · obtain ⟨al,hl,ua,uh,es,rfl,hp,hu,ha,hc,hal,hhl,hua,huh,hacap,hhcap⟩ := valid_view_1 s valid
      obtain ⟨nal,nhl,nua,nuh,nes,rfl,np,nu,na,nc,nal0,nhl0,nua0,nuh0,nacap,nhcap⟩ := valid_view_1 next next_valid
      obtain ⟨fal,fhl,fua,fuh,fes,rfl,fp,fu,fa,fc,fal0,fhl0,fua0,fuh0,facap,fhcap⟩ := valid_view_1 final final_valid
      have unique : Elixir.HoldLedger.Spec.«unique_keys_seen?/2» es Lynx.Term.nil = Except.ok Lynx.Term.true := by
        exact unique_view es hu
      exact identities_trans es nes fes hp np unique first_ids ids_tail
    · simp [Elixir.HoldLedger.Spec.«history_authorizations_explained?/2»,oracle,first_approval,explained_tail]
    · intro key amount status terminal lookup
      apply terminals_tail key amount status terminal
      obtain ⟨al,hl,ua,uh,es,rfl,hp,hu,ha,hc,hal,hhl,hua,huh,hacap,hhcap⟩ := valid_view_1 s valid
      have lookup' : Elixir.HoldLedger.Spec.«lookup/2» es key =
          Except.ok (Lynx.Term.tuple #[Lynx.Term.atom "ok",Lynx.Term.tuple #[key,amount,status]]) := by
        simpa [Erlang.erlang.«element/2»,bind,Except.bind] using lookup
      have preserved := terminal_lookup al hl ua uh es event key key amount status hp terminal lookup'
      simpa [step,Erlang.erlang.«element/2»,bind,Except.bind] using preserved
  case case3 => simp [Lynx.Term.true] at proper

end HoldLedgerProof

namespace Elixir.HoldLedger.ProofContracts

theorem «po_c3/2» (s events : Lynx.Term)
    (requires : «po_c3:requires/2» s events = Except.ok Lynx.Term.true) :
    «po_c3:ensures/2» s events = Except.ok Lynx.Term.true := by
  have valid : Elixir.HoldLedger.Spec.«valid?/1» s = Except.ok Lynx.Term.true := by
    simp only [«po_c3:requires/2»,bind,Except.bind] at requires
    all_goals repeat' (split at requires <;> try simp_all [Lynx.Term.true])
  have proper : Elixir.HoldLedger.Spec.«proper_events?/1» events = Except.ok Lynx.Term.true := by
    simpa [«po_c3:requires/2»,valid,bind,Except.bind] using requires
  obtain ⟨final,run,expected,final_valid,ids,explained,preserved⟩ := HoldLedgerProof.history events s proper valid
  have terminals : Elixir.HoldLedger.Spec.«terminal_preserved?/2» s final = Except.ok Lynx.Term.true := by
    obtain ⟨al,hl,ua,uh,es,rfl,hp,hu,ha,hc,hal,hhl,hua,huh,hacap,hhcap⟩ := HoldLedgerProof.valid_view_1 s valid
    obtain ⟨fal,fhl,fua,fuh,fes,rfl,fp,fu,fa,fc,fal0,fhl0,fua0,fuh0,facap,fhcap⟩ := HoldLedgerProof.valid_view_1 final final_valid
    have unique : Elixir.HoldLedger.Spec.«unique_keys_seen?/2» es Lynx.Term.nil = Except.ok Lynx.Term.true := by
      exact HoldLedgerProof.unique_view es hu
    apply HoldLedgerProof.terminal_entries es Lynx.Term.nil fes unique
    intro key amount status _ lookup terminal
    have kept := preserved key amount status terminal (by simpa [Erlang.erlang.«element/2»,bind,Except.bind] using lookup)
    simpa [Erlang.erlang.«element/2»,bind,Except.bind] using kept
  simp [«po_c3:ensures/2»,run,expected,ids,terminals,explained,Erlang.erlang.«==/2»]

end Elixir.HoldLedger.ProofContracts
