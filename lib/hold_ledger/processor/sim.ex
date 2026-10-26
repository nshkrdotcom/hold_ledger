defmodule HoldLedger.Processor.Sim do
  @moduledoc """
  Deterministic receiver simulation, not a payment service.

  Faults are consumed in FIFO order per operation. Supported authorize faults:
  `:drop_before`, `:execute_then_drop`, `{:delay, milliseconds}`,
  `:duplicate_callback`, `{:out_of_order, outcomes}`. A lookup may be made
  unavailable with `:unavailable`; a void may fail with `:unavailable`.

  With `dedupe: false`, same-key retries create additional receiver holds.
  The simulated void completes *one* matching receiver hold, exhibiting an
  orphan when the receiver does not deduplicate. This is deliberately outside
  the ledger's proof boundary.
  """
  use GenServer
  @behaviour HoldLedger.Processor

  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name)
    GenServer.start_link(__MODULE__, opts, if(name, do: [name: name], else: []))
  end

  @impl true
  def init(opts) do
    {:ok,
     %{
       dedupe: Keyword.get(opts, :dedupe, true),
       tombstones: [],
       amounts: %{},
       decisions: Map.new(Keyword.get(opts, :decisions, [])),
       faults: %{authorize: [], lookup: [], void: []},
       records: [],
       attempts: [],
       voids: [],
       outcomes: %{}
     }}
  end

  @doc "Inject a single next-operation fault without clocks or random ordering."
  def queue_fault(server, operation, fault) when operation in [:authorize, :lookup, :void] do
    GenServer.call(server, {:fault, operation, fault})
  end

  def snapshot(server), do: GenServer.call(server, :snapshot)

  @impl HoldLedger.Processor
  def capabilities(server), do: GenServer.call(server, :capabilities)

  @impl HoldLedger.Processor
  def authorize(server, key, amount), do: GenServer.call(server, {:authorize, key, amount})

  @impl HoldLedger.Processor
  def lookup(server, key), do: GenServer.call(server, {:lookup, key})

  @impl HoldLedger.Processor
  def void(server, key), do: GenServer.call(server, {:void, key})

  @impl true
  def handle_call({:fault, op, fault}, _from, state) do
    {:reply, :ok, put_in(state, [:faults, op], state.faults[op] ++ [fault])}
  end

  def handle_call(:capabilities, _from, state) do
    declaration = %{
      terminal_confirmation: state.dedupe,
      non_resurrection: if(state.dedupe, do: :permanent, else: :unsupported)
    }

    {:reply, declaration, state}
  end

  def handle_call(:snapshot, _from, state) do
    records = Enum.reverse(state.records)

    {:reply,
     %{
       dedupe: state.dedupe,
       records: records,
       active: Enum.filter(records, &(&1.status == :active)),
       attempts: Enum.reverse(state.attempts),
       voids: Enum.reverse(state.voids)
     }, state}
  end

  def handle_call({:authorize, key, amount}, _from, state) do
    {fault, state} = take_fault(state, :authorize)
    state = %{state | attempts: [{key, amount, fault} | state.attempts]}

    if fault == :drop_before do
      {:reply, {:lost, :request}, state}
    else
      {decision, state} = execute_authorize(state, key, amount)

      reply =
        case {decision, fault} do
          {:identity_conflict, _} ->
            {:error, :identity_conflict}

          {_, :execute_then_drop} ->
            {:lost, :reply}

          {_, {:delay, milliseconds}} when is_integer(milliseconds) and milliseconds >= 0 ->
            {:delayed, milliseconds, {:ok, decision}}

          {_, :duplicate_callback} ->
            {:callbacks, [decision, decision]}

          {_, {:out_of_order, outcomes}} when is_list(outcomes) ->
            {:callbacks, outcomes}

          _ ->
            {:ok, decision}
        end

      {:reply, reply, state}
    end
  end

  def handle_call({:lookup, key}, _from, state) do
    {fault, state} = take_fault(state, :lookup)

    reply =
      cond do
        fault == :unavailable -> {:error, :unavailable}
        Map.has_key?(state.outcomes, key) -> {:ok, state.outcomes[key]}
        true -> :not_found
      end

    {:reply, reply, state}
  end

  def handle_call({:void, key}, _from, state) do
    {fault, state} = take_fault(state, :void)

    if fault == :unavailable do
      {:reply, {:error, :unavailable}, %{state | voids: [{key, :unavailable} | state.voids]}}
    else
      {found?, records} = void_one(state.records, key)
      outcome = if(found?, do: :voided, else: :already_voided)
      outcomes = if found?, do: Map.delete(state.outcomes, key), else: state.outcomes

      next = %{
        state
        | records: records,
          tombstones: Enum.uniq([key | state.tombstones]),
          voids: [{key, outcome} | state.voids],
          outcomes: outcomes
      }

      {:reply, {:ok, outcome}, next}
    end
  end

  defp take_fault(state, operation) do
    case state.faults[operation] do
      [fault | rest] -> {fault, put_in(state, [:faults, operation], rest)}
      [] -> {nil, state}
    end
  end

  defp execute_authorize(state, key, amount) do
    cond do
      state.dedupe and Map.has_key?(state.amounts, key) and state.amounts[key] != amount ->
        {:identity_conflict, state}

      key in state.tombstones ->
        {:declined, state}

      true ->
        authorize_unfenced(state, key, amount)
    end
  end

  defp authorize_unfenced(state, key, amount) do
    case Map.fetch(state.outcomes, key) do
      {:ok, previous} when state.dedupe ->
        {previous, state}

      _ ->
        decision = Map.get(state.decisions, key, :approved)

        records =
          if decision == :approved do
            [%{key: key, amount: amount, status: :active} | state.records]
          else
            state.records
          end

        {decision,
         %{
           state
           | records: records,
             amounts: Map.put(state.amounts, key, amount),
             outcomes: Map.put(state.outcomes, key, decision)
         }}
    end
  end

  defp void_one([], _key), do: {false, []}

  defp void_one([%{key: key, status: :active} = record | rest], key) do
    {true, [%{record | status: :voided} | rest]}
  end

  defp void_one([head | rest], key) do
    {found?, new_rest} = void_one(rest, key)
    {found?, [head | new_rest]}
  end
end
