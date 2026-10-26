defmodule HoldLedger.Exposure do
  @moduledoc """
  Pure coupled execution model for truthful processor deliveries.

  Local operations can issue intents, while remote deliveries are separate steps.
  Approvals/declines come from the environment, and confirmation follows a terminal
  remote void. This model has no clocks, I/O, authentication or fairness promise.
  """
  alias HoldLedger.{Composite, Environment, Outbox}

  def init(amount, count), do: {Composite.init(amount, count), Environment.init()}

  def step({composite, remote} = state, {:local, event}) do
    if local?(event) do
      {next, _, effects} = Composite.step(composite, event)
      {next, issue_all(remote, effects)}
    else
      state
    end
  end

  def step({composite, remote} = state, {:authorize, key, decision})
      when is_integer(key) and decision in [:approved, :declined] do
    case Environment.deliver(remote, {:authorize, key, decision}) do
      {next_remote, outcome} when outcome in [:approved, :declined] -> {composite, next_remote}
      _ -> state
    end
  end

  def step({composite, {_, records} = remote} = state, {:observe, key}) when is_integer(key) do
    case Environment.lookup(records, key) do
      {^key, _, outcome} when outcome in [:approved, :declined] ->
        {next, _, _} = Composite.step(composite, {:processor_result, key, outcome})
        {next, remote}

      _ ->
        state
    end
  end

  def step({{_, obligations} = composite, remote} = state, {:void, key}) when is_integer(key) do
    case Outbox.fetch(obligations, key) do
      :not_found ->
        state

      {^key, _, _} ->
        {next_remote, :void_confirmed} = Environment.deliver(remote, {:void, key})
        {composite, next_remote}
    end
  end

  def step({composite, {_, records} = remote} = state, {:confirm, key}) when is_integer(key) do
    case Environment.lookup(records, key) do
      {^key, _, :voided} ->
        {next, _, _} = Composite.step(composite, {:void_confirmed, key})
        {next, remote}

      _ ->
        state
    end
  end

  def step(state, _), do: state
  def run(state, []), do: state
  def run(state, [event | tail]), do: run(step(state, event), tail)

  defp local?(:restart), do: true
  defp local?({:request, _, _}), do: true
  defp local?({tag, _}) when tag in [:dispatch, :timeout, :retry, :void], do: true
  defp local?(_), do: false
  defp issue_all(remote, []), do: remote
  defp issue_all(remote, [effect | rest]), do: issue_all(Environment.issue(remote, effect), rest)
end
