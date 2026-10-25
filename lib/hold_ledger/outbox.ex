defmodule HoldLedger.Outbox do
  @moduledoc """
  Reconstructible remote void obligations. A local authorized void opens an
  obligation. Only a trusted journaled success closes it; errors keep it visible.
  The hold key is the remote identity, and attempt counts survive restart.
  """

  def open(outbox, key),
    do: Map.put_new(outbox, key, %{attempts: 0, status: :pending, outcome: nil})

  def apply(outbox, {:void_attempt, key}) do
    Map.update!(outbox, key, &%{&1 | attempts: &1.attempts + 1, status: :pending})
  end

  def apply(outbox, {:void_outcome, key, outcome}) do
    Map.update!(outbox, key, &%{&1 | status: status(outcome), outcome: outcome})
  end

  def apply(outbox, {:void_retry_enabled, key}) do
    Map.update!(outbox, key, &%{&1 | attempts: 0})
  end

  def apply(outbox, _), do: outbox

  def due(outbox, max_attempts) do
    for {key, %{status: :pending, attempts: n}} <- outbox, n < max_attempts, do: key
  end

  def unresolved(outbox), do: Enum.reject(outbox, fn {_, item} -> item.status == :complete end)

  defp status({:ok, outcome}) when outcome in [:voided, :already_voided], do: :complete
  defp status(_), do: :pending
end
