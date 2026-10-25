defmodule HoldLedger.Event do
  @moduledoc "Bounded journal event schema and public/internal admission boundary."
  @reserved [
    :void_attempt,
    :void_outcome,
    :void_retry_enabled,
    :processor_lookup_requested,
    :processor_lookup_not_found,
    :processor_lookup_unavailable,
    :hold_ledger_caps,
    :rejected_submission,
    :malformed_submission,
    :processor_conflict
  ]
  @reasons [
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
  ]

  def public(event) do
    tag = if is_tuple(event) and tuple_size(event) > 0, do: elem(event, 0), else: event

    cond do
      tag in @reserved -> {{:rejected_submission, tag}, true}
      public?(event) -> {event, false}
      true -> {{:malformed_submission, :other}, false}
    end
  end

  def valid?({:hold_ledger_caps, amount, holds}),
    do: is_integer(amount) and amount >= 0 and is_integer(holds) and holds >= 0

  def valid?({:rejected_submission, tag}), do: tag in @reserved
  def valid?({:malformed_submission, :other}), do: true

  def valid?({tag, key})
      when tag in [
             :void_attempt,
             :void_retry_enabled,
             :processor_lookup_requested,
             :processor_lookup_not_found,
             :processor_lookup_unavailable
           ],
      do: is_integer(key)

  def valid?({:void_outcome, key, {:ok, outcome}}),
    do: is_integer(key) and outcome in [:voided, :already_voided]

  def valid?({:void_outcome, key, {:error, reason}}), do: is_integer(key) and reason in @reasons

  def valid?({:processor_conflict, key, first, later}),
    do: is_integer(key) and first in [:approved, :declined] and later in [:approved, :declined]

  def valid?(event), do: public?(event)

  def decode(payload) do
    event = :erlang.binary_to_term(payload, [:safe])
    if valid?(event), do: {:ok, event}, else: :error
  rescue
    ArgumentError -> :error
  end

  defp public?(:restart), do: true
  defp public?({:request, key, amount}), do: is_integer(key) and is_integer(amount)

  defp public?({tag, key}) when tag in [:dispatch, :retry, :timeout, :void, :transport_ack],
    do: is_integer(key)

  defp public?({:processor_result, key, result}),
    do: is_integer(key) and result in [:approved, :declined]

  defp public?(_), do: false
end
