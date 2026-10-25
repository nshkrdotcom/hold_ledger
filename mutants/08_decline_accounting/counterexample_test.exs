defmodule HoldLedger.Mutants.M8CounterexampleTest do
  use ExUnit.Case, async: true
  alias HoldLedger.{Ledger, Spec}

  test "M8: decline increases used amount" do
    state = {1000, 3, 300, 1, [{11, 300, :sent}]}
    event = {:processor_result, 11, :declined}
    assert Spec.valid?(state)
    assert Ledger.step(state, event) == Spec.expected_step(state, event)
  end
end
