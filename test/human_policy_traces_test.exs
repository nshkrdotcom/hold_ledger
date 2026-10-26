defmodule HoldLedger.HumanPolicyTracesTest do
  use ExUnit.Case, async: true
  alias HoldLedger.Ledger

  test "exact amount and last slot fit must admit" do
    assert Ledger.step({100, 1, 0, 0, []}, {:request, 1, 100}) ==
             {{100, 1, 100, 1, [{1, 100, :reserved}]}, :admitted, []}
  end

  test "pending void retains capacity until confirmation, which releases only once" do
    initial = {100, 2, 100, 1, [{1, 100, :authorized}]}
    pending = {100, 2, 100, 1, [{1, 100, :voiding}]}
    released = {100, 2, 0, 0, [{1, 100, :voided}]}
    assert Ledger.step(initial, {:void, 1}) == {pending, :voiding, [{:void, 1}]}
    assert Ledger.step(pending, {:request, 2, 100}) == {pending, :insufficient_amount, []}
    assert Ledger.step(pending, {:void_confirmed, 1}) == {released, :voided, []}
    assert Ledger.step(released, {:void_confirmed, 1}) == {released, :stale, []}
    assert Ledger.step(released, {:request, 1, 100}) == {released, :duplicate, []}

    assert Ledger.step(released, {:request, 2, 100}) ==
             {{100, 2, 100, 1, [{2, 100, :reserved}, {1, 100, :voided}]}, :admitted, []}
  end

  test "timeout and restart both retain uncertain capacity" do
    sent = {100, 2, 100, 1, [{1, 100, :sent}]}
    unknown = {100, 2, 100, 1, [{1, 100, :unknown}]}
    assert Ledger.step(sent, {:timeout, 1}) == {unknown, :marked_unknown, []}
    assert Ledger.step(sent, :restart) == {unknown, :restarted, []}
    assert Ledger.step(unknown, {:request, 2, 100}) == {unknown, :insufficient_amount, []}
  end
end
