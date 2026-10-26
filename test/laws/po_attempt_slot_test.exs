defmodule HoldLedger.Laws.PoAttemptSlotTest do
  use ExUnit.Case
  use HoldLedger.ProofCase
  alias HoldLedger.Attempts

  laws "po_attempt_slot" do
    law(po_attempt_slot(next, entries, kind, key, limit),
      requires:
        is_integer(Attempts.count(entries)) and
          Attempts.occupied?(entries, kind, key) === true,
      expects:
        Attempts.step({next, false, entries}, {:start, kind, key, limit}) ==
          {{next, false, entries}, []},
      proof: ~LEAN"""
      simp only [«po_attempt_slot:requires/5», bind, Except.bind] at requires
      cases counted : Elixir.HoldLedger.Attempts.«count/1» entries with
      | error err => simp [counted] at requires
      | ok count =>
        have occupied : Elixir.HoldLedger.Attempts.«occupied?/3» entries kind key =
            Except.ok Lynx.Term.true := by
          cases found : Elixir.HoldLedger.Attempts.«occupied?/3» entries kind key with
          | error err =>
            simp [counted, found] at requires
            repeat' (split at requires <;> try simp_all [Erlang.erlang.«is_integer/1», Lynx.Term.true, Lynx.Term.false])
          | ok value =>
            simp [counted, found, Erlang.erlang.«=:=/2», Lynx.Term.true, Lynx.Term.false] at requires
            repeat' (split at requires <;> try simp_all [Lynx.Term.true])
            all_goals simpa [Lynx.Term.true] using (by assumption : value = Lynx.Term.atom "true")
        simp only [«po_attempt_slot:ensures/5», Elixir.HoldLedger.Attempts.«step/2»,
          Lynx.Except.guard, Lynx.Except.tryWith, bind, Except.bind]
        repeat' (split at * <;> try simp_all [
          Erlang.erlang.«==/2», Erlang.erlang.«</2», Erlang.erlang.«>/2», Erlang.erlang.«not/1», Erlang.erlang.«=:=/2», Erlang.erlang.«is_integer/1», Lynx.Term.true, Lynx.Term.false,
          Lynx.Except.andAlso])
      """
    )
  end
end
