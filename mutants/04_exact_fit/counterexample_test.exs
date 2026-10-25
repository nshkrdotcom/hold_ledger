defmodule HoldLedger.Mutants.M4CounterexampleTest do
  use ExUnit.Case, async: true
  alias HoldLedger.{Ledger, Spec}

  test "M4: rejects equality at remaining amount boundary" do
    s = {100, 1, 0, 0, []}
    event = {:request, 11, 100}
    assert Spec.valid?(s)
    assert Ledger.step(s, event) == Spec.expected_step(s, event)
    assert Ledger.step(s, event) == {{100, 1, 100, 1, [{11, 100, :reserved}]}, :admitted, []}
  end
end
