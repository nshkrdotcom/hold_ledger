defmodule HoldLedger.Mutants.M10CounterexampleTest do
  use ExUnit.Case, async: true
  alias HoldLedger.{Ledger, Spec}

  test "M10: an unconfirmed void must retain issued capacity" do
    state = {100, 2, 100, 1, [{1, 100, :authorized}]}
    {next, _, _} = Ledger.step(state, {:void, 1})
    assert Spec.valid?(state)
    assert Spec.exposed_entry?(next, 1, 100)
    assert {_, :insufficient_amount, []} = Ledger.step(next, {:request, 2, 100})
  end
end
