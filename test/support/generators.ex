defmodule HoldLedger.TestGenerators do
  @moduledoc """
  Property inputs with two independent state-construction routes:
  journal histories replayed through the reducer, AND literal/arithmetically
  built states never constructed by calling the reducer. A property always
  checks the independent state invariant before relying on its precondition.
  """
  import StreamData
  alias HoldLedger.{Ledger, TestFixtures}

  def key, do: frequency([{3, integer(-20..20)}, {1, member_of([0, -1, 11, 22, 100_000])}])

  def amount,
    do: frequency([{4, integer(1..10_000)}, {1, member_of([1, 100, 300, 7000, 10_000, 100_000])}])

  def status,
    do: member_of([:reserved, :sent, :unknown, :authorized, :voiding, :declined, :voided])

  def outcome, do: member_of([:approved, :declined])

  # StreamData 1.4.0 drops max_generation_size in check_all options;
  # bound recursive term construction explicitly at each arbitrary-term source.
  def malformed_event do
    one_of([
      constant(nil),
      constant(:unsupported),
      constant([]),
      constant([:an_event | :improper_tail]),
      constant({:restart}),
      constant({:dispatch, :non_integer}),
      constant({:timeout, "11"}),
      constant({:request, 11, 0}),
      constant({:request, 11, -1}),
      constant({:request, 11, 1.5}),
      constant({:request, :key, 3}),
      constant({:retry, :key}),
      constant({:void, :key}),
      constant({:void_confirmed, :key}),
      constant({:transport_ack, :key}),
      constant({:processor_result, 11, :unspecified}),
      constant({:processor_result, 11, :approved, :extra}),
      map(integer(-10..10), fn n -> {:bad, n} end),
      map(resize(term(), 20), fn t -> {:unknown_event, t} end)
    ])
  end

  def event_for_key(key) do
    one_of([
      map(amount(), fn a -> {:request, key, a} end),
      constant({:dispatch, key}),
      constant({:timeout, key}),
      constant({:retry, key}),
      constant({:void, key}),
      constant({:void_confirmed, key}),
      constant({:transport_ack, key}),
      map(outcome(), fn result -> {:processor_result, key, result} end)
    ])
  end

  def event do
    frequency([
      {6, bind(key(), &event_for_key/1)},
      {1, constant(:restart)},
      {4, malformed_event()},
      {1, resize(term(), 20)}
    ])
  end

  def initial do
    fixed_list([integer(0..20_000), integer(0..7)])
    |> map(fn [amount_cap, slot_cap] -> {amount_cap, slot_cap, 0, 0, []} end)
  end

  def history_state do
    bind(initial(), fn s ->
      map(list_of(event(), max_length: 30), fn events -> Ledger.run(s, events) end)
    end)
  end

  # Independent generator: keys are an arithmetic sequence; cached usage is
  # calculated by a local fixture constructor, not by Ledger or Spec helpers.
  def independent_state do
    bind(list_of(fixed_list([amount(), status()]), max_length: 8), fn raw ->
      map(
        fixed_list([integer(-100..100), integer(0..2000), integer(0..3)]),
        fn [start_key, amount_slack, slot_slack] ->
          {entries, amount_used, slot_used} = fixture_entries(raw, start_key)
          {amount_used + amount_slack, slot_used + slot_slack, amount_used, slot_used, entries}
        end
      )
    end)
  end

  defp fixture_entries([], _key), do: {[], 0, 0}

  defp fixture_entries([[amount, status] | tail], key) do
    {entries, used_amount, used_holds} = fixture_entries(tail, key + 1)

    if status in [:reserved, :sent, :unknown, :authorized, :voiding] do
      {[{key, amount, status} | entries], used_amount + amount, used_holds + 1}
    else
      {[{key, amount, status} | entries], used_amount, used_holds}
    end
  end

  def literal_state, do: member_of(TestFixtures.all())

  def valid_state do
    frequency([{3, independent_state()}, {2, history_state()}, {2, literal_state()}])
  end

  def step_case do
    bind(valid_state(), fn s ->
      step_case_for(s)
    end)
  end

  defp step_case_for(s) do
    entries = elem(s, 4)

    if entries == [] do
      map(event(), fn e -> {s, e} end)
    else
      existing = Enum.map(entries, fn {k, _, _} -> k end)

      frequency([
        {5, bind(member_of(existing), &state_event(s, &1))},
        {2, map(event(), fn e -> {s, e} end)},
        {2, map(malformed_event(), fn e -> {s, e} end)}
      ])
    end
  end

  defp state_event(state, key) do
    map(event_for_key(key), fn event -> {state, event} end)
  end

  def request_case do
    bind(valid_state(), fn s ->
      fixed_list([key(), one_of([amount(), integer(-100..0), resize(term(), 20)])])
      |> map(fn [k, a] -> {s, k, a} end)
    end)
  end

  # Every generated case satisfies the exact positive-admission precondition.
  # Include exact-fit and tight slot boundaries as distinct sampled branches.
  def eligible_request do
    bind(
      fixed_list([amount(), amount(), integer(0..10_000), integer(0..3), key()]),
      fn [a, earlier_amount, slack, slot_slack, key] ->
        member_of([
          {{a, 1, 0, 0, []}, key, a},
          {{a + slack, 1 + slot_slack, 0, 0, []}, key, a},
          {{a + slack, 1, 0, 0, []}, key, a},
          {{earlier_amount + a, 2 + slot_slack, earlier_amount, 1,
            [{key + 1, earlier_amount, :unknown}]}, key, a}
        ])
      end
    )
  end

  def duplicate_request do
    bind(
      fixed_list([amount(), status(), member_of([:same, :different])]),
      fn [amount, status, choice] ->
        amount_used =
          if status in [:reserved, :sent, :unknown, :authorized, :voiding], do: amount, else: 0

        holds_used = if amount_used == 0, do: 0, else: 1
        s = {amount + 5, 2, amount_used, holds_used, [{11, amount, status}]}
        request_amount = if choice == :same, do: amount, else: amount + 1
        constant({s, {:request, 11, request_amount}, choice})
      end
    )
  end

  def rejection_case do
    one_of([
      map(duplicate_request(), fn {s, event, _} -> {s, event} end),
      constant({TestFixtures.zero(), {:request, 1, 1}}),
      constant({TestFixtures.full_slots(), {:request, 99, 1}}),
      constant({TestFixtures.full_amount(), {:request, 99, 1}}),
      constant({TestFixtures.reserved(), {:dispatch, 99}}),
      constant({TestFixtures.declined(), {:dispatch, 11}}),
      constant({TestFixtures.sent(), {:transport_ack, 11}}),
      map(malformed_event(), fn event -> {TestFixtures.unknown(), event} end)
    ])
  end

  def with_status(status) do
    map(
      fixed_list([amount(), integer(0..10_000), integer(0..3)]),
      fn [amount, extra_amount, extra_slots] ->
        held = status in [:reserved, :sent, :unknown, :authorized, :voiding]
        used_amount = if held, do: amount, else: 0
        used_holds = if held, do: 1, else: 0

        {used_amount + extra_amount, used_holds + extra_slots, used_amount, used_holds,
         [{11, amount, status}]}
      end
    )
  end

  def unknown_non_result_case do
    bind(with_status(:unknown), fn s ->
      one_of([
        constant({s, {:request, 22, 1}}),
        constant({s, {:transport_ack, 11}}),
        constant({s, {:retry, 11}}),
        constant({s, :restart}),
        constant({s, {:processor_result, 22, :approved}}),
        map(malformed_event(), fn e -> {s, e} end)
      ])
    end)
  end

  # Roughly half of each lifecycle sample is deliberately in a state where
  # that operation actually applies. This avoids a vacuous not-found-only run.
  def lifecycle_case(:restart) do
    one_of([
      map(valid_state(), fn s -> {s, :restart} end),
      constant({TestFixtures.mixed(), :restart})
    ])
  end

  def lifecycle_case(:processor_result) do
    one_of([
      bind(with_status(:sent), fn s ->
        map(outcome(), fn result -> {s, {:processor_result, 11, result}} end)
      end),
      bind(with_status(:unknown), fn s ->
        map(outcome(), fn result -> {s, {:processor_result, 11, result}} end)
      end),
      random_lifecycle_case(:processor_result)
    ])
  end

  def lifecycle_case(tag) when tag in [:dispatch, :timeout, :retry, :void] do
    if tag == :void do
      one_of([
        map(with_status(:reserved), fn s -> {s, {:void, 11}} end),
        map(with_status(:authorized), fn s -> {s, {:void, 11}} end),
        random_lifecycle_case(tag)
      ])
    else
      status =
        case tag do
          :dispatch -> :reserved
          :timeout -> :sent
          :retry -> :unknown
        end

      one_of([
        map(with_status(status), fn s -> {s, {tag, 11}} end),
        random_lifecycle_case(tag)
      ])
    end
  end

  defp random_lifecycle_case(tag) do
    bind(valid_state(), fn s ->
      bind(key(), &lifecycle_event(s, &1, tag))
    end)
  end

  defp lifecycle_event(state, key, :processor_result) do
    map(outcome(), fn result -> {state, {:processor_result, key, result}} end)
  end

  defp lifecycle_event(state, key, tag), do: constant({state, {tag, key}})
end
