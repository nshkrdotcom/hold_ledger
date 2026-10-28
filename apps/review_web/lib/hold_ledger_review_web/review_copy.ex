defmodule HoldLedgerReviewWeb.ReviewCopy do
  @moduledoc false
  @titles %{
    "po_a2" => "Accept requests that fit available capacity",
    "po_a4_duplicate" => "Recognize a repeated request",
    "po_a4_conflict" => "Reject a reused identity with a different amount",
    "po_b1_void" => "Keep the account consistent during cancellation",
    "po_b1_timeout" => "Keep the account consistent after a timeout",
    "po_exposure_retain" => "Keep money reserved until cancellation is confirmed",
    "po_exposure_model" => "Follow the ledger and the payment processor",
    "po_s" => "Keep the ledger consistent"
  }
  def title(law) do
    @titles[law["slug"]] ||
      (law["title"] || law["slug"] || "Ledger rule")
      |> String.split(" · ")
      |> List.last()
      |> String.capitalize()
  end

  def policy(%{"slug" => "po_a2"}),
    do:
      "A request can use all remaining capacity. It must also fit a free hold slot and use a new request ID."

  def policy(%{"slug" => "po_exposure_retain"}),
    do:
      "Requesting cancellation does not release the money. Keep it reserved until trusted confirmation arrives."

  def policy(reading), do: reading["policy"]["quote"] || "Read the rule and try a concrete case."

  def result(value),
    do:
      Map.get(
        %{
          "admitted" => "Accepted",
          "insufficient_amount" => "Not enough available money",
          "insufficient_holds" => "No free hold slot",
          "voiding" => "Cancellation requested",
          "voided" => "Cancellation confirmed",
          "dispatched" => "Authorization sent",
          "marked_unknown" => "Outcome unknown"
        },
        value,
        String.replace(value, "_", " ")
      )

  def state(value),
    do:
      Map.get(
        %{
          "reserved" => "Reserved",
          "sent" => "Authorization pending",
          "unknown" => "Awaiting confirmation",
          "authorized" => "Authorized",
          "voiding" => "Waiting for cancellation",
          "voided" => "Cancelled",
          "declined" => "Declined"
        },
        value,
        value
      )

  def action(%{"type" => "void", "key" => key}), do: "Cancel hold #{key}"

  def action(%{"type" => "authorize", "key" => key, "amount" => amount}),
    do: "Authorize #{amount}¢ for request #{key}"

  def check("allows_here"), do: "Rule accepts this alternative"
  def check("catches"), do: "Rule rejects this alternative"
  def check("doesnt_apply"), do: "Rule does not apply"
  def check("not_probed"), do: "Not checked for this event"
  def check(_), do: "Could not evaluate"

  def applicability(%{"explanation" => %{"bindings" => bindings, "complete" => complete}})
      when is_list(bindings) do
    values = Enum.map(bindings, &get_in(&1, ["requires", "value"]))
    count = Enum.count(values, &(&1 == true))

    cond do
      not complete or Enum.any?(bindings, &Map.has_key?(&1, "error")) -> "Could not evaluate all bindings"
      values == [] -> "Not checked"
      Enum.any?(values, &(not is_boolean(&1))) -> "Could not evaluate"
      count > 0 -> "Applies (#{count} of #{length(values)} bindings)"
      Enum.all?(values, &(&1 == false)) -> "Does not apply"
      true -> "Could not evaluate"
    end
  end

  def applicability(_), do: "Not checked"

  def code_acceptance(%{"explanation" => %{"bindings" => bindings, "complete" => true}})
      when is_list(bindings) do
    covered = Enum.filter(bindings, &(get_in(&1, ["requires", "value"]) == true))
    values = Enum.map(covered, &get_in(&1, ["actual", "value"]))

    cond do
      bindings == [] -> "Unavailable"
      Enum.any?(bindings, &Map.has_key?(&1, "error")) -> "Unavailable"
      Enum.any?(bindings, &(not is_boolean(get_in(&1, ["requires", "value"])))) ->
        "Unavailable"
      covered == [] and Enum.all?(bindings, &(get_in(&1, ["requires", "value"]) == false)) ->
        "Not applicable"
      values == [] -> "Unavailable"
      false in values -> "Rejects code result"
      Enum.all?(values, &(&1 == true)) -> "Accepts code result"
      true -> "Unavailable"
    end
  end

  def code_acceptance(_), do: "Unavailable"

  def candidate_acceptance(%{"law_status" => "allows_here"}), do: "Accepts alternative"
  def candidate_acceptance(%{"law_status" => "catches"}), do: "Rejects alternative"
  def candidate_acceptance(%{"law_status" => "doesnt_apply"}), do: "Not applicable"
  def candidate_acceptance(%{"law_status" => "not_probed"}), do: "Not checked"
  def candidate_acceptance(_), do: "Unavailable"

  def accounting(true), do: "Accounting balances"
  def accounting(false), do: "Accounting does not balance"
  def accounting(_), do: "Unavailable"
end
