defmodule HoldLedgerReview.Part3Verification do
  @moduledoc """
  Source-bound report and incremental offline artifact intake. Artifact presence
  and producer activity are diagnostic evidence, never checker acceptance.
  Only the original ProofEvidence validator derives formal acceptance.
  """
  alias HoldLedgerReview.{Anchor, Canonical, Part3Snapshots, ProofEvidence}
  alias HoldLedgerReview.Claims.Source

  @activities ~w(source_extraction pointwise_execution elaboration export checker acceptance)
  @artifact_kinds ~w(core_erlang translated_statement lean_source proof_dependencies export checker log)
  def activities, do: @activities

  def inspect_report(snapshot_id, relative) when is_binary(relative) do
    with {:ok, snapshot} <- Part3Snapshots.load(snapshot_id),
         {:ok, bytes} <- read_artifact(snapshot_id, relative),
         {:ok, report} when is_map(report) <- Jason.decode(bytes),
         {:ok, sources} <- Source.snapshot(Part3Snapshots.root(snapshot_id)) do
      slugs = Enum.map(sources.catalog, & &1["slug"])
      acceptance = ProofEvidence.status(Part3Snapshots.root(snapshot_id), report, slugs)
      provenance = artifact(relative, bytes)

      rows =
        Enum.map(@activities, fn kind ->
          %{
            "kind" => kind,
            "status" => activity_status(kind, report, acceptance),
            "acceptance_status" => Atom.to_string(acceptance),
            "report" => provenance,
            "snapshot_id" => snapshot["snapshot_id"],
            "requested_scope" => "full_required_catalog"
          }
        end)

      {:ok, rows}
    else
      _ -> {:error, :missing_stale_or_invalid_verification_report}
    end
  end

  def inspect_report(_, _), do: {:error, :invalid_report_path}

  @doc """
  Read an operator-staged index under tmp/verification/part3-*/. Every update
  is a new, hashed intake attempt. CI must copy exact artifacts locally first.
  The index binds snapshot, scope, report hash, artifact bytes and source digest;
  it cannot assert acceptance. Missing report/artifact values remain missing.
  """
  def inspect_index(snapshot_id, relative) do
    with {:ok, snapshot} <- Part3Snapshots.load(snapshot_id),
         {:ok, bytes} <- read_artifact(snapshot_id, relative),
         {:ok, index} <- Jason.decode(bytes),
         true <-
           keys?(
             index,
             ~w(schema_version snapshot_id source_manifest_digest requested_scope producer report artifacts)
           ),
         true <- index["schema_version"] == 1 and index["snapshot_id"] == snapshot_id,
         true <- index["source_manifest_digest"] == Canonical.digest(snapshot["manifest"]),
         true <- index["requested_scope"] == "full_required_catalog",
         true <- is_binary(index["producer"]) and byte_size(index["producer"]) in 1..200,
         true <- is_list(index["artifacts"]) and length(index["artifacts"]) <= 38,
         true <- Enum.all?(index["artifacts"], &valid_index_artifact?(snapshot_id, &1)),
         {:ok, report, rows} <- indexed_report(snapshot_id, index["report"]) do
      {:ok,
       %{
         "index" => artifact(relative, bytes),
         "producer" => index["producer"],
         "artifacts" => index["artifacts"],
         "report" => report,
         "activities" => rows,
         "acceptance_status" =>
           if(rows == [], do: "not_supplied", else: hd(rows)["acceptance_status"])
       }}
    else
      _ -> {:error, :invalid_stale_or_missing_artifact_index}
    end
  end

  defp indexed_report(_sid, nil), do: {:ok, nil, []}

  defp indexed_report(sid, item) do
    with true <- keys?(item, ~w(path sha256 bytes)),
         {:ok, bytes} <- read_artifact(sid, item["path"]),
         true <- artifact(item["path"], bytes) == item,
         {:ok, rows} <- inspect_report(sid, item["path"]) do
      {:ok, item, rows}
    else
      _ -> {:error, :invalid_report}
    end
  end

  defp valid_index_artifact?(sid, item) do
    with true <- keys?(item, ~w(path sha256 bytes kind slug)),
         true <- item["kind"] in @artifact_kinds and is_binary(item["slug"]),
         {:ok, bytes} <- read_artifact(sid, item["path"]) do
      artifact(item["path"], bytes) == Map.take(item, ~w(path sha256 bytes))
    else
      _ -> false
    end
  end

  def read_artifact(sid, relative) when is_binary(relative) do
    with true <- String.starts_with?(relative, "tmp/verification/part3-"),
         {:ok, bytes} <- Anchor.read_under(Part3Snapshots.root(sid), relative),
         true <- byte_size(bytes) <= 10_000_000 do
      {:ok, bytes}
    else
      _ -> {:error, :artifact_unavailable}
    end
  end

  def read_artifact(_, _), do: {:error, :artifact_unavailable}

  defp artifact(path, bytes),
    do: %{"path" => path, "sha256" => Anchor.sha(bytes), "bytes" => byte_size(bytes)}

  defp keys?(map, keys), do: is_map(map) and Enum.sort(Map.keys(map)) == Enum.sort(keys)

  defp activity_status("pointwise_execution", _report, _), do: "not_run"

  defp activity_status("source_extraction", _report, status),
    do: if(status == :stale, do: "failed", else: "succeeded")

  defp activity_status("acceptance", _report, :full_catalog_checked), do: "succeeded"
  defp activity_status("acceptance", _report, _), do: "failed"

  defp activity_status("checker", _report, status)
       when status in [:full_catalog_checked, :selected_checked], do: "succeeded"

  defp activity_status("checker", _report, :development_only), do: "not_run"
  defp activity_status("checker", _report, _), do: "failed"

  defp activity_status(kind, report, status) do
    laws = report["laws"]

    cond do
      status == :stale ->
        "failed"

      report["mode"] != "EXECUTED" or not is_map(laws) or map_size(laws) == 0 ->
        "not_run"

      true ->
        status_of_laws(kind, laws)
    end
  end

  defp status_of_laws("elaboration", laws),
    do: result_status(Enum.all?(laws, fn {_, law} -> law["native_passed"] == true end))

  defp status_of_laws("export", laws),
    do: result_status(Enum.all?(laws, fn {_, law} -> exports_present?(law["exports"]) end))

  defp exports_present?(exports),
    do: is_list(exports) and exports != [] and Enum.all?(exports, &(&1["passed"] == true))

  defp result_status(true), do: "succeeded"
  defp result_status(false), do: "failed"
end
