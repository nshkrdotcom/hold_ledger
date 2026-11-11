Code.require_file("../verification/research/0300_map_ledger.ex", __DIR__)

defmodule HoldLedger.MapEquivalenceTest do
  @moduledoc false
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias HoldLedger.{Ledger, Spec, TestFixtures, TestGenerators}
  alias HoldLedger.Research.MapLedger

  @moduletag :phase4_research

  test "literal policy vectors distinguish results, ordered effects and tombstones" do
    for {state, event, expected_state, expected_result, expected_effects} <-
          TestFixtures.map_boundary_cases() do
      assert Spec.valid?(state)
      assert Spec.valid?(expected_state)
      encoded = MapLedger.encode(state)
      assert MapLedger.valid?(encoded)

      assert {expected_state, expected_result, expected_effects} ===
               Spec.expected_step(state, event)

      assert {expected_state, expected_result, expected_effects} === Ledger.step(state, event)

      {next, result, effects} = MapLedger.step(encoded, event)
      assert MapLedger.valid?(next)

      assert {MapLedger.decode(next), result, effects} ===
               {expected_state, expected_result, expected_effects}
    end
  end

  test "encoding preserves every ordered entry and cached counter" do
    for source <- TestFixtures.all() do
      assert Spec.valid?(source)
      encoded = MapLedger.encode(source)
      assert MapLedger.valid?(encoded)
      assert MapLedger.decode(encoded) === source
      assert encoded.order === Enum.map(elem(source, 4), &elem(&1, 0))
      assert map_size(encoded.cells) == length(encoded.order)
    end
  end

  test "invalid states and map order/cell counter corruptions fail closed" do
    for invalid <- [
          :not_a_ledger,
          {1, 1, 0, 0, [{1, 1, :declined}, {1, 1, :voided}]},
          {1, 1, 0, 0, [{1.0, 1, :declined}]},
          {1, 1, 0, 0, [{1, 0, :declined}]},
          {1, 1, 0, 0, [{1, 1, :invented}]},
          {1, 1, 0, 0, [{1, 1, :reserved}]},
          {1, 1, 1, 1, [{1, 1, :declined}]},
          {1, 1, 0, 0, [{1, 1, :declined} | :improper]},
          {0, 0, 0, 0, %{}}
        ] do
      refute Spec.valid?(invalid)
      assert_raise ArgumentError, fn -> MapLedger.encode(invalid) end
    end

    encoded = MapLedger.encode(TestFixtures.mixed())

    for broken <- [
          %{encoded | order: Enum.reverse(encoded.order) ++ [11]},
          %{encoded | order: tl(encoded.order)},
          %{encoded | cells: Map.put(encoded.cells, 999, {4, :voided})},
          %{encoded | cells: Map.delete(encoded.cells, 11)},
          %{encoded | cells: Map.put(encoded.cells, 11, {0, :sent})},
          %{encoded | cells: Map.put(encoded.cells, 11, {300, :nonsense})},
          %{encoded | used_amount: encoded.used_amount - 1},
          %{encoded | used_holds: encoded.used_holds - 1},
          %{encoded | order: [11 | :improper]}
        ] do
      refute MapLedger.valid?(broken)
      assert_raise ArgumentError, fn -> MapLedger.decode(broken) end
    end

    refute MapLedger.valid?(:not_a_map_candidate)
    assert_raise ArgumentError, fn -> MapLedger.decode(%{}) end
  end

  test "integer map-key exactness must not break broad numeric helper lookup" do
    source = {10, 2, 2, 1, [{1, 2, :reserved}, {2, 3, :voided}]}
    assert Spec.valid?(source)
    encoded = MapLedger.encode(source)

    for key <- [1, 1.0, 2, 2.0, 3, 3.0, :key, nil, %{a: 1}, [1]] do
      assert MapLedger.find(encoded, key) === Ledger.find(elem(source, 4), key)
      assert MapLedger.find(encoded, key) === Spec.lookup(elem(source, 4), key)
    end

    assert Map.fetch(encoded.cells, 1.0) === :error
    assert MapLedger.find(encoded, 1.0) === {:ok, {1, 2, :reserved}}
    assert MapLedger.find(encoded, 2.0) === {:ok, {2, 3, :voided}}
  end

  test "replay/restart does not reassign known keys or release uncertain capacity" do
    events = [
      {:request, 7, 40},
      {:request, 8, 30},
      {:dispatch, 7},
      {:dispatch, 8},
      :restart,
      {:retry, 7},
      {:processor_result, 7, :approved},
      {:void, 7},
      :restart,
      {:void_confirmed, 7},
      {:processor_result, 8, :declined},
      {:request, 7, 40},
      {:request, 7, 41},
      {:transport_ack, 8}
    ]

    initial = {100, 2, 0, 0, []}
    expected = {100, 2, 0, 0, [{8, 30, :declined}, {7, 40, :voided}]}
    assert MapLedger.decode(MapLedger.run(MapLedger.encode(initial), events)) === expected
    assert Ledger.run(initial, events) === expected
    assert Spec.valid?(expected)

    Enum.reduce(events, {initial, MapLedger.encode(initial)}, fn event, {old, candidate} ->
      {next_old, expected_result, expected_effects} = Spec.expected_step(old, event)
      {next_candidate, result, effects} = MapLedger.step(candidate, event)

      assert {MapLedger.decode(next_candidate), result, effects} ===
               {next_old, expected_result, expected_effects}

      assert Spec.identity_preserved?(old, next_old)
      {next_old, next_candidate}
    end)
  end

  property "independent valid states round-trip with strict list order and key bijection" do
    check all(state <- TestGenerators.valid_state(), max_runs: 2_000) do
      assert Spec.valid?(state)
      candidate = MapLedger.encode(state)
      assert MapLedger.valid?(candidate)
      assert MapLedger.decode(candidate) === state
    end
  end

  property "each event is a forward simulation of the independent specification" do
    check all({state, event} <- TestGenerators.map_candidate_step_case(), max_runs: 3_000) do
      assert Spec.valid?(state)
      candidate = MapLedger.encode(state)
      {next_candidate, result, effects} = MapLedger.step(candidate, event)
      {reference_state, reference_result, reference_effects} = Spec.expected_step(state, event)
      assert MapLedger.valid?(next_candidate)

      assert {MapLedger.decode(next_candidate), result, effects} ===
               {reference_state, reference_result, reference_effects}

      assert {reference_state, reference_result, reference_effects} === Ledger.step(state, event)
      assert Spec.valid?(reference_state)
      assert Spec.identity_preserved?(state, reference_state)
      assert Spec.effects_valid?(state, event, reference_state, result, effects)
    end
  end

  property "finite histories simulate every prefix including arbitrary malformed events" do
    check all(
            state <- TestGenerators.valid_state(),
            events <- list_of(TestGenerators.map_candidate_event(), max_length: 35),
            max_runs: 1_200
          ) do
      {reference, candidate} =
        Enum.reduce(events, {state, MapLedger.encode(state)}, fn event, {old, candidate} ->
          {next, expected_result, expected_effects} = Spec.expected_step(old, event)
          {mapped, result, effects} = MapLedger.step(candidate, event)

          assert {MapLedger.decode(mapped), result, effects} ===
                   {next, expected_result, expected_effects}

          assert Spec.valid?(next)
          {next, mapped}
        end)

      assert MapLedger.decode(MapLedger.run(MapLedger.encode(state), events)) === reference
      assert Ledger.run(state, events) === reference
      assert MapLedger.decode(candidate) === reference
    end
  end
end
