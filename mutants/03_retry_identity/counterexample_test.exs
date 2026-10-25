defmodule HoldLedger.Mutants.M3CounterexampleTest do
  use ExUnit.Case, async: true
  alias HoldLedger.{Ledger, Spec}

  test "M3: retry changes authorization identity" do
    s = {1000, 3, 300, 1, [{11, 300, :unknown}]}
    event = {:retry, 11}
    assert Spec.valid?(s)
    assert Ledger.step(s, event) == Spec.expected_step(s, event)
    assert Ledger.step(s, event) == {{1000, 3, 300, 1, [{11, 300, :sent}]}, :retried, [{:authorize, 11, 300}]}
  end
end
