defmodule HoldLedger.ControlledProcessor do
  @moduledoc false
  @behaviour HoldLedger.Processor

  def child_spec(opts), do: %{id: __MODULE__, start: {__MODULE__, :start_link, [opts]}}

  def start_link(opts),
    do:
      Agent.start_link(fn ->
        %{owner: Keyword.fetch!(opts, :owner), modes: Keyword.get(opts, :modes, %{})}
      end)

  @impl HoldLedger.Processor
  def capabilities(_), do: %{terminal_confirmation: true, non_resurrection: :permanent}

  @impl HoldLedger.Processor
  def authorize(target, key, _), do: perform(target, :authorize, key, {:ok, :approved})
  @impl HoldLedger.Processor
  def void(target, key), do: perform(target, :void, key, {:ok, :voided})
  @impl HoldLedger.Processor
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
