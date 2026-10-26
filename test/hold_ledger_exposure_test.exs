defmodule HoldLedger.ExposureTest do
  use ExUnit.Case, async: true
  use ExUnitProperties
  import StreamData
  alias HoldLedger.{Environment, Exposure, Ledger, Spec, TestGenerators}

  property "admissible delayed deliveries preserve coupling and remote coverage" do
    event =
      one_of([
        map(TestGenerators.event(), &{:local, &1}),
        map(fixed_list([integer(-5..5), member_of([:approved, :declined])]), fn [key, decision] ->
          {:authorize, key, decision}
        end),
        map({member_of([:void, :confirm, :observe]), integer(-5..5)}, fn {tag, key} ->
          {tag, key}
        end)
      ])

    check all(events <- list_of(event, max_length: 100), max_runs: 10_000) do
      initial =
        Exposure.run(Exposure.init(100, 3), [
          {:local, {:request, 1, 40}},
          {:local, {:dispatch, 1}},
          {:authorize, 1, :approved}
        ])

      Enum.reduce(events, initial, fn event, state ->
        {composite = {ledger, _}, remote} = next = Exposure.step(state, event)
        assert Spec.exposure_valid?(next)
        assert Spec.composite_valid?(composite)
        assert Environment.covered?(remote, ledger)
        active = for {_, amount, :approved} <- elem(remote, 1), do: amount
        assert Enum.sum(active) <= 100
        assert length(active) <= 3
        next
      end)
    end
  end

  test "duplicate authorization delivered after confirmation cannot resurrect exposure" do
    state =
      Exposure.run(Exposure.init(100, 2), [
        {:local, {:request, 1, 100}},
        {:local, {:dispatch, 1}},
        {:authorize, 1, :approved},
        {:observe, 1},
        {:local, {:void, 1}},
        {:void, 1},
        {:confirm, 1},
        {:authorize, 1, :approved},
        {:local, {:request, 2, 100}},
        {:local, {:dispatch, 2}},
        {:authorize, 2, :approved}
      ])

    {{ledger, []}, remote} = state
    assert Ledger.find(elem(ledger, 4), 1) == {:ok, {1, 100, :voided}}
    assert Ledger.find(elem(ledger, 4), 2) == {:ok, {2, 100, :sent}}
    assert {2, 100, :approved} in elem(remote, 1)
    assert Environment.covered?(remote, ledger)
    assert Enum.count(elem(remote, 1), &(elem(&1, 2) == :approved)) == 1
  end
end
