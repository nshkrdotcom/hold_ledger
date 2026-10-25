defmodule HoldLedger.Mutants.M6CounterexampleTest do
  use ExUnit.Case, async: true
  alias HoldLedger.{Ledger, Spec}

  test "M6: ack treated as authorization result" do
    s = {1000, 3, 300, 1, [{11, 300, :sent}]}
    event = {:transport_ack, 11}
    assert Spec.valid?(s)
    assert Ledger.step(s, event) == Spec.expected_step(s, event)
    assert Ledger.step(s, event) == {s, :stale, []}
  end
end
