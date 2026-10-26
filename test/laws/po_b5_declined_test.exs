defmodule HoldLedger.Laws.PoB5DeclinedTest do
  use ExUnit.Case
  use HoldLedger.ProofCase

  alias HoldLedger.{Ledger, Spec}

  # PO-B5/declined (P1): declined remains absorbing under arbitrary next event.
  # Witness: test/hold_ledger_witness_test.exs.
  # Proof scope and commands: guides/verification.md.
  @moduletag timeout: 300_000

  laws "po_b5_declined" do
    law(po_b5_declined(s, event, key, amount),
      requires:
        Spec.valid?(s) and Spec.lookup(elem(s, 4), key) == {:ok, {key, amount, :declined}},
      expects:
        Spec.lookup(elem(elem(Ledger.step(s, event), 0), 4), key) ==
          {:ok, {key, amount, :declined}},
      proof: ~LEAN"""
      have valid : Elixir.HoldLedger.Spec.«valid?/1» s = Except.ok Lynx.Term.true := by
        simp only [«po_b5_declined:requires/4», bind, Except.bind] at requires
        all_goals repeat' (split at requires <;> try simp_all [Lynx.Term.true])
      have before : (do let entries ← Erlang.erlang.«element/2» (Lynx.Term.integer 5) s
                        let found ← Elixir.HoldLedger.Spec.«lookup/2» entries key
                        Erlang.erlang.«==/2» found
                          (Lynx.Term.tuple #[Lynx.Term.atom "ok", Lynx.Term.tuple #[key,amount,Lynx.Term.atom "declined"]])) =
                      Except.ok Lynx.Term.true := by
        simpa [«po_b5_declined:requires/4»,valid,bind,Except.bind] using requires
      simpa only [«po_b5_declined:ensures/4»] using
        HoldLedgerProof.terminal_comparison s event key amount "declined" (Or.inl rfl) valid before
      """
    )
  end
end
