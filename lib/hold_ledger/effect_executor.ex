defmodule HoldLedger.EffectExecutor do
  @moduledoc """
  Monitored external work. The calling Server owns each task and its deadline.
  Adapter terms are normalized to bounded outcomes before journal admission.
  """

  def dispatch(supervisor, processor, effect, timeout) do
    {:ok,
     Task.Supervisor.async_nolink(supervisor, fn ->
       {:ok, timer} = :timer.kill_after(timeout, self())

       try do
         execute(processor, effect)
       after
         :timer.cancel(timer)
       end
     end)}
  rescue
    _ -> {:error, :task_start_failed}
  catch
    :exit, _ -> {:error, :task_start_failed}
  end

  def execute(processor, effect) do
    perform(processor, effect)
  rescue
    _ -> {:error, :adapter_exception}
  catch
    _, _ -> {:error, :adapter_exit}
  end

  defp perform({module, target}, {:authorize, key, amount}),
    do: authorization(module.authorize(target, key, amount))

  defp perform({module, target}, {:lookup, key}) do
    case module.lookup(target, key) do
      {:ok, result} when result in [:approved, :declined] -> {:ok, result}
      :not_found -> :not_found
      {:error, reason} -> {:error, reason(reason)}
      _ -> {:error, :unexpected_reply}
    end
  end

  defp perform({module, target}, {:void, key}) do
    case module.void(target, key) do
      {:ok, result} when result in [:voided, :already_voided] -> {:ok, result}
      {:ok, :not_found} -> {:error, :not_found}
      {:error, error} -> {:error, reason(error)}
      _ -> {:error, :unexpected_reply}
    end
  end

  defp authorization({:ok, result}) when result in [:approved, :declined],
    do: {:callbacks, [result]}

  defp authorization({:callbacks, outcomes}) when is_list(outcomes) do
    if outcomes != [] and length(outcomes) <= 16 and
         Enum.all?(outcomes, &(&1 in [:approved, :declined])),
       do: {:callbacks, outcomes},
       else: {:error, :unexpected_reply}
  end

  defp authorization({:delayed, milliseconds, reply})
       when is_integer(milliseconds) and milliseconds >= 0 do
    Process.sleep(milliseconds)
    authorization(reply)
  end

  defp authorization(_), do: {:error, :uncertain}

  defp reason(reason) when reason in [:unavailable, :not_found, :timeout, :declined], do: reason
  defp reason(_), do: :adapter_error
end
