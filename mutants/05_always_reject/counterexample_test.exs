defmodule HoldLedger.Mutants.M5CounterexampleTest do
  use ExUnit.Case, async: true
  alias HoldLedger.{Ledger, Spec}

  test "M5: rejects every otherwise eligible request" do
    s = {1000, 3, 0, 0, []}
    event = {:request, 22, 100}
    assert Spec.valid?(s)
    assert Ledger.step(s, event) == Spec.expected_step(s, event)
    assert Ledger.step(s, event) == {{1000, 3, 100, 1, [{22, 100, :reserved}]}, :admitted, []}
  end
end
