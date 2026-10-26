defmodule HoldLedger.CompositeTest do
  use ExUnit.Case, async: true
  use ExUnitProperties
  alias HoldLedger.{Composite, Environment, Ledger, Spec, TestGenerators}

  test "deferred void keeps capacity and blocks the remote-200/local-100 witness" do
    initial = Composite.init(100, 2)
    events = [{:request, 1, 100}, {:dispatch, 1}, {:processor_result, 1, :approved}, {:void, 1}]
    {ledger, obligations} = pending = Composite.run(initial, events)
    assert ledger == {100, 2, 100, 1, [{1, 100, :voiding}]}
    assert obligations == [{1, 0, :unattempted}]
    assert {^pending, :insufficient_amount, []} = Composite.step(pending, {:request, 2, 100})
    {completed, :voided, []} = Composite.step(pending, {:void_confirmed, 1})
    assert Spec.composite_valid?(completed)
    assert {_, :admitted, []} = Composite.step(completed, {:request, 2, 100})
    assert {^completed, :stale, []} = Composite.step(completed, {:void_confirmed, 1})
  end

  test "independent invariant rejects missing, extra and duplicate obligations" do
    ledger = {100, 2, 100, 1, [{1, 100, :voiding}]}
    assert Spec.composite_valid?({ledger, [{1, 0, :unattempted}]})
    refute Spec.composite_valid?({ledger, []})
    refute Spec.composite_valid?({ledger, [{2, 0, :unattempted}]})
    refute Spec.composite_valid?({ledger, [{1, 0, :unattempted}, {1, 0, :unattempted}]})
  end

  property "every composite prefix agrees with the independent oracle and preserves coupling" do
    check all(events <- list_of(TestGenerators.event(), max_length: 60), max_runs: 10_000) do
      initial = Composite.init(1000, 5)
      assert Composite.run(initial, events) == Spec.expected_composite_run(initial, events)

      Enum.reduce(events, initial, fn event, state ->
        assert Spec.composite_valid?(state)
        actual = Composite.step(state, event)
        assert actual == Spec.expected_composite_step(state, event)
        {next, _, _} = actual
        assert Spec.composite_valid?(next)
        next
      end)
    end
  end

  property "independently constructed composite states agree on metadata and arbitrary inputs" do
    state =
      StreamData.map(TestGenerators.independent_state(), fn ledger ->
        obligations = for {key, _, :voiding} <- elem(ledger, 4), do: {key, 3, {:error, :timeout}}
        {ledger, Enum.reverse(obligations)}
      end)

    event =
      one_of([
        TestGenerators.event(),
        member_of([
          {:void_outcome, 1, {:error, :made_up}},
          {:void_attempt, 1},
          {:void_outcome, 1, {:error, :timeout}},
          {:void_retry_enabled, 1}
        ])
      ])

    check all(state <- state, event <- event, max_runs: 10_000) do
      assert Spec.composite_valid?(state)
      assert Composite.step(state, event) == Spec.expected_composite_step(state, event)
      assert Spec.composite_valid?(elem(Composite.step(state, event), 0))
    end
  end

  test "truthful remote deliveries maintain coverage through void and duplicate authorization" do
    remote = Environment.issue(Environment.init(), {:authorize, 1, 100})
    {remote, :approved} = Environment.deliver(remote, {:authorize, 1, :approved})

    ledger =
      Ledger.run(Ledger.init(100, 1), [
        {:request, 1, 100},
        {:dispatch, 1},
        {:processor_result, 1, :approved},
        {:void, 1}
      ])

    assert Environment.covered?(remote, ledger)
    {remote, :void_confirmed} = Environment.deliver(remote, {:void, 1})
    {ledger, :voided, []} = Ledger.step(ledger, {:void_confirmed, 1})
    {remote, :declined} = Environment.deliver(remote, {:authorize, 1, :approved})
    assert Environment.covered?(remote, ledger)
  end
end
