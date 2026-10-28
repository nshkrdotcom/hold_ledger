defmodule HoldLedgerReviewWeb.Explain do
  @moduledoc "Pure presentation of already decoded review JSON; never evaluates a rule or validates a witness."
  alias HoldLedgerReviewWeb.Glossary

  def state(%{
        "used_amount" => used,
        "amount_limit" => limit,
        "used_holds" => count,
        "hold_limit" => slots,
        "entries" => entries
      }) do
    totals =
      "The ledger has #{used}¢ of #{limit}¢ reserved, with #{count} of #{slots} hold slots in use."

    totals <> " " <> entries(entries)
  end

  def state(_), do: "State unavailable. Inspect the raw JSON."

  def event(%{"type" => "request", "key" => key, "amount" => amount}),
    do: "Request a #{amount}¢ hold with key #{key}."

  def event(%{"type" => "timeout", "key" => key}),
    do: "The authorization for hold #{key} times out."

  def event(%{"type" => "void", "key" => key}), do: "Request cancellation of hold #{key}."
  def event(%{"type" => "dispatch", "key" => key}), do: "Dispatch authorization for hold #{key}."
  def event(nil), do: "No next event selected."
  def event(_), do: "Event not described here. Inspect the raw JSON."

  def output(%{"after" => after_state, "result" => result, "effects" => effects}) do
    "#{result(result)} #{state(after_state)} #{effects(effects)}"
  end

  def output(_), do: "Outcome unavailable. Inspect the raw JSON."

  def value("after", value), do: state(value)
  def value("result", value), do: result(value)
  def value("effects", value), do: effects(value)
  def value(_, _), do: "See raw values."

  defp entries([]), do: "No recorded holds."
  defp entries(entries) when is_list(entries), do: Enum.map_join(entries, "; ", &entry/1) <> "."
  defp entries(_), do: "Entries unavailable."

  defp entry(%{"key" => key, "amount" => amount, "status" => status}) do
    label =
      if Glossary.entry(status),
        do: Glossary.label(status),
        else: "Unrecognized status (see raw JSON)"

    "Hold #{key} (#{amount}¢): #{String.downcase(label)}"
  end

  defp entry(_), do: "Unrecognized entry (see raw JSON)"

  defp result("admitted"), do: "New hold admitted."
  defp result("marked_unknown"), do: "The authorization outcome is still unknown."
  defp result("voiding"), do: "Cancellation is pending."
  defp result("voided"), do: "Hold cancelled."
  defp result("dispatched"), do: "The authorization is marked as dispatched."

  defp result("insufficient_amount"),
    do: "Request refused: not enough room under the amount limit."

  defp result("insufficient_holds"), do: "Request refused: no hold slot is available."
  defp result("duplicate"), do: "The ledger already remembers this key and amount."
  defp result("conflict"), do: "The ledger remembers this key with a different amount."
  defp result("declined"), do: "Hold declined."
  defp result("authorized"), do: "Hold authorized."
  defp result("not_found"), do: "No matching hold found."
  defp result("stale"), do: "Event does not apply to this hold."
  defp result("malformed"), do: "Event is malformed."
  defp result("restarted"), do: "Restart recorded."
  defp result("retried"), do: "Retry recorded."
  defp result(_), do: "Result not described here; inspect raw JSON."

  defp effects([]), do: "No outside work requested."
  defp effects(effects) when is_list(effects), do: Enum.map_join(effects, " ", &effect/1)
  defp effects(_), do: "Outside work unavailable; inspect raw JSON."

  defp effect(%{"type" => "void", "key" => key}),
    do: "Requests remote cancellation of hold #{key}. Cancellation still needs confirmation."

  defp effect(%{"type" => "authorize", "key" => key, "amount" => amount}),
    do:
      "Requests authorization of hold #{key} for #{amount}¢. Approval still needs a processor report."

  defp effect(_), do: "Unrecognized outside-work request; inspect raw JSON."
end
