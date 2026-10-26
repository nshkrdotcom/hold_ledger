defmodule HoldLedger.SpecTest do
  use ExUnit.Case, async: true
  alias HoldLedger.{Spec, TestFixtures}

  test "all standalone fixtures satisfy the independent invariant" do
    for s <- TestFixtures.all() do
      assert Spec.valid?(s), inspect(s)
    end
  end

  test "counter semantics include authorized and unknown, exclude both terminals" do
    entries = elem(TestFixtures.mixed(), 4)
    assert Spec.holding?(:authorized)
    assert Spec.holding?(:unknown)
    refute Spec.holding?(:voided)
    refute Spec.holding?(:declined)
    assert Spec.hold_amount(entries) == 700
    assert Spec.hold_count(entries) == 3
    assert Spec.lookup(entries, 13) == {:ok, {13, 200, :authorized}}
    assert Spec.lookup(entries, 99) == :not_found
    assert Spec.has_key?(entries, 15)
    refute Spec.has_key?(entries, 16)
    assert Spec.unique_keys?(entries)
    assert Spec.proper_entries?(entries)
  end

  test "invalid state shape, improper entries, duplicate terminal keys, counters, caps" do
    invalid = [
      nil,
      {},
      {1, 1, 0, 0},
      {1, 1, 0, 0, [], :extra},
      {0.0, 2, 0, 0, []},
      {1, :limit, 0, 0, []},
      {-1, 1, 0, 0, []},
      {1, -1, 0, 0, []},
      {1, 1, -1, 0, []},
      {1, 1, 0, -1, []},
      {1, 1, 0, 0, :bad},
      {1, 1, 0, 0, [{11, 1, :declined} | :bad_tail]},
      {1, 1, 0, 0, [{11, 1, :declined}, {11, 1, :voided}]},
      {1, 1, 0, 0, [{11, 0, :declined}]},
      {1, 1, 0, 0, [{:key, 1, :declined}]},
      {1, 1, 0, 0, [{11, 1, :complete}]},
      {1, 1, 0, 0, [{11, 1}]},
      {1, 1, 0, 0, [nil]},
      {1, 1, 0, 0, [{11, 1, :reserved}]},
      {1, 1, 1, 0, [{11, 1, :reserved}]},
      {1, 1, 1, 1, []},
      {0, 1, 1, 1, [{11, 1, :reserved}]},
      {1, 0, 1, 1, [{11, 1, :reserved}]}
    ]

    for bad <- invalid do
      refute Spec.valid?(bad), inspect(bad)
    end

    refute Spec.proper_entries?([{1, 1, :sent} | :improper])
    refute Spec.unique_keys?([{1, 1, :declined}, {1, 2, :voided}])
  end

  test "result and effect predicates enforce original identity, no rejected effects" do
    assert Spec.applied_result?(:admitted)
    assert Spec.applied_result?(:authorized)
    refute Spec.applied_result?(:duplicate)
    assert Spec.not_applied_result?(:duplicate)
    assert Spec.not_applied_result?(:malformed)
    refute Spec.not_applied_result?(:admitted)
    refute Spec.applied_result?(:unknown)

    before = TestFixtures.reserved()
    after_state = TestFixtures.sent()
    assert Spec.effect_valid?(after_state, {:authorize, 11, 300})
    refute Spec.effect_valid?(after_state, {:authorize, 11, 301})
    refute Spec.effect_valid?(after_state, {:authorize, 12, 300})
    refute Spec.effect_valid?(after_state, {:void, 11})

    assert Spec.effects_valid?(before, {:dispatch, 11}, after_state, :dispatched, [
             {:authorize, 11, 300}
           ])

    refute Spec.effects_valid?(before, {:dispatch, 11}, after_state, :dispatched, [
             {:authorize, 12, 300}
           ])

    refute Spec.effects_valid?(before, {:dispatch, 11}, after_state, :dispatched, [
             {:authorize, 11, 301}
           ])

    refute Spec.effects_valid?(before, {:dispatch, 11}, after_state, :dispatched, [])
    refute Spec.effects_valid?(before, {:dispatch, 11}, after_state, :duplicate, [])
    assert Spec.effects_valid?(before, {:request, 11, 300}, before, :duplicate, [])

    refute Spec.effects_valid?(before, {:request, 11, 300}, before, :duplicate, [
             {:authorize, 11, 300}
           ])

    assert Spec.effect_valid?(TestFixtures.voiding(), {:void, 11})
    refute Spec.effect_valid?(TestFixtures.voided(), {:void, 11})
  end
end
