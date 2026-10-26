defmodule HoldLedger.WorkedTraceTest do
  use ExUnit.Case, async: true
  alias HoldLedger.{Ledger, Spec}

  test "ten exact worked transitions, including effect and result ordering" do
    states = [
      {10_000, 3, 0, 0, []},
      {10_000, 3, 7000, 1, [{11, 7000, :reserved}]},
      {10_000, 3, 7000, 1, [{11, 7000, :reserved}]},
      {10_000, 3, 7000, 1, [{11, 7000, :reserved}]},
      {10_000, 3, 7000, 1, [{11, 7000, :sent}]},
      {10_000, 3, 7000, 1, [{11, 7000, :unknown}]},
      {10_000, 3, 7000, 1, [{11, 7000, :sent}]},
      {10_000, 3, 7000, 1, [{11, 7000, :authorized}]},
      {10_000, 3, 7000, 1, [{11, 7000, :voiding}]},
      {10_000, 3, 0, 0, [{11, 7000, :voided}]},
      {10_000, 3, 0, 0, [{11, 7000, :voided}]}
    ]

    transitions = [
      {{:request, 11, 7000}, :admitted, []},
      {{:request, 12, 6000}, :insufficient_amount, []},
      {{:request, 11, 7000}, :duplicate, []},
      {{:dispatch, 11}, :dispatched, [{:authorize, 11, 7000}]},
      {{:timeout, 11}, :marked_unknown, []},
      {{:retry, 11}, :retried, [{:authorize, 11, 7000}]},
      {{:processor_result, 11, :approved}, :authorized, []},
      {{:void, 11}, :voiding, [{:void, 11}]},
      {{:void_confirmed, 11}, :voided, []},
      {{:request, 11, 7000}, :duplicate, []}
    ]

    assert hd(states) == Ledger.init(10_000, 3)

    for {before, {{event, result, effects}, after_state}} <-
          Enum.zip(states, Enum.zip(transitions, tl(states))) do
      assert Spec.valid?(before)
      assert Ledger.step(before, event) == {after_state, result, effects}
      assert Spec.effects_valid?(before, event, after_state, result, effects)
    end

    assert Ledger.run(hd(states), Enum.map(transitions, fn {event, _, _} -> event end)) ==
             List.last(states)
  end
end
