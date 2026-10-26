defmodule HoldLedger.Laws.PoAttemptPoisonTest do
  use ExUnit.Case
  use HoldLedger.ProofCase
  alias HoldLedger.Attempts

  laws "po_attempt_poison" do
    law(po_attempt_poison(next, entries, kind, key, limit),
      requires: true,
      expects:
        Attempts.step({next, true, entries}, {:start, kind, key, limit}) ==
          {{next, true, entries}, []},
      proof: ~LEAN"""
      cases requires
      simp [«po_attempt_poison:ensures/5»,
        Elixir.HoldLedger.Attempts.«step/2», Erlang.erlang.«==/2»]
      """
    )
  end
end
