defmodule HoldLedgerReview.Part3ProofInspector do
  @moduledoc """
  On-demand source and artifact index, including partial and failed intake.
  Revalidates every artifact. Acceptance is always the current original gate
  result, never a saved success flag or a producer's assertion.
  """
  alias HoldLedgerReview.{Anchor, Part3Snapshots, Part3Verification}

  @max_items 100
  @max_excerpt 4000

  def inspect(package) do
    sid = package["proposal"]["snapshot_id"]

    with {:ok, snapshot} <- Part3Snapshots.load(sid),
         {:ok, raw} <- Anchor.read_under(Part3Snapshots.root(sid), "verification/laws.json"),
         {:ok, %{"laws" => catalog}} <- Jason.decode(raw),
         true <- is_list(catalog) and length(catalog) <= @max_items do
      {report, status} = latest_report(package, sid)
      artifacts = available_artifacts(package, sid)
      rows = Enum.map(catalog, &law_row(&1, snapshot, report, artifacts))

      {:ok,
       %{
         "catalog_count" => length(rows),
         "sources" => rows,
         "artifacts" => artifacts,
         "report_status" =>
           if(report, do: "report_present:" <> status, else: "not_run_or_missing"),
         "formal_acceptance" => status
       }}
    else
      _ -> {:error, :proof_catalog_or_source_missing}
    end
  end

  defp law_row(law, snapshot, report, artifacts) do
    path = law["file"]

    source =
      case Anchor.read_under(Part3Snapshots.root(snapshot["snapshot_id"]), path) do
        {:ok, bytes} ->
          %{
            "path" => path,
            "sha256" => snapshot["manifest"][path],
            "excerpt" => String.slice(bytes, 0, @max_excerpt)
          }

        _ ->
          %{"path" => path, "status" => "unavailable"}
      end

    record = if report, do: get_in(report, ["laws", law["slug"]]), else: nil
    linked = Enum.filter(artifacts, &(&1["slug"] in [law["slug"], "*"]))

    %{
      "slug" => law["slug"],
      "obligation_id" => law["id"],
      "purpose" => law["purpose"],
      "source" => source,
      "artifacts" => linked,
      "translated_statement" => field(record, "translated_statement"),
      "proof_dependencies" => field(record, "axioms"),
      "exports" => field(record, "exports"),
      "checker_result" =>
        if(is_map(record), do: Map.take(record, ~w(passed native_passed checkers)), else: nil),
      "artifact_scope" =>
        if(is_map(record) or linked != [],
          do: "available_artifacts_not_acceptance",
          else: "not_run_or_missing"
        )
    }
  end

  defp field(map, key) when is_map(map), do: Map.get(map, key)
  defp field(_, _), do: nil

  defp latest_report(package, sid) do
    package["verification_attempts"]
    |> Enum.reverse()
    |> Enum.find_value({nil, "not_run"}, fn a ->
      # Intake's report is distinct from its supplementary source artifacts.
      report = get_in(a, ["result", "report"])

      candidates =
        if is_map(report),
          do: [report],
          else: Enum.filter(a["artifacts"], &String.ends_with?(&1["path"], "/checked.json"))

      Enum.find_value(candidates, &checked_report(&1, sid))
    end)
  end

  defp checked_report(item, sid) do
    with {:ok, bytes} <- Part3Verification.read_artifact(sid, item["path"]),
         true <- Anchor.sha(bytes) == item["sha256"] and byte_size(bytes) == item["bytes"],
         {:ok, rows} <- Part3Verification.inspect_report(sid, item["path"]),
         {:ok, decoded} <- Jason.decode(bytes) do
      {decoded, hd(rows)["acceptance_status"]}
    else
      _ -> nil
    end
  end

  defp available_artifacts(package, sid) do
    package["verification_attempts"]
    |> Enum.flat_map(fn attempt -> get_in(attempt, ["result", "artifacts"]) || [] end)
    |> Enum.uniq_by(&{&1["path"], &1["sha256"]})
    |> Enum.map(&inspect_artifact(&1, sid))
  end

  defp inspect_artifact(item, sid) do
    case Part3Verification.read_artifact(sid, item["path"]) do
      {:ok, bytes} ->
        if Anchor.sha(bytes) == item["sha256"] and byte_size(bytes) == item["bytes"],
          do:
            Map.merge(item, %{
              "status" => "present",
              "excerpt" => String.slice(bytes, 0, @max_excerpt)
            }),
          else: Map.put(item, "status", "stale")

      _ ->
        Map.put(item, "status", "missing")
    end
  end
end
