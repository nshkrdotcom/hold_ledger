defmodule HoldLedgerReview.Session do
  @moduledoc "Pure session actions; LiveViews hold isolated instances."
  alias HoldLedgerReview.{Packet, Facts}
  @decisions ~w(accept_scope reject_scope needs_policy insufficient_evidence)
  def decisions, do: @decisions

  def new(packet),
    do: %{
      packet: packet,
      session_id: Base.url_encode64(:crypto.strong_rand_bytes(18), padding: false),
      prediction: nil,
      note: "",
      candidate: "correct",
      selected: packet.case.claims,
      examined: [],
      follow: nil,
      source: nil,
      explanation: nil,
      feedback: [],
      stale?: false,
      receipt_id: nil
    }

  def act(s, "predict", %{"choice" => choice} = params)
      when choice in ~w(retain release uncertain admit reject) do
    choices =
      if s.packet.case.id == "exact_fit",
        do: ~w(admit reject uncertain),
        else: ~w(retain release uncertain)

    if choice not in choices do
      {:error, :invalid_prediction}
    else
      if is_nil(s.prediction),
        do: {:ok, %{s | prediction: choice, note: text(params["note"], 500)}},
        else: {:ok, s}
    end
  end

  def act(%{prediction: prediction} = s, "select_candidate", %{"id" => id})
      when not is_nil(prediction) do
    if Map.has_key?(s.packet.facts.candidates, id),
      do:
        {:ok,
         %{
           s
           | candidate: id,
             follow: nil,
             examined: Enum.uniq([id | s.examined]),
             explanation: nil
         }},
      else: {:error, :unknown_candidate}
  end

  def act(%{prediction: prediction} = s, "toggle_claim", %{"id" => id})
      when not is_nil(prediction) do
    if id in s.packet.case.claims do
      {:ok,
       %{
         s
         | selected:
             if(id in s.selected, do: List.delete(s.selected, id), else: s.selected ++ [id])
       }}
    else
      {:error, :unknown_claim}
    end
  end

  def act(%{prediction: prediction} = s, "follow_event", %{"id" => "next"})
      when not is_nil(prediction) do
    with {:ok, result} <-
           Facts.follow(s.packet.facts.candidates[s.candidate], s.packet.case.follow),
         do: {:ok, %{s | follow: result}}
  end

  def act(s, "open_anchor", %{"id" => id}) do
    if Map.has_key?(s.packet.anchors, id),
      do: {:ok, %{s | source: id}},
      else: {:error, :unknown_anchor}
  end

  def act(s, "flag_explanation", _) do
    if s.explanation,
      do:
        {:ok,
         %{
           s
           | feedback:
               Enum.take(
                 [
                   %{
                     candidate: s.candidate,
                     packet: s.packet.packet_sha256,
                     kind: "misleading_or_unsupported"
                   }
                   | s.feedback
                 ],
                 20
               )
         }},
      else: {:error, :no_explanation}
  end

  def act(_, _, _), do: {:error, :invalid_action}
  def passing?(s, id), do: Enum.all?(s.selected, &s.packet.facts.matrix[id][&1])

  def validate_decision(s, params) do
    decision = params["decision"]
    rationale = params["rationale"] || ""
    ids = params["evidence"] || []
    mode = Application.get_env(:hold_ledger_review_web, :review_mode, :practice)
    current = Packet.current?(s.packet)

    cond do
      s.receipt_id != nil ->
        {:error, :already_recorded}

      s.prediction == nil ->
        {:error, :prediction_required}

      decision not in @decisions ->
        {:error, :unknown_decision}

      not is_binary(rationale) or not String.valid?(rationale) or byte_size(rationale) > 2000 ->
        {:error, :rationale_too_long}

      not is_list(ids) or length(ids) > 30 or
          Enum.any?(ids, &(&1 not in Packet.evidence_ids(s.packet))) ->
        {:error, :invalid_evidence}

      decision in ~w(accept_scope reject_scope) and (String.trim(rationale) == "" or ids == []) ->
        {:error, :rationale_and_evidence_required}

      decision == "accept_scope" and (not current or s.packet.facts.disputed?) ->
        {:error, :stale_or_disputed_source}

      decision == "accept_scope" and params["formally_checked"] == "true" and
          s.packet.proof.status not in [:selected_checked, :full_catalog_checked] ->
        {:error, :checked_evidence_required}

      mode == :source_review and
          (params["revision"] != s.packet.git_head or text(params["scope"], 500) == "") ->
        {:error, :revision_and_scope_required}

      true ->
        {:ok,
         %{
           decision: decision,
           rationale: rationale,
           selected_evidence_ids: ids,
           review_mode: mode,
           reviewed_scope: text(params["scope"], 500),
           reviewed_revision: params["revision"],
           formally_checked: params["formally_checked"] == "true",
           stale_at_recording: not current
         }}
    end
  end

  def text(v, max) when is_binary(v) do
    if String.valid?(v) and byte_size(v) <= max, do: String.trim(v), else: ""
  end

  def text(_, _), do: ""
end
