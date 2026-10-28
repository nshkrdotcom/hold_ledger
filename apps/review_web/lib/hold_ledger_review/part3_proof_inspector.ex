defmodule HoldLedgerReview.Part3ProofInspector do
  @moduledoc """
  Read-only, on-demand source and producer-artifact projection. Each version is
  independent; source identity and the *original* ProofEvidence acceptance
  status are retained. A report's checker assertions are not a new UI gate.
  """
  alias HoldLedgerReview.{Anchor, Part3Snapshots, Part3Verification}

  @max_items 100
  @max_excerpt 4000
  @checkers ["Lean default", "Lean paranoid", "lean4lean", "nanoda", "con-leche", "con-ron"]

  def inspect(package) do
    with {:ok, baseline} <- inspect_side(package, "baseline"),
         {:ok, proposal} <- inspect_side(package, "proposal") do
      {:ok,
       %{
         "versions" => [baseline, proposal],
         # Retained keys allow old clients to continue displaying proposal scope.
         "catalog_count" => proposal["catalog_count"],
         "sources" => proposal["sources"],
         "artifacts" => proposal["artifacts"],
         "report_status" => proposal["report_status"],
         "formal_acceptance" => proposal["formal_acceptance"]
       }}
    else
      _ -> {:error, :proof_catalog_or_source_missing}
    end
  end

  defp inspect_side(package, side) do
    sid = package[side]["snapshot_id"]

    with {:ok, snapshot} <- Part3Snapshots.load(sid),
         true <- snapshot == package[side],
         {:ok, raw} <- Anchor.read_under(Part3Snapshots.root(sid), "verification/laws.json"),
         {:ok, %{"laws" => catalog}} <- Jason.decode(raw),
         true <- is_list(catalog) and length(catalog) <= @max_items do
      {report, status, report_ref} = latest_report(package, sid)
      artifacts = available_artifacts(package, sid)
      rows = Enum.map(catalog, &law_row(&1, snapshot, report, artifacts, status))

      {:ok,
       %{
         "side" => side,
         "snapshot_id" => sid,
         "catalog_count" => length(rows),
         "sources" => rows,
         "artifacts" => artifacts,
         "report_reference" => report_ref,
         "report_status" => if(report, do: "report_present:" <> status, else: "not_run_or_missing"),
         "formal_acceptance" => status
       }}
    else
      _ -> {:error, :catalog_or_snapshot_unavailable}
    end
  end

  defp law_row(law, snapshot, report, artifacts, status) do
    path = law["file"]

    source =
      case Anchor.read_under(Part3Snapshots.root(snapshot["snapshot_id"]), path) do
        {:ok, bytes} ->
          %{
            "path" => path,
            "sha256" => snapshot["manifest"][path],
            "excerpt" => preview(bytes),
            "excerpt_bounded" => byte_size(bytes) > @max_excerpt,
            "status" => "source_hash_matched"
          }

        _ ->
          %{"path" => path, "status" => "unavailable"}
      end

    record = if report, do: get_in(report, ["laws", law["slug"]]), else: nil
    linked = Enum.filter(artifacts, &(&1["slug"] in [law["slug"], "*"]))
    statements = Enum.filter(linked, &(&1["kind"] in ~w(translated_statement lean_source)))
    dependencies = Enum.filter(linked, &(&1["kind"] == "proof_dependencies"))

    %{
      "slug" => law["slug"],
      "obligation_id" => law["id"],
      "purpose" => law["purpose"],
      "source" => source,
      "artifacts" => linked,
      "translated_statement" => field(record, "translated_statement"),
      "lean_declarations" => statements,
      "proof_dependencies" => field(record, "proof_dependencies"),
      "dependency_artifacts" => dependencies,
      "exports" => export_summaries(record, report, status),
      "checker_result" =>
        if(is_map(record), do: Map.take(record, ~w(passed native_passed)), else: nil),
      "artifact_scope" =>
        if(is_map(record) or linked != [],
          do: "recorded_producer_evidence_not_new_acceptance",
          else: "not_run_or_missing"
        )
    }
  end

  defp export_summaries(%{"exports" => exports}, report, acceptance)
       when is_list(exports) do
    Enum.map(exports, fn export ->
      scope = export_scope(export, report)
      checks = export["checker_acceptance"]

      %{
        "path" => export["path"],
        "sha256" => export["export_sha256"],
        "bytes" => export["export_bytes"],
        "scope" => scope,
        "axiom_scope" => scope,
        "recorded_axioms" => export["axiom_list"],
        "allowed_axioms_reported" => export["allowed_axioms"],
        "producer_passed" => export["passed"],
        "checkers" =>
          Enum.map(@checkers, fn name ->
            %{
              "name" => name,
              "recorded_status" =>
                cond do
                  not is_map(checks) or not Map.has_key?(checks, name) -> "not_supplied"
                  checks[name] == true -> "producer_reported_pass"
                  checks[name] == false -> "producer_reported_fail"
                  true -> "unsupported_record"
                end
            }
          end),
        "original_gate_status" => acceptance
      }
    end)
  end

  defp export_summaries(_, _, _), do: []

  # The pinned full-suite producer can reuse the same 158 MB export record
  # in every law row. That is a *suite* axiom list, not theorem-specific data.
  defp export_scope(export, report) do
    count =
      if is_map(report) and is_map(report["laws"]) do
        Enum.count(report["laws"], fn {_, law} ->
          Enum.any?(law["exports"] || [], fn other ->
            is_map(other) and other["path"] == export["path"] and
              other["export_sha256"] == export["export_sha256"]
          end)
        end)
      else
        0
      end

    if count > 1, do: "shared_suite_export", else: "export_scoped_not_theorem_scoped"
  end

  defp field(record, key) when is_map(record), do: Map.get(record, key)
  defp field(_, _), do: nil

  defp latest_report(package, sid) do
    package["verification_attempts"]
    |> Enum.filter(&(&1["snapshot_id"] == sid))
    |> Enum.reverse()
    |> Enum.find_value({nil, "not_run", nil}, fn a ->
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
      {decoded, hd(rows)["acceptance_status"], Map.take(item, ~w(path sha256 bytes))}
    else
      _ -> nil
    end
  end

  defp available_artifacts(package, sid) do
    package["verification_attempts"]
    |> Enum.filter(&(&1["snapshot_id"] == sid))
    |> Enum.flat_map(fn attempt ->
      (attempt["artifacts"] || []) ++ (get_in(attempt, ["result", "artifacts"]) || [])
    end)
    |> Enum.uniq_by(&{&1["path"], &1["sha256"]})
    |> Enum.map(&inspect_artifact(&1, sid))
  end

  defp preview(bytes) do
    if String.valid?(bytes),
      do: String.slice(bytes, 0, @max_excerpt),
      else: "[binary artifact: exact digest and byte size shown; not rendered as text]"
  end

  defp inspect_artifact(item, sid) do
    case Part3Verification.read_artifact(sid, item["path"]) do
      {:ok, bytes} ->
        if Anchor.sha(bytes) == item["sha256"] and byte_size(bytes) == item["bytes"],
          do:
            Map.merge(item, %{
              "status" => "present",
              "excerpt" => preview(bytes),
              "excerpt_bounded" => byte_size(bytes) > @max_excerpt
            }),
          else: Map.put(item, "status", "stale")

      _ ->
        Map.put(item, "status", "missing")
    end
  end
end
