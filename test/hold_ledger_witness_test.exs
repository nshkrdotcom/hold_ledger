defmodule HoldLedger.PreconditionWitnessTest do
  @moduledoc """
  Named, hand-built nonvacuity witnesses for every future proof obligation.
  Each input is checked for the independent invariant *before* use. These
  fixed inputs complement the generated properties in PropertyTest.
  """
  use ExUnit.Case, async: true
  alias HoldLedger.{Ledger, Spec, TestFixtures}

  test "PO-I: zero limits" do
    assert Spec.valid?(Ledger.init(0, 0))
  end

  test "PO-A1: valid state with malformed and valid request arguments" do
    s = TestFixtures.empty()
    assert Spec.valid?(s)
    assert {^s, :malformed, []} = Ledger.step(s, {:request, 11, :not_money})
    assert {next, :admitted, []} = Ledger.step(s, {:request, 11, 5})
    assert Spec.valid?(next)
  end

  test "PO-A2: independent, satisfiable exact-fit admission and counters" do
    s = TestFixtures.exact_fit()
    assert Spec.valid?(s)
    assert Spec.request_eligible?(s, 11, 100)

    assert Ledger.step(s, {:request, 11, 100}) ==
             {{100, 1, 100, 1, [{11, 100, :reserved}]}, :admitted, []}
  end

  test "PO-A3: a real not-applied duplicate returns exact input and no effects" do
    s = TestFixtures.declined()
    assert Spec.valid?(s)
    assert Spec.not_applied_result?(:duplicate)
    assert Ledger.step(s, {:request, 11, 300}) == {s, :duplicate, []}
  end

  test "PO-A4: both duplicate and conflict predicates hold for terminal keys" do
    s = TestFixtures.voided()
    assert Spec.valid?(s)
    assert Spec.has_key?(elem(s, 4), 11)
    assert Ledger.step(s, {:request, 11, 300}) == {s, :duplicate, []}
    assert Ledger.step(s, {:request, 11, 301}) == {s, :conflict, []}
  end

  test "PO-B1/dispatch: a reserved entry is reachable" do
    s = TestFixtures.reserved()
    assert Spec.valid?(s)
    assert Spec.lookup(elem(s, 4), 11) == {:ok, {11, 300, :reserved}}
    assert {next, :dispatched, [{:authorize, 11, 300}]} = Ledger.dispatch(s, 11)
    assert Spec.valid?(next)
  end

  test "PO-B1/timeout: a sent entry is reachable" do
    s = TestFixtures.sent()
    assert Spec.valid?(s)
    assert {next, :marked_unknown, []} = Ledger.timeout(s, 11)
    assert Spec.valid?(next)
  end

  test "PO-B1/restart: at least one sent entry must be converted" do
    s = TestFixtures.mixed()
    assert Spec.valid?(s)
    assert {next, :restarted, []} = Ledger.restart(s)
    assert Spec.lookup(elem(next, 4), 11) == {:ok, {11, 300, :unknown}}
    assert Spec.valid?(next)
  end

  test "PO-B1/retry: an unknown entry produces authorize intent" do
    s = TestFixtures.unknown()
    assert Spec.valid?(s)
    assert {next, :retried, [{:authorize, 11, 300}]} = Ledger.retry(s, 11)
    assert Spec.valid?(next)
  end

  test "PO-B1/processor_result: both approved and declined apply from a sent entry" do
    s = TestFixtures.sent()
    assert Spec.valid?(s)
    assert {yes, :authorized, []} = Ledger.processor_result(s, 11, :approved)
    assert {no, :declined, []} = Ledger.processor_result(s, 11, :declined)
    assert Spec.valid?(yes)
    assert Spec.valid?(no)
  end

  test "PO-B1/void: reserved releases and authorized retains capacity with intent" do
    reserved = TestFixtures.reserved()
    authorized = TestFixtures.authorized()
    assert Spec.valid?(reserved)
    assert Spec.valid?(authorized)
    assert {next1, :voided, []} = Ledger.void(reserved, 11)
    assert {next2, :voiding, [{:void, 11}]} = Ledger.void(authorized, 11)
    assert Spec.valid?(next1)
    assert Spec.valid?(next2)
  end

  test "PO-B2: unrelated request changes global totals without changing unknown entry" do
    s = TestFixtures.unknown()
    assert Spec.valid?(s)
    assert Spec.lookup(elem(s, 4), 11) == {:ok, {11, 300, :unknown}}
    assert {next, :admitted, []} = Ledger.step(s, {:request, 22, 1})
    assert elem(s, 2) != elem(next, 2)
    assert Spec.lookup(elem(next, 4), 11) == {:ok, {11, 300, :unknown}}
    assert Spec.valid?(next)
  end

  test "PO-B3: valid dispatch/void intents and rejected empty effects" do
    reserved = TestFixtures.reserved()
    authorized = TestFixtures.authorized()
    assert Spec.valid?(reserved)
    assert Spec.valid?(authorized)
    {sent, :dispatched, effects} = Ledger.step(reserved, {:dispatch, 11})
    assert Spec.effects_valid?(reserved, {:dispatch, 11}, sent, :dispatched, effects)
    {voiding, :voiding, void_effects} = Ledger.step(authorized, {:void, 11})
    assert Spec.effects_valid?(authorized, {:void, 11}, voiding, :voiding, void_effects)
    assert Spec.effects_valid?(reserved, {:request, 11, 300}, reserved, :duplicate, [])
  end

  test "PO-S: arbitrary invalid event is safe from an independently valid mixed state" do
    s = TestFixtures.mixed()
    assert Spec.valid?(s)
    assert Ledger.step(s, {:request, :malformed, :money}) == {s, :malformed, []}
    assert Spec.valid?(elem(Ledger.step(s, {:request, :malformed, :money}), 0))
  end

  test "PO-C1: a finite list with applied, stale and malformed events" do
    s = Ledger.init(100, 1)
    assert Spec.valid?(s)
    events = [{:request, 11, 100}, {:dispatch, 11}, {:transport_ack, 11}, nil]
    assert Ledger.run(s, events) == {100, 1, 100, 1, [{11, 100, :sent}]}
    assert Spec.valid?(Ledger.run(s, events))
  end

  test "PO-C2: every prefix of a valid bounded journal remains valid" do
    s = Ledger.init(100, 1)
    assert Spec.valid?(s)

    events = [
      {:request, 11, 100},
      {:dispatch, 11},
      :restart,
      {:retry, 11},
      {:processor_result, 11, :declined}
    ]

    for n <- 0..length(events), do: assert(Spec.valid?(Ledger.run(s, Enum.take(events, n))))
  end

  test "PO-B4: ack is not approval, but a valid processor result is" do
    s = TestFixtures.sent()
    assert Spec.valid?(s)
    {after_ack, :stale, []} = Ledger.step(s, {:transport_ack, 11})
    {after_approval, :authorized, []} = Ledger.step(s, {:processor_result, 11, :approved})
    assert Spec.authorized_only_on_result?(s, {:transport_ack, 11}, after_ack)
    assert Spec.authorized_only_on_result?(s, {:processor_result, 11, :approved}, after_approval)
  end

  test "PO-B5: both terminal statuses resist replay/restart/result attempts" do
    for s <- [TestFixtures.declined(), TestFixtures.voided()] do
      assert Spec.valid?(s)
      {:ok, original} = Spec.lookup(elem(s, 4), 11)

      for e <- [{:request, 11, 300}, {:processor_result, 11, :approved}, :restart] do
        {next, _, _} = Ledger.step(s, e)
        assert Spec.lookup(elem(next, 4), 11) == {:ok, original}
      end
    end
  end

  test "PO-B6: an original key and amount remain recorded after decline" do
    s = TestFixtures.unknown()
    assert Spec.valid?(s)
    {next, :declined, []} = Ledger.step(s, {:processor_result, 11, :declined})
    assert Spec.identity_preserved?(s, next)
    assert Spec.lookup(elem(next, 4), 11) == {:ok, {11, 300, :declined}}
  end

  test "PO-B7: restart eliminates sent while preserving holding counts" do
    s = TestFixtures.mixed()
    assert Spec.valid?(s)
    {next, :restarted, []} = Ledger.step(s, :restart)
    refute Enum.any?(elem(next, 4), fn {_, _, status} -> status == :sent end)
    assert elem(next, 2) == elem(s, 2)
    assert elem(next, 3) == elem(s, 3)
  end

  test "PO-C3: terminal status and identity persist through a representative history" do
    s = TestFixtures.sent()
    assert Spec.valid?(s)

    events = [
      {:timeout, 11},
      {:retry, 11},
      {:processor_result, 11, :declined},
      {:request, 11, 300},
      :restart,
      {:processor_result, 11, :approved}
    ]

    assert Ledger.run(s, events) == TestFixtures.declined()
    assert Spec.identity_preserved?(s, Ledger.run(s, events))
  end
end
