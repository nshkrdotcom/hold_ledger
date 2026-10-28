defmodule HoldLedgerReview.Part3ProofInspector do
  @moduledoc """
  Read-only, on-demand evidence index. Original law/Lean source and checker
  artifacts are different authorities. Missing translated or exported evidence
  remains missing; no source excerpt is presented as a checker result.
  """
  alias HoldLedgerReview.{Anchor, Part3Snapshots, Part3Verification}

  @max_items 100
  @max_excerpt 950

  def inspect(package) do
    sid = package["proposal"]["snapshot_id"]
    with {:ok, snapshot} <- Part3Snapshots.load(sid),
         root = Part3Snapshots.root(sid),
         {:ok, raw} <- Anchor.read_under(root, "verification/laws.json"),
         true <- Anchor.sha(raw) == snapshot["manifest"]["verification/laws.json"],
         {:ok, %{"laws" => catalog}} <- Jason.decode(raw),
         true <- is_list(catalog) and length(catalog) <= @max_items do
      report = latest_checked_report(package, root, sid)
      rows = Enum.map(catalog, fn law -> law_row(law, root, snapshot, report) end)
      {:ok, %{"catalog_count" => length(rows), "sources" => rows,
        "report_status" => if(report, do: "source_matching_artifact_present", else: "not_run_or_missing"),
        "formal_acceptance" => if(report, do: report["status"], else: "not_run")}}
    else
      _ -> {:error, :proof_catalog_or_source_missing}
    end
  end

  defp law_row(law, root, snapshot, report) do
    path = law["file"]
    source = case is_binary(path) and Map.get(snapshot["manifest"], path) do
      digest when is_binary(digest) ->
        case Anchor.read_under(root, path) do
          {:ok, bytes} ->
            if Anchor.sha(bytes) == digest,
              do: %{"path" => path, "sha256" => digest, "excerpt" => String.slice(bytes, 0, @max_excerpt)},
              else: %{"path" => path, "status" => "source_drift"}
          _ -> %{"path" => path, "status" => "unavailable"}
        end
      _ -> %{"status" => "not_registered_in_snapshot"}
    end
    slug = law["slug"]
    artifact = if report, do: get_in(report, ["laws", slug]), else: nil
    %{
      "slug" => slug, "obligation_id" => law["id"],
      "source" => source, "purpose" => law["purpose"],
      "translated_statement" => field(artifact, "translated_statement"),
      "proof_dependencies" => field(artifact, "axioms"),
      "exports" => field(artifact, "exports"),
      "checker_result" => if(is_map(artifact), do: Map.take(artifact, ~w(passed native_passed checkers)), else: nil),
      "artifact_scope" => if(is_map(artifact), do: "existing_source_matching_report", else: "not_run_or_missing")
    }
  end

  defp field(map, key) when is_map(map), do: Map.get(map, key)
  defp field(_, _), do: nil

  defp latest_checked_report(package, root, sid) do
    package["verification_attempts"]
    |> Enum.reverse()
    |> Enum.find_value(fn a ->
      case a do
        %{"kind" => "acceptance", "status" => "succeeded", "snapshot_id" => ^sid,
          "artifacts" => [%{"path" => path, "sha256" => digest}]} ->
          with {:ok, _} <- Part3Verification.inspect_report(sid, path),
               {:ok, bytes} <- Anchor.read_under(root, path),
               true <- Anchor.sha(bytes) == digest,
               {:ok, %{"laws" => laws} = r} <- Jason.decode(bytes),
               true <- is_map(laws) do
            Map.put(r, "status", "full_catalog_checked")
          else
            _ -> nil
          end
        _ -> nil
      end
    end)
  end
end
