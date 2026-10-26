defmodule HoldLedger.Laws.PoTerminalFenceTest do
  use ExUnit.Case
  use HoldLedger.ProofCase
  alias HoldLedger.Environment

  laws "po_terminal_fence" do
    law(po_terminal_fence(issued, key, amount, rest),
      requires: true,
      expects:
        Environment.deliver(
          {issued, [{key, amount, :voided} | rest]},
          {:authorize, key, :approved}
        ) ==
          {{issued, [{key, amount, :voided} | rest]}, :declined},
      proof: ~LEAN"""
      cases requires
      simp [«po_terminal_fence:ensures/4»,
        Elixir.HoldLedger.Environment.«deliver/2», Elixir.HoldLedger.Environment.«lookup/2»,
        Erlang.erlang.«=:=/2», Erlang.erlang.«==/2»]
      """
    )
  end
end
