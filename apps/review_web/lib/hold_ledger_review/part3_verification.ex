defmodule HoldLedgerReview.Part3Verification do
  @moduledoc """
  Source-bound inspection of the EXISTING formal gate's reports. An activity
  result is not proof acceptance. Only ProofEvidence's required full-catalog
  checker/export/axiom/source validation can establish that status.
  """
  alias HoldLedgerReview.{Anchor, Part3Snapshots, ProofEvidence}
  alias HoldLedgerReview.Claims.Source

  @activities ~w(source_extraction pointwise_execution elaboration export checker acceptance)
  def activities, do: @activities

  def inspect_report(snapshot_id, relative) when is_binary(relative) do
    root = Part3Snapshots.root(snapshot_id)
    with {:ok, snapshot} <- Part3Snapshots.load(snapshot_id),
         true <- String.starts_with?(relative, "tmp/verification/part3-") and String.ends_with?(relative, "/checked.json"),
         {:ok, bytes} <- Anchor.read_under(root, relative),
         true <- byte_size(bytes) <= 10_000_000,
         {:ok, report} <- Jason.decode(bytes),
         {:ok, sources} <- Source.snapshot(root) do
      slugs = Enum.map(sources.catalog, & &1["slug"])
      acceptance = ProofEvidence.status(root, report, slugs)
      provenance = %{"path" => relative, "sha256" => Anchor.sha(bytes), "bytes" => byte_size(bytes)}
      rows =
        Enum.map(@activities, fn kind ->
          %{"kind" => kind, "status" => activity_status(kind, report, acceptance),
            "acceptance_status" => Atom.to_string(acceptance), "report" => provenance,
            "snapshot_id" => snapshot["snapshot_id"], "requested_scope" => "full_required_catalog"}
        end)
      {:ok, rows}
    else
      _ -> {:error, :missing_stale_or_invalid_verification_report}
    end
  end

  def inspect_report(_, _), do: {:error, :invalid_report_path}

  defp activity_status("pointwise_execution", _report, _), do: "not_run"
  defp activity_status("source_extraction", _report, status), do: if(status == :stale, do: "failed", else: "succeeded")
  defp activity_status("elaboration", report, status) do
    cond do
      status == :stale -> "failed"
      report["mode"] != "EXECUTED" -> "not_run"
      is_map(report["laws"]) and map_size(report["laws"]) > 0 and Enum.all?(report["laws"], fn {_slug, law} -> law["native_passed"] == true end) -> "succeeded"
      true -> "failed"
    end
  end
  defp activity_status("export", report, status) do
    cond do
      status == :stale -> "failed"
      not is_map(report["laws"]) or map_size(report["laws"]) == 0 -> "not_run"
      Enum.all?(report["laws"], fn {_slug, law} ->
        is_list(law["exports"]) and law["exports"] != [] and
          Enum.all?(law["exports"], fn e -> e["passed"] == true and is_binary(e["export_sha256"]) end)
      end) -> "succeeded"
      true -> "failed"
    end
  end
  defp activity_status("checker", _r, :full_catalog_checked), do: "succeeded"
  defp activity_status("checker", _r, :selected_checked), do: "succeeded"
  defp activity_status("checker", _r, :development_only), do: "not_run"
  defp activity_status("checker", _r, _), do: "failed"
  defp activity_status("acceptance", _r, :full_catalog_checked), do: "succeeded"
  defp activity_status("acceptance", _r, :not_supplied), do: "not_run"
  defp activity_status("acceptance", _r, _), do: "failed"
end
