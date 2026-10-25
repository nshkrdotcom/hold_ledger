defmodule HoldLedger.Mutants.M1CounterexampleTest do
  use ExUnit.Case, async: true
  alias HoldLedger.{Ledger, Spec}

  test "M1: terminal reuse / duplicate key" do
    s = {1000, 3, 0, 0, [{11, 300, :voided}]}
    event = {:request, 11, 300}
    assert Spec.valid?(s)
    assert Ledger.step(s, event) == Spec.expected_step(s, event)
    assert Ledger.step(s, event) == {s, :duplicate, []}
  end
end
