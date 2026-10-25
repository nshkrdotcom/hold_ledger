defmodule HoldLedger.ControlledProcessor do
  @moduledoc false
  @behaviour HoldLedger.Processor

  def start_link(opts),
    do:
      Agent.start_link(fn ->
        %{owner: Keyword.fetch!(opts, :owner), modes: Keyword.get(opts, :modes, %{})}
      end)

  def authorize(target, key, _), do: perform(target, :authorize, key, {:ok, :approved})
  def void(target, key), do: perform(target, :void, key, {:ok, :voided})
  def lookup(target, key), do: perform(target, :lookup, key, :not_found)

  defp perform(target, kind, key, default) do
    {owner, mode} =
      Agent.get_and_update(target, fn state ->
        case Map.get(state.modes, kind, []) do
          [mode | rest] -> {{state.owner, mode}, put_in(state, [:modes, kind], rest)}
          [] -> {{state.owner, default}, state}
        end
      end)

    send(owner, {:entered, kind, self(), key})
    respond(mode)
  end

  defp respond(:block) do
    receive do
      {:respond, result} -> result
    end
  end

  defp respond(:raise), do: raise("synthetic adapter failure")
  defp respond(result), do: result
end
