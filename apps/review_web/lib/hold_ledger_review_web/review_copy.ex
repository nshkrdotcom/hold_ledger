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

  def check("allows_here"), do: "accepts this result"
  def check("catches"), do: "rejects this result"
  def check("doesnt_apply"), do: "does not apply"
  def check(_), do: "not checked"
end
