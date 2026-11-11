defmodule HoldLedger.Research.MapLedger do
  @moduledoc """
  Experimental, nonproduction map-backed reducer for representation research.

  This is NOT a replacement for `HoldLedger.Ledger`. No runtime, journal, proof
  law or public Ledger function routes through it. The supported domain is the
  original `HoldLedger.Spec.valid?/1` five-tuples and arbitrary event terms.

  Every key, including terminal tombstones, is retained in both `order` and
  `cells`. `order` is newest-first, matching the original list exactly; map
  iteration order is never used to decode or emit effects. The correspondence
  relation is `decode(candidate) === ledger_state` for valid candidates.
  Inputs outside that state domain are rejected at the encode boundary.

  This is an executable candidate, not a formally established simulation
  theorem or a claim of faster end-to-end journal/replay performance.
  """

  @enforce_keys [:amount_limit, :hold_limit, :used_amount, :used_holds, :order, :cells]
  defstruct @enforce_keys

  @statuses [:reserved, :sent, :unknown, :authorized, :voiding, :declined, :voided]
  @holding [:reserved, :sent, :unknown, :authorized, :voiding]

  @type cell :: {pos_integer(), HoldLedger.Ledger.status()}
  @type t :: %__MODULE__{
          amount_limit: non_neg_integer(),
          hold_limit: non_neg_integer(),
          used_amount: non_neg_integer(),
          used_holds: non_neg_integer(),
          order: [integer()],
          cells: %{integer() => cell()}
        }

  @doc "Encode a valid ordered Ledger state; reject all invalid states."
  @spec encode(HoldLedger.Ledger.state()) :: t()
  def encode({al, hl, used, count, entries} = state) do
    if valid_source?(state) do
      {reversed, cells} =
        Enum.reduce(entries, {[], %{}}, fn {key, amount, status}, {order, map} ->
          {[key | order], Map.put(map, key, {amount, status})}
        end)

      %__MODULE__{
        amount_limit: al,
        hold_limit: hl,
        used_amount: used,
        used_holds: count,
        order: Enum.reverse(reversed),
        cells: cells
      }
    else
      raise ArgumentError, "MapLedger.encode expects a valid ordered Ledger state"
    end
  end

  def encode(_), do: raise(ArgumentError, "MapLedger.encode expects a valid ordered Ledger state")

  @doc "Decode only a well-formed candidate to the exact original tuple and list."
  @spec decode(t()) :: HoldLedger.Ledger.state()
  def decode(%__MODULE__{} = state) do
    if valid?(state) do
      entries =
        Enum.map(state.order, fn key ->
          {amount, status} = Map.fetch!(state.cells, key)
          {key, amount, status}
        end)

      {state.amount_limit, state.hold_limit, state.used_amount, state.used_holds, entries}
    else
      raise ArgumentError, "MapLedger.decode expects a valid candidate"
    end
  end

  def decode(_), do: raise(ArgumentError, "MapLedger.decode expects a valid candidate")

  @doc "Verify the key bijection, status/amount shape and exact cached counters."
  @spec valid?(term()) :: boolean()
  def valid?(%__MODULE__{
        amount_limit: al,
        hold_limit: hl,
        used_amount: used,
        used_holds: count,
        order: order,
        cells: cells
      })
      when is_integer(al) and al >= 0 and is_integer(hl) and hl >= 0 and
             is_integer(used) and used >= 0 and used <= al and
             is_integer(count) and count >= 0 and count <= hl and
             is_list(order) and is_map(cells) do
    case inspect_order(order, cells, %{}, 0, 0) do
      {:ok, n, sum, holds} ->
        n == map_size(cells) and sum == used and holds == count

      :error ->
        false
    end
  end

  def valid?(_), do: false

  @doc """
  Lookup retaining numeric `==` compatibility for broad helper callers.

  Integer event keys use exact map lookup. A float `1.0` must still find an
  encoded integer key `1`, just as `Ledger.find/2` does; map lookup alone would
  be wrong on that separate, non-event helper domain.
  """
  @spec find(t(), term()) :: {:ok, HoldLedger.Ledger.entry()} | :not_found
  def find(%__MODULE__{cells: cells}, key) when is_integer(key) do
    case Map.fetch(cells, key) do
      {:ok, {amount, status}} -> {:ok, {key, amount, status}}
      :error -> :not_found
    end
  end

  def find(%__MODULE__{order: order, cells: cells}, key) do
    Enum.reduce_while(order, :not_found, fn existing_key, _ ->
      if existing_key == key do
        {amount, status} = Map.fetch!(cells, existing_key)
        {:halt, {:ok, {existing_key, amount, status}}}
      else
        {:cont, :not_found}
      end
    end)
  end

  @doc "Independent candidate transition, for valid encoded states only."
  @spec step(t(), term()) :: {t(), atom(), list()}
  def step(%__MODULE__{} = state, {:request, key, amount})
      when is_integer(key) and is_integer(amount) and amount > 0 do
    case Map.fetch(state.cells, key) do
      {:ok, {^amount, _status}} ->
        {state, :duplicate, []}

      {:ok, _} ->
        {state, :conflict, []}

      :error ->
        cond do
          state.used_holds >= state.hold_limit ->
            {state, :insufficient_holds, []}

          amount > state.amount_limit - state.used_amount ->
            {state, :insufficient_amount, []}

          true ->
            next = %{
              state
              | used_amount: state.used_amount + amount,
                used_holds: state.used_holds + 1,
                order: [key | state.order],
                cells: Map.put(state.cells, key, {amount, :reserved})
            }

            {next, :admitted, []}
        end
    end
  end

  def step(%__MODULE__{} = state, {:request, _key, _amount}), do: {state, :malformed, []}

  def step(%__MODULE__{} = state, {:dispatch, key}) when is_integer(key) do
    case Map.fetch(state.cells, key) do
      {:ok, {amount, :reserved}} ->
        {change_status(state, key, :sent), :dispatched, [{:authorize, key, amount}]}

      :error ->
        {state, :not_found, []}

      _ ->
        {state, :stale, []}
    end
  end

  def step(%__MODULE__{} = state, {:dispatch, _}), do: {state, :malformed, []}

  def step(%__MODULE__{} = state, {:timeout, key}) when is_integer(key) do
    case Map.fetch(state.cells, key) do
      {:ok, {_amount, :sent}} -> {change_status(state, key, :unknown), :marked_unknown, []}
      :error -> {state, :not_found, []}
      _ -> {state, :stale, []}
    end
  end

  def step(%__MODULE__{} = state, {:timeout, _}), do: {state, :malformed, []}

  def step(%__MODULE__{} = state, :restart) do
    cells =
      Map.new(state.cells, fn
        {key, {amount, :sent}} -> {key, {amount, :unknown}}
        other -> other
      end)

    {%{state | cells: cells}, :restarted, []}
  end

  def step(%__MODULE__{} = state, {:retry, key}) when is_integer(key) do
    case Map.fetch(state.cells, key) do
      {:ok, {amount, :unknown}} ->
        {change_status(state, key, :sent), :retried, [{:authorize, key, amount}]}

      :error ->
        {state, :not_found, []}

      _ ->
        {state, :stale, []}
    end
  end

  def step(%__MODULE__{} = state, {:retry, _}), do: {state, :malformed, []}

  def step(%__MODULE__{} = state, {:processor_result, key, outcome})
      when is_integer(key) and outcome in [:approved, :declined] do
    case Map.fetch(state.cells, key) do
      {:ok, {_amount, status}} when status in [:sent, :unknown] and outcome == :approved ->
        {change_status(state, key, :authorized), :authorized, []}

      {:ok, {amount, status}} when status in [:sent, :unknown] ->
        next = change_status(state, key, :declined)
        {%{next | used_amount: next.used_amount - amount, used_holds: next.used_holds - 1},
         :declined, []}

      :error ->
        {state, :not_found, []}

      _ ->
        {state, :stale, []}
    end
  end

  def step(%__MODULE__{} = state, {:processor_result, _, _}),
    do: {state, :malformed, []}

  def step(%__MODULE__{} = state, {:void, key}) when is_integer(key) do
    case Map.fetch(state.cells, key) do
      {:ok, {amount, :reserved}} ->
        next = change_status(state, key, :voided)
        {%{next | used_amount: next.used_amount - amount, used_holds: next.used_holds - 1},
         :voided, []}

      {:ok, {_amount, :authorized}} ->
        {change_status(state, key, :voiding), :voiding, [{:void, key}]}

      :error ->
        {state, :not_found, []}

      _ ->
        {state, :stale, []}
    end
  end

  def step(%__MODULE__{} = state, {:void, _}), do: {state, :malformed, []}

  def step(%__MODULE__{} = state, {:void_confirmed, key}) when is_integer(key) do
    case Map.fetch(state.cells, key) do
      {:ok, {amount, :voiding}} ->
        next = change_status(state, key, :voided)
        {%{next | used_amount: next.used_amount - amount, used_holds: next.used_holds - 1},
         :voided, []}

      :error ->
        {state, :not_found, []}

      _ ->
        {state, :stale, []}
    end
  end

  def step(%__MODULE__{} = state, {:void_confirmed, _}), do: {state, :malformed, []}

  def step(%__MODULE__{} = state, {:transport_ack, key}) when is_integer(key),
    do: {state, :stale, []}

  def step(%__MODULE__{} = state, {:transport_ack, _}), do: {state, :malformed, []}
  def step(%__MODULE__{} = state, _), do: {state, :malformed, []}

  @doc "Run a proper finite event list, preserving every decoded state prefix."
  @spec run(t(), list()) :: t()
  def run(state, []), do: state

  def run(state, [event | rest]) do
    {next, _result, _effects} = step(state, event)
    run(next, rest)
  end

  defp change_status(%__MODULE__{} = state, key, status) do
    %{state | cells: Map.update!(state.cells, key, fn {amount, _} -> {amount, status} end)}
  end

  defp valid_source?({al, hl, used, count, entries})
       when is_integer(al) and al >= 0 and is_integer(hl) and hl >= 0 and
              is_integer(used) and used >= 0 and used <= al and
              is_integer(count) and count >= 0 and count <= hl do
    case inspect_source(entries, %{}, 0, 0) do
      {:ok, ^used, ^count} -> true
      _ -> false
    end
  end

  defp valid_source?(_), do: false

  defp inspect_source([], _seen, used, count), do: {:ok, used, count}

  defp inspect_source([{key, amount, status} | rest], seen, used, count)
       when is_integer(key) and is_integer(amount) and amount > 0 and status in @statuses do
    if Map.has_key?(seen, key) do
      :error
    else
      if status in @holding do
        inspect_source(rest, Map.put(seen, key, true), used + amount, count + 1)
      else
        inspect_source(rest, Map.put(seen, key, true), used, count)
      end
    end
  end

  defp inspect_source(_, _, _, _), do: :error

  defp inspect_order([], _cells, seen, used, count),
    do: {:ok, map_size(seen), used, count}

  defp inspect_order([key | tail], cells, seen, used, count) when is_integer(key) do
    case Map.fetch(cells, key) do
      {:ok, {amount, status}}
      when is_integer(amount) and amount > 0 and status in @statuses ->
        if Map.has_key?(seen, key) do
          :error
        else
          if status in @holding do
            inspect_order(tail, cells, Map.put(seen, key, true), used + amount, count + 1)
          else
            inspect_order(tail, cells, Map.put(seen, key, true), used, count)
          end
        end

      _ ->
        :error
    end
  end

  defp inspect_order(_, _, _, _, _), do: :error
end
