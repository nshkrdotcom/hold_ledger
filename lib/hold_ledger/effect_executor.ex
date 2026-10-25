defmodule HoldLedger.EffectExecutor do
  @moduledoc """
  Launch only *new live* ledger intents under a Task.Supervisor. Each observed
  processor outcome is delivered to the authoritative server as a new event;
  the executor never changes ledger state or writes a journal itself.
  """

  def dispatch(supervisor, server, processor, effect) do
    ref = make_ref()

    case Task.Supervisor.start_child(supervisor, fn ->
           events =
             try do
               execute(processor, effect)
             rescue
               _error -> uncertain_event(effect)
             catch
               _, _ -> uncertain_event(effect)
             end

           send(server, {:hold_ledger_effects, ref, events})
         end) do
      {:ok, _pid} -> {:ok, ref}
      {:error, reason} -> {:error, reason}
    end
  end

  defp execute({module, target}, {:authorize, key, amount}) do
    module.authorize(target, key, amount) |> authorization_events(key)
  end

  defp execute({module, target}, {:void, key}) do
    [{:processor_void_result, key, module.void(target, key)}]
  end

  defp authorization_events({:ok, outcome}, key) when outcome in [:approved, :declined],
    do: [{:processor_result, key, outcome}]

  defp authorization_events({:lost, _}, key), do: [{:timeout, key}]

  defp authorization_events({:delayed, milliseconds, response}, key)
       when is_integer(milliseconds) and milliseconds >= 0 do
    Process.sleep(milliseconds)
    authorization_events(response, key)
  end

  defp authorization_events({:callbacks, outcomes}, key) when is_list(outcomes) do
    Enum.map(outcomes, fn outcome -> {:processor_result, key, outcome} end)
  end

  defp authorization_events(_unexpected, key), do: [{:timeout, key}]

  defp uncertain_event({:authorize, key, _}), do: [{:timeout, key}]

  defp uncertain_event({:void, key}),
    do: [{:processor_void_result, key, {:error, :executor_failed}}]
end
