defmodule HoldLedger.Mutants.M2CounterexampleTest do
  use ExUnit.Case, async: true
  alias HoldLedger.{Ledger, Spec}

  test "M2: timeout erroneously releases a reservation" do
    s = {1000, 3, 300, 1, [{11, 300, :sent}]}
    event = {:timeout, 11}
    assert Spec.valid?(s)
    assert Ledger.step(s, event) == Spec.expected_step(s, event)
    assert Ledger.step(s, event) == {{1000, 3, 300, 1, [{11, 300, :unknown}]}, :marked_unknown, []}
  end
end
