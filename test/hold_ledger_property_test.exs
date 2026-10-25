defmodule HoldLedger.PropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias HoldLedger.{Ledger, PropertyCoverage, Spec, TestFixtures, TestGenerators}

  # Candidate counts are measured by ETS in the executing ExUnit process.
  # Generators satisfy the law preconditions by construction; no filters,
  # property `such_that`, silent skips or reduced legal domains are used.
  # Bound recursive arbitrary-term growth while retaining all 10,000 candidates.
  @runs 10_000

  property "PO-I: every nonnegative pair of limits initializes a valid state" do
    tab = PropertyCoverage.start()

    check all(
            limits <- fixed_list([integer(0..100_000), integer(0..50)]),
            max_runs: @runs
          ) do
      [amount_cap, slot_cap] = limits
      s = Ledger.init(amount_cap, slot_cap)
      PropertyCoverage.hit(tab, amount_cap >= 0 and slot_cap >= 0)
      assert s == {amount_cap, slot_cap, 0, 0, []}
      assert Spec.valid?(s)
    end

    PropertyCoverage.report!(tab, "PO-I", @runs)
  end

  property "PO-A1: request preserves validity even for malformed arguments" do
    tab = PropertyCoverage.start()

    check all(
            {s, key, amount} <- TestGenerators.request_case(),
            max_runs: @runs
          ) do
      assert Spec.valid?(s)
      assert {new_s, result, effects} = Ledger.step(s, {:request, key, amount})
      PropertyCoverage.hit(tab, Spec.valid?(s), Spec.applied_result?(result))
      assert Spec.valid?(new_s)
      assert {new_s, result, effects} == Spec.expected_step(s, {:request, key, amount})
    end

    PropertyCoverage.report!(tab, "PO-A1", @runs)
  end

  property "PO-A2: positive admission including exact fit is compulsory" do
    tab = PropertyCoverage.start()

    check all(
            {s, key, amount} <- TestGenerators.eligible_request(),
            max_runs: @runs
          ) do
      PropertyCoverage.hit(tab, Spec.request_eligible?(s, key, amount), true)
      assert Spec.request_eligible?(s, key, amount)
      {cap, slots, used_amount, used_holds, entries} = s

      assert Ledger.step(s, {:request, key, amount}) ==
               {{cap, slots, used_amount + amount, used_holds + 1,
                 [{key, amount, :reserved} | entries]}, :admitted, []}
    end

    PropertyCoverage.report!(tab, "PO-A2", @runs)
  end

  property "PO-A3: any not-applied result preserves the exact ledger and emits nothing" do
    tab = PropertyCoverage.start()

    check all(
            {s, event} <- TestGenerators.rejection_case(),
            max_runs: @runs
          ) do
      assert Spec.valid?(s)
      {new_s, result, effects} = Ledger.step(s, event)
      PropertyCoverage.hit(tab, Spec.not_applied_result?(result))
      assert Spec.not_applied_result?(result)
      assert {new_s, effects} == {s, []}
      assert {new_s, result, effects} == Spec.expected_step(s, event)
    end

    PropertyCoverage.report!(tab, "PO-A3", @runs)
  end

  property "PO-A4: a seen key remains duplicate/conflict across every status" do
    tab = PropertyCoverage.start()

    check all(
            {s, event, same_or_different} <- TestGenerators.duplicate_request(),
            max_runs: @runs
          ) do
      assert Spec.valid?(s)
      {_tag, key, amount} = event
      original = elem(hd(elem(s, 4)), 1)
      PropertyCoverage.hit(tab, Spec.has_key?(elem(s, 4), key))
      expected = if same_or_different == :same, do: :duplicate, else: :conflict
      assert amount == original == (same_or_different == :same)
      assert Ledger.step(s, event) == {s, expected, []}
    end

    PropertyCoverage.report!(tab, "PO-A4", @runs)
  end

  for {event_type, name} <- [
        {:dispatch, "dispatch"},
        {:timeout, "timeout"},
        {:restart, "restart"},
        {:retry, "retry"},
        {:processor_result, "processor result"},
        {:void, "void"}
      ] do
    property "PO-B1/#{name}: each lifecycle operation preserves validity" do
      law = "PO-B1/#{unquote(event_type)}"
      tab = PropertyCoverage.start()

      check all(
              {s, event} <- TestGenerators.lifecycle_case(unquote(event_type)),
              max_runs: @runs
            ) do
        assert Spec.valid?(s)
        {new_s, result, effects} = Ledger.step(s, event)
        PropertyCoverage.hit(tab, Spec.valid?(s), Spec.applied_result?(result))
        assert Spec.valid?(new_s)
        assert {new_s, result, effects} == Spec.expected_step(s, event)
      end

      PropertyCoverage.report!(tab, law, @runs, require_applied: true)
    end
  end

  property "PO-B2: unknown contribution and identity survive until valid own result" do
    tab = PropertyCoverage.start()

    check all(
            {s, event} <- TestGenerators.unknown_non_result_case(),
            max_runs: @runs
          ) do
      assert Spec.valid?(s)
      {:ok, {11, amount, :unknown}} = Spec.lookup(elem(s, 4), 11)
      {next, result, effects} = Ledger.step(s, event)
      PropertyCoverage.hit(tab, Spec.holding?(:unknown), Spec.applied_result?(result))
      assert Spec.valid?(next)
      assert {next, result, effects} == Spec.expected_step(s, event)

      assert Spec.lookup(elem(next, 4), 11) in [
               {:ok, {11, amount, :unknown}},
               {:ok, {11, amount, :sent}}
             ]

      {:ok, {11, ^amount, next_status}} = Spec.lookup(elem(next, 4), 11)
      assert Spec.holding?(next_status)
      assert Spec.identity_preserved?(s, next)
      if event == {:retry, 11}, do: assert(result == :retried)
    end

    PropertyCoverage.report!(tab, "PO-B2", @runs)
  end

  property "PO-B3: every emitted effect is required and uses the original identity" do
    tab = PropertyCoverage.start()

    check all({s, event} <- TestGenerators.step_case(), max_runs: @runs) do
      assert Spec.valid?(s)
      {new_s, result, effects} = Ledger.step(s, event)
      PropertyCoverage.hit(tab, Spec.valid?(s), Spec.applied_result?(result))
      assert Spec.effects_valid?(s, event, new_s, result, effects)
      for effect <- effects, do: assert(Spec.effect_valid?(new_s, effect))
    end

    PropertyCoverage.report!(tab, "PO-B3", @runs)
  end

  property "PO-S: step with arbitrary term preserves the independent invariant" do
    tab = PropertyCoverage.start()

    check all({s, event} <- TestGenerators.step_case(), max_runs: @runs) do
      assert Spec.valid?(s)
      {new_s, result, effects} = Ledger.step(s, event)
      PropertyCoverage.hit(tab, Spec.valid?(s), Spec.applied_result?(result))
      assert Spec.valid?(new_s)
      assert {new_s, result, effects} == Spec.expected_step(s, event)
    end

    PropertyCoverage.report!(tab, "PO-S", @runs)
  end

  property "PO-C1: run on any finite event list returns valid state and matches oracle fold" do
    tab = PropertyCoverage.start()

    check all(
            s <- TestGenerators.initial(),
            events <- list_of(TestGenerators.event(), max_length: 40),
            max_runs: @runs
          ) do
      PropertyCoverage.hit(tab, Spec.valid?(s) and is_list(events))
      assert Spec.valid?(s)
      actual = Ledger.run(s, events)

      oracle =
        Enum.reduce(events, s, fn event, old ->
          {new_s, _, _} = Spec.expected_step(old, event)
          new_s
        end)

      assert actual == oracle
      assert Spec.valid?(actual)
    end

    PropertyCoverage.report!(tab, "PO-C1", @runs)
  end

  property "PO-C2: every replayed journal prefix is valid, not only the last one" do
    tab = PropertyCoverage.start()

    check all(
            limits <- fixed_list([integer(0..10_000), integer(0..5)]),
            events <- list_of(TestGenerators.event(), max_length: 24),
            max_runs: @runs
          ) do
      [amount_cap, slot_cap] = limits
      s = Ledger.init(amount_cap, slot_cap)
      PropertyCoverage.hit(tab, Spec.valid?(s) and is_list(events))

      for prefix_length <- 0..length(events) do
        assert Spec.valid?(Ledger.run(s, Enum.take(events, prefix_length)))
      end
    end

    PropertyCoverage.report!(tab, "PO-C2", @runs)
  end

  property "PO-B4: approval is possible only through a valid processor result" do
    tab = PropertyCoverage.start()

    check all({s, event} <- TestGenerators.step_case(), max_runs: @runs) do
      {new_s, result, _effects} = Ledger.step(s, event)
      PropertyCoverage.hit(tab, Spec.valid?(s), Spec.applied_result?(result))
      assert Spec.authorized_only_on_result?(s, event, new_s)
      if match?({:transport_ack, _}, event), do: assert(new_s == s)
    end

    PropertyCoverage.report!(tab, "PO-B4", @runs)
  end

  for status <- [:declined, :voided] do
    property "PO-B5/#{status}: terminal entry is absorbing under every next event" do
      tab = PropertyCoverage.start()
      law = "PO-B5/#{unquote(status)}"

      check all(
              s <- TestGenerators.with_status(unquote(status)),
              event <-
                one_of([
                  TestGenerators.event(),
                  TestGenerators.event_for_key(11),
                  constant(:restart)
                ]),
              max_runs: @runs
            ) do
        assert Spec.valid?(s)
        {next, result, _} = Ledger.step(s, event)
        PropertyCoverage.hit(tab, Spec.valid?(s), Spec.applied_result?(result))

        assert Spec.lookup(elem(next, 4), 11) ==
                 {:ok, {11, elem(hd(elem(s, 4)), 1), unquote(status)}}
      end

      PropertyCoverage.report!(tab, law, @runs)
    end
  end

  property "PO-B6: a key and its original amount cannot disappear or change" do
    tab = PropertyCoverage.start()

    check all({s, event} <- TestGenerators.step_case(), max_runs: @runs) do
      {next, result, _} = Ledger.step(s, event)
      PropertyCoverage.hit(tab, Spec.valid?(s), Spec.applied_result?(result))
      assert Spec.identity_preserved?(s, next)
      assert Spec.valid?(next)
    end

    PropertyCoverage.report!(tab, "PO-B6", @runs)
  end

  property "PO-B7: restart leaves zero sent entries" do
    tab = PropertyCoverage.start()

    check all(s <- TestGenerators.valid_state(), max_runs: @runs) do
      {next, :restarted, []} = Ledger.step(s, :restart)
      PropertyCoverage.hit(tab, Spec.valid?(s), true)
      assert Spec.valid?(next)
      refute Enum.any?(elem(next, 4), fn {_, _, status} -> status == :sent end)
    end

    PropertyCoverage.report!(tab, "PO-B7", @runs)
  end

  property "PO-C3: entry-local authorization, permanence and identity lift to histories" do
    tab = PropertyCoverage.start()

    check all(
            s <- TestGenerators.valid_state(),
            events <- list_of(TestGenerators.event(), max_length: 30),
            max_runs: @runs
          ) do
      PropertyCoverage.hit(tab, Spec.valid?(s) and is_list(events))

      final =
        Enum.reduce(events, s, fn event, old ->
          {next, _result, _effects} = Ledger.step(old, event)
          assert Spec.identity_preserved?(old, next)
          assert Spec.authorized_only_on_result?(old, event, next)

          for {key, amount, status} <- elem(old, 4), status in [:declined, :voided] do
            assert Spec.lookup(elem(next, 4), key) == {:ok, {key, amount, status}}
          end

          assert Spec.valid?(next)
          next
        end)

      assert final == Ledger.run(s, events)
      assert Spec.valid?(final)
    end

    PropertyCoverage.report!(tab, "PO-C3", @runs)
  end

  test "explicit fixture sanity and positive-acceptance anti-vacuity" do
    for s <- TestFixtures.all(), do: assert(Spec.valid?(s))
    assert Spec.request_eligible?(TestFixtures.exact_fit(), 11, 100)
    assert match?({_, :admitted, []}, Ledger.step(TestFixtures.exact_fit(), {:request, 11, 100}))
  end
end
