defmodule HoldLedger.Mutants.M9CounterexampleTest do
  use ExUnit.Case, async: true
  alias HoldLedger.{Ledger, Spec}

  test "M9: restart leaves sent entries unchanged" do
    state = {1000, 3, 300, 1, [{11, 300, :sent}]}
    event = :restart
    assert Spec.valid?(state)
    assert Ledger.step(state, event) == Spec.expected_step(state, event)
  end
end
