defmodule HoldLedgerReview.Part3Docket do
  @moduledoc """
  Read-only projection of admitted pointwise evidence and immutable human history.
  Human actions are *commands* for Part3Store's existing CAS boundary. Neither
  a source edit nor a docket action authorizes a payment-policy change.
  """
  alias HoldLedgerReview.{Canonical, Part3Snapshots}

  @actions ~w(design policy considered)

  def cards(package) do
    laws = law_paths(package)

    Enum.map(package["evidence"], fn evidence ->
      changes =
        evidence["source_ids"]
        |> Enum.flat_map(&matched_changes(&1, laws, package["source_changes"]))
        |> Enum.uniq_by(& &1["id"])

      receipts = %{
        "baseline" => receipt(package, evidence, "baseline"),
        "proposal" => receipt(package, evidence, "proposal")
      }

      history =
        Enum.filter(package["human_findings"], fn finding ->
          evidence["id"] in finding["evidence_ids"]
        end)

      %{
        "id" => evidence["id"],
        "kind" => evidence["kind"],
        "evidence" => evidence,
        "changes" => changes,
        "receipts" => receipts,
        "history" => history,
        "latest" => List.last(history),
        "correspondence" =>
          if(changes == [],
            do: "no_directly_matched_changed_declaration",
            else: "matched_registered_declaration_not_causation"
          )
      }
    end)
  end

  defp matched_changes("law." <> slug, laws, changes) do
    case Map.get(laws, slug) do
      nil -> []
      path -> Enum.filter(changes, &(&1["path"] == path))
    end
  end

  defp matched_changes(_, _, _), do: []

  @doc "Build an explicit human-command candidate from stored evidence, never client prose."
  def decision(package, evidence_id, action, request_id, revision, presentation, revealed)
      when action in @actions do
    with card when is_map(card) <- Enum.find(cards(package), &(&1["id"] == evidence_id)),
         true <- presentation in ~w(expert learning) and is_boolean(revealed) do
      evidence = card["evidence"]
      {status, reason} = action_reason(action)

      cmd = %{
        "request_id" => request_id,
        "expected_human_revision" => revision,
        "lens" => lens(evidence["kind"]),
        "status" => status,
        "scope" =>
          "Single #{evidence["kind"]} witness #{evidence_id}; no general relation asserted",
        "rationale" =>
          "#{reason} Evidence #{evidence_id}: #{evidence["kind"]}; #{evidence["note"]}",
        "evidence_ids" => [evidence_id],
        "change_ids" => Enum.map(card["changes"], & &1["id"]),
        "presentation" => presentation,
        "revealed_before_answer" => revealed
      }

      {:ok, cmd}
    else
      _ -> {:error, :unknown_or_unmatched_evidence}
    end
  end

  def decision(_, _, _, _, _, _, _), do: {:error, :unsupported_human_action}

  defp action_reason("design"),
    do: {"unresolved", "Reviewer selected needs design change; no fix has been verified."}

  defp action_reason("policy"),
    do:
      {"unresolved",
       "Reviewer selected needs policy/evidence decision; no policy change is authorized."}

  defp action_reason("considered"),
    do:
      {"addressed",
       "Reviewer marked pointwise evidence considered in this scope; not defect resolution or formal acceptance."}

  defp lens("lost_domain_input"), do: "excluded_inputs"
  defp lens(_), do: "alternative_behavior"

  defp law_paths(package) do
    case Part3Snapshots.source(package["baseline"]["snapshot_id"], "verification/laws.json") do
      {:ok, bytes} ->
        case Jason.decode(bytes) do
          {:ok, %{"laws" => laws}} when is_list(laws) ->
            Map.new(laws, &{&1["slug"], &1["file"]})

          _ ->
            %{}
        end

      _ ->
        %{}
    end
  end

  defp receipt(package, evidence, side) do
    sid = package[side]["snapshot_id"]
    input_digest = Canonical.digest(evidence["input"])

    attempt =
      package["replay_attempts"]
      |> Enum.reverse()
      |> Enum.find(fn a ->
        a["snapshot_id"] == sid and a["input_digest"] == input_digest and
          a["status"] == "succeeded" and is_map(a["result"])
      end)

    if attempt do
      result = attempt["result"]

      %{
        "attempt_id" => attempt["id"],
        "input_digest" => input_digest,
        "completion_digest" => attempt["completion_digest"],
        "result_completion_digest" => result["completion_digest"],
        "source_generation" => result["source_generation"],
        "loaded_evaluator_id" => result["loaded_evaluator_id"],
        "actual" => get_in(result, ["evaluation", "actual"]),
        "status" => "admitted_succeeded_replay"
      }
    else
      %{"status" => "no_admitted_matching_replay", "actual" => nil}
    end
  end
end
