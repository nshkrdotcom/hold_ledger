defmodule HoldLedger.Mutants.M7CounterexampleTest do
  use ExUnit.Case, async: true
  alias HoldLedger.{Ledger, Spec}

  test "M7: void drops its required remote intent" do
    state = {1000, 3, 300, 1, [{11, 300, :authorized}]}
    event = {:void, 11}
    assert Spec.valid?(state)
    assert Ledger.step(state, event) == Spec.expected_step(state, event)
  end
end
