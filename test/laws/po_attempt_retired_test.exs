defmodule HoldLedger.Laws.PoAttemptRetiredTest do
  use ExUnit.Case
  use HoldLedger.ProofCase
  alias HoldLedger.Attempts

  laws "po_attempt_retired" do
    law(po_attempt_retired(next, poison, entries, id),
      requires: Attempts.lookup(entries, id) === :not_found,
      expects:
        Attempts.step({next, poison, entries}, {:result, id}) == {{next, poison, entries}, []} and
          Attempts.step({next, poison, entries}, {:down, id}) == {{next, poison, entries}, []} and
          Attempts.step({next, poison, entries}, {:deadline, id}) == {{next, poison, entries}, []} and
          Attempts.step({next, poison, entries}, {:shutdown_result, id}) ==
            {{next, poison, entries}, []} and
          Attempts.step({next, poison, entries}, {:committed, id}) ==
            {{next, poison, entries}, []},
      proof: ~LEAN"""
      have absent : Elixir.HoldLedger.Attempts.«lookup/2» entries id =
          Except.ok (Lynx.Term.atom "not_found") := by
        cases found : Elixir.HoldLedger.Attempts.«lookup/2» entries id with
        | error err => simp [«po_attempt_retired:requires/4», found, bind, Except.bind] at requires
        | ok value =>
          simp [«po_attempt_retired:requires/4», found, Erlang.erlang.«=:=/2»,
            Lynx.Term.true, Lynx.Term.false] at requires
          simp [requires]
      simp [«po_attempt_retired:ensures/4», Elixir.HoldLedger.Attempts.«step/2»,
        Elixir.HoldLedger.Attempts.«change/5», absent, Erlang.erlang.«==/2»,
        Lynx.Term.true]
      """
    )
  end
end
