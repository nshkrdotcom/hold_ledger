defmodule HoldLedger.Attempts do
  @moduledoc """
  Pure lifecycle for runtime attempts, separate from the formally checked ledger.

  State is `{next_id, poisoned?, attempts}`; entries are `{id, kind, key, phase}`.
  Running attempts may produce a result or enter stopping on a deadline. Both
  results and completed shutdowns enter committing. Only a persistence
  acknowledgment retires an attempt and releases its slot. A failed persistence
  poisons the lifecycle. Runtime handles, clocks and I/O never enter this model.
  """

  def init, do: {1, false, []}

  def step({next, false, entries} = state, {:start, kind, key, limit})
      when kind in [:authorize, :void, :lookup] and is_integer(key) and
             is_integer(limit) and limit > 0 do
    if count(entries) < limit and not occupied?(entries, kind, key) do
      {{next + 1, false, [{next, kind, key, :running} | entries]}, [{:spawn, next}]}
    else
      {state, []}
    end
  end

  def step(state, {:deadline, id}), do: change(state, id, :running, :stopping, :shutdown)
  def step(state, {:result, id}), do: change(state, id, :running, :committing, :persist)
  def step(state, {:down, id}), do: change(state, id, :running, :committing, :persist)

  def step(state, {:shutdown_result, id}),
    do: change(state, id, :stopping, :committing, :persist)

  def step({next, poisoned, entries} = state, {:committed, id}) do
    case find(entries, id) do
      {:ok, {^id, _, _, :committing}} ->
        {{next, poisoned, remove(entries, id)}, [{:retire, id}]}

      _ ->
        {state, []}
    end
  end

  def step({next, _, entries}, :poison), do: {{next, true, entries}, []}
  def step(state, _), do: {state, []}

  def count({_, _, entries}), do: count(entries)
  def count([]), do: 0
  def count([_ | rest]), do: 1 + count(rest)

  def occupied?([], _, _), do: false
  def occupied?([{_, kind, key, _} | _], kind, key), do: true
  def occupied?([_ | rest], kind, key), do: occupied?(rest, kind, key)

  def entries({_, _, entries}), do: entries

  defp change({next, poisoned, entries} = state, id, from, to, intent) do
    case find(entries, id) do
      {:ok, {^id, kind, key, ^from}} ->
        {{next, poisoned, replace(entries, id, to)}, [{intent, id, kind, key}]}

      _ ->
        {state, []}
    end
  end

  defp find([], _), do: :not_found
  defp find([{id, _, _, _} = entry | _], id), do: {:ok, entry}
  defp find([_ | rest], id), do: find(rest, id)

  defp replace([{id, kind, key, _} | rest], id, phase),
    do: [{id, kind, key, phase} | rest]

  defp replace([head | rest], id, phase), do: [head | replace(rest, id, phase)]

  defp remove([], _), do: []
  defp remove([{id, _, _, _} | rest], id), do: rest
  defp remove([head | rest], id), do: [head | remove(rest, id)]
end
