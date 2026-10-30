defmodule HoldLedgerReviewWeb.ReviewCopy do
  @moduledoc false
  @titles %{
    "po_a2" => "Accept requests that fit available capacity",
    "po_a4_duplicate" => "Recognize a repeated request",
    "po_a4_conflict" => "Reject a reused identity with a different amount",
    "po_b1_void" => "Keep the account consistent during cancellation",
    "po_b1_timeout" => "Keep the account consistent after a timeout",
    "po_exposure_retain" => "Keep issued holds reserved until a final result",
    "po_exposure_model" => "Follow the ledger and the payment processor",
    "po_s" => "Keep the ledger consistent"
  }
  def title(law) do
    @titles[law["slug"]] || HoldLedgerReviewWeb.Education.title(law["slug"]) ||
      (law["title"] || law["slug"] || "Ledger claim")
      |> String.split(" · ")
      |> List.last()
      |> String.capitalize()
  end

  def policy(%{"slug" => "po_a2"}),
    do:
      "A request can use all remaining capacity. It must also fit a free hold slot and use a new request ID."

  def policy(%{"slug" => "po_exposure_retain"}),
    do:
      "An issued hold keeps its capacity until a trusted decline or void confirmation releases it."

  def policy(reading), do: reading["policy"]["quote"] || "Read the claim and try a concrete case."

  def result(value),
    do:
      Map.get(
        %{
          "admitted" => "Accepted",
          "insufficient_amount" => "Not enough available money",
          "insufficient_holds" => "No free hold slot",
          "voiding" => "Cancellation requested",
          "voided" => "Hold cancelled",
          "dispatched" => "Authorization requested",
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
          "unknown" => "Outcome unknown",
          "authorized" => "Authorized",
          "voiding" => "Waiting for cancellation",
          "voided" => "Cancelled",
          "declined" => "Declined"
        },
        value,
        value
      )

  def state_hint(value) do
    case HoldLedgerReviewWeb.Education.term(value) do
      nil -> nil
      term -> term["short"]
    end
  end

  def action(%{"type" => "void", "key" => key}), do: "Cancel hold #{key}"

  def action(%{"type" => "authorize", "key" => key, "amount" => amount}),
    do: "Authorize #{amount}¢ for request #{key}"

  def check("allows_here"), do: "Claim would accept this output. Intended?"
  def check("catches"), do: "Claim rejects this output"
  def check("doesnt_apply"), do: "Claim says nothing about this input"
  def check("not_probed"), do: "No check wired up for this event"
  def check(_), do: "Check unavailable"

  def applicability(%{"explanation" => %{"bindings" => bindings, "complete" => complete}})
      when is_list(bindings) do
    values = Enum.map(bindings, &get_in(&1, ["requires", "value"]))
    count = Enum.count(values, &(&1 == true))

    cond do
      not complete or Enum.any?(bindings, &Map.has_key?(&1, "error")) ->
        "Could not evaluate all bindings"

      values == [] ->
        "Not checked"

      Enum.any?(values, &(not is_boolean(&1))) ->
        "Could not evaluate"

      count > 0 ->
        "Applies (#{count} of #{length(values)} bindings)"

      Enum.all?(values, &(&1 == false)) ->
        "Claim says nothing about this input"

      true ->
        "Could not evaluate"
    end
  end

  def applicability(_), do: "Not checked"

  def code_acceptance(%{"explanation" => %{"bindings" => bindings, "complete" => true}})
      when is_list(bindings) do
    covered = Enum.filter(bindings, &(get_in(&1, ["requires", "value"]) == true))
    values = Enum.map(covered, &get_in(&1, ["actual", "value"]))

    if incomplete_bindings?(bindings), do: "Unavailable", else: code_result(covered, values)
  end

  def code_acceptance(_), do: "Unavailable"

  defp incomplete_bindings?(bindings) do
    bindings == [] or
      Enum.any?(
        bindings,
        &(Map.has_key?(&1, "error") or
            not is_boolean(get_in(&1, ["requires", "value"])))
      )
  end

  defp code_result([], _), do: "Outside this claim's input"

  defp code_result(_, values) do
    cond do
      false in values -> "Rejects code result"
      Enum.all?(values, &(&1 == true)) -> "Accepts code result"
      true -> "Unavailable"
    end
  end

  def candidate_acceptance(%{"law_status" => "allows_here"}), do: "Accepts proposed output"
  def candidate_acceptance(%{"law_status" => "catches"}), do: "Rejects proposed output"
  def candidate_acceptance(%{"law_status" => "doesnt_apply"}),
    do: "Outside this claim's input"
  def candidate_acceptance(%{"law_status" => "not_probed"}), do: "Not checked"
  def candidate_acceptance(_), do: "Unavailable"

  def output_check_unavailable?(case_data) do
    code_acceptance(case_data) == "Unavailable" and
      candidate_acceptance(case_data) in ["Unavailable", "Not checked"]
  end

  def probe_reason(":outside_initial_probe_scope", "l2_identity"),
    do:
      "This claim checks whether set_status/3 keeps existing request IDs and amounts. " <>
        "Read the helper's source; this event check calls Ledger.step/2."

  def probe_reason(":outside_initial_probe_scope", _),
    do: "No event check is available for this claim. Read its source below."

  def probe_reason(reason, _), do: reason

  def accounting(true), do: "Accounting balances"
  def accounting(false), do: "Accounting does not balance"
  def accounting(_), do: "Unavailable"

  def evidence_status("source_declaration_not_elaborated_evidence"),
    do: "Source text · not proof-check evidence"

  def evidence_status("missing_or_ambiguous_declaration"),
    do: "Declaration unavailable or ambiguous"

  def evidence_status("missing_or_stale"), do: "Missing or out of date"
  def evidence_status("not_supplied"), do: "Not supplied"
  def evidence_status("current"), do: "Matches the reviewed source"
  def evidence_status("stale"), do: "Out of date for this source"
  def evidence_status("elaborated"), do: "Focused elaboration completed · not full acceptance"
  def evidence_status("full_catalog_checked"), do: "Full required catalog checked"
  def evidence_status("selected_checked"), do: "Selected scope checked · not full catalog"
  def evidence_status("development_only"), do: "Development checks only"
  def evidence_status("failed"), do: "Verification failed"
  def evidence_status("incomplete"), do: "Verification incomplete or unavailable"
  def evidence_status(_), do: "Unavailable · inspect the verification record"

  def dollar_gloss(cents) when is_integer(cents) do
    sign = if cents < 0, do: "-", else: ""
    amount = abs(cents)
    fraction = amount |> rem(100) |> Integer.to_string() |> String.pad_leading(2, "0")
    sign <> "$" <> Integer.to_string(div(amount, 100)) <> "." <> fraction
  end

  def state_tuple(state) do
    case HoldLedgerReview.TermCodec.decode_state(state) do
      {:ok, tuple} -> inspect(tuple, pretty: true, limit: :infinity)
      {:error, _} -> "The state cannot be displayed as a ledger tuple."
    end
  end
end
