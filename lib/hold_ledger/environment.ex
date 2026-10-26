defmodule HoldLedger.Environment do
  @moduledoc """
  Pure processor environment with terminal identity fencing.

  This is an assumption model, not verification of an external service. Issued
  identities keep their amount forever. Terminal voids reject delayed authorize
  deliveries, including a void delivered before the first authorization.
  """

  def init, do: {[], []}

  def issue({issued, remote} = state, {:authorize, key, amount})
      when is_integer(key) and is_integer(amount) and amount > 0 do
    case lookup(issued, key) do
      :not_found -> {[{key, amount, :issued} | issued], remote}
      {^key, ^amount, :issued} -> state
      _ -> state
    end
  end

  def issue(state, _), do: state

  def deliver({issued, remote} = state, {:authorize, key, outcome})
      when outcome in [:approved, :declined] do
    case lookup(remote, key) do
      {^key, _, :voided} ->
        {state, :declined}

      {^key, _, previous} ->
        {state, previous}

      :not_found ->
        case lookup(issued, key) do
          {^key, amount, :issued} ->
            {{issued, [{key, amount, outcome} | remote]}, outcome}

          :not_found ->
            {state, :not_issued}
        end
    end
  end

  def deliver({issued, remote}, {:void, key}) when is_integer(key) do
    amount =
      case lookup(issued, key) do
        {^key, amount, :issued} -> amount
        :not_found -> 0
      end

    {{issued, put(remote, key, amount, :voided)}, :void_confirmed}
  end

  def deliver(state, _), do: {state, :malformed}

  def lookup([], _), do: :not_found
  def lookup([{key, _, _} = entry | _], key), do: entry
  def lookup([_ | tail], key), do: lookup(tail, key)

  defp put([], key, amount, status), do: [{key, amount, status}]
  defp put([{key, amount, _} | rest], key, _, status), do: [{key, amount, status} | rest]
  defp put([entry | rest], key, amount, status), do: [entry | put(rest, key, amount, status)]

  @doc "Every live remote authorization is matched by a holding ledger entry."
  def covered?({_, remote}, {_, _, _, _, entries}), do: covered_entries?(remote, entries)
  defp covered_entries?([], _), do: true

  defp covered_entries?([{key, amount, :approved} | tail], entries) do
    case lookup(entries, key) do
      {^key, ^amount, status}
      when status in [:reserved, :sent, :unknown, :authorized, :voiding] ->
        covered_entries?(tail, entries)

      _ ->
        false
    end
  end

  defp covered_entries?([_ | tail], entries), do: covered_entries?(tail, entries)
end
