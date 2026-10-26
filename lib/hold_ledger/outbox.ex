defmodule HoldLedger.Outbox do
  @moduledoc """
  Pure tuple/list fold of pending remote void obligations.

  Each entry is `{key, durable_attempt_count, last_outcome}`. A key appears once;
  only the composite confirmation transition removes it. All failures retain it.
  """

  def open([], key), do: [{key, 0, :unattempted}]
  def open([{key, _, _} | _] = entries, key), do: entries
  def open([entry | rest], key), do: [entry | open(rest, key)]

  def fetch([], _), do: :not_found
  def fetch([{key, _, _} = entry | _], key), do: entry
  def fetch([_ | rest], key), do: fetch(rest, key)

  def remove([], _), do: []
  def remove([{key, _, _} | rest], key), do: rest
  def remove([entry | rest], key), do: [entry | remove(rest, key)]

  def fold([{key, n, _} | tail], {:void_attempt, key}),
    do: [{key, n + 1, :unattempted} | tail]

  def fold([{key, n, _} | tail], {:void_outcome, key, {:error, reason} = outcome})
      when reason in [
             :unavailable,
             :not_found,
             :timeout,
             :declined,
             :adapter_error,
             :adapter_exception,
             :adapter_exit,
             :unexpected_reply,
             :uncertain,
             :task_start_failed,
             :capacity,
             :task_down
           ],
      do: [{key, n, outcome} | tail]

  def fold([{key, _, outcome} | tail], {:void_retry_enabled, key}),
    do: [{key, 0, outcome} | tail]

  def fold([head | tail], event), do: [head | fold(tail, event)]
  def fold([], _), do: []

  def due([], _), do: []
  def due([{key, n, _} | tail], max) when n < max, do: [key | due(tail, max)]
  def due([_ | tail], max), do: due(tail, max)
end
