# Revalidate preserved historical evidence and controlled incomplete derivatives.
# This script does not run Lean or produce fresh formal acceptance.
alias HoldLedgerReview.{
  Anchor,
  Canonical,
  Config,
  Part3ProofInspector,
  Part3Snapshots,
  Part3Store,
  Part3Verification
}

[ids_file] = Enum.drop_while(System.argv(), &(&1 == "--"))
ids = ids_file |> File.read!() |> Jason.decode!()
{:ok, p} = Part3Store.create(ids["baseline"], ids["unchanged"])
sid = ids["unchanged"]
root = Part3Snapshots.root(sid)
prefix = "tmp/verification/part3-historical-revalidation"
File.mkdir_p!(Path.join(root, prefix))
{:ok, pending} = Part3ProofInspector.inspect(p)
"not_run" = pending["formal_acceptance"]
{:ok, _, _queued} = Part3Store.queue_verification(p["id"])

original_path = Path.join(Config.root(), "tmp/verification/gate-b/checked.json")
original_bytes = File.read!(original_path)
original = Jason.decode!(original_bytes)

exports =
  original["laws"] |> Map.values() |> Enum.flat_map(& &1["exports"]) |> Enum.uniq_by(& &1["path"])

Enum.each(exports, fn export ->
  destination = Path.join(root, export["path"])
  File.mkdir_p!(Path.dirname(destination))
  File.cp!(Path.join(Config.root(), export["path"]), destination)
end)

results =
  for {name, report, expected} <- [
        {"partial_controlled_derivative",
         %{original | "laws" => Map.take(original["laws"], ["po_a2"]), "complete" => false},
         "incomplete"},
        {"failed_controlled_derivative", put_in(original, ["laws", "po_a2", "passed"], false),
         "failed"},
        {"stale_preserved_report",
         Jason.decode!(File.read!(Path.join(Config.root(), "tmp/verification/checked.json"))),
         "stale"},
        {"accepted_historical_report_not_fresh_run", original, "full_catalog_checked"}
      ] do
    report_path = prefix <> "/" <> name <> "/checked.json"
    File.mkdir_p!(Path.dirname(Path.join(root, report_path)))

    bytes =
      if name == "accepted_historical_report_not_fresh_run",
        do: original_bytes,
        else: Jason.encode!(report)

    File.write!(Path.join(root, report_path), bytes)
    {:ok, rows} = Part3Verification.inspect_report(sid, report_path)
    ^expected = hd(rows)["acceptance_status"]

    index = %{
      "schema_version" => 1,
      "snapshot_id" => sid,
      "source_manifest_digest" => Canonical.digest(p["proposal"]["manifest"]),
      "requested_scope" => "full_required_catalog",
      "producer" => "historical evidence revalidation; no fresh proof execution",
      "report" => %{
        "path" => report_path,
        "sha256" => Anchor.sha(bytes),
        "bytes" => byte_size(bytes)
      },
      "artifacts" => []
    }

    index_path = prefix <> "/" <> name <> "/artifact-index.json"
    File.write!(Path.join(root, index_path), Canonical.json(index))
    {:ok, saved} = Part3Store.ingest_artifacts(p["id"], index_path)
    {:ok, inspected} = Part3ProofInspector.inspect(saved)
    ^expected = inspected["formal_acceptance"]

    %{
      "case" => name,
      "status" => expected,
      "report_sha256" => Anchor.sha(bytes),
      "snapshot_id" => sid
    }
  end

{:ok, saved, :ok} = Part3Store.get(p["id"])

Enum.each(exports, fn export ->
  File.write!(Path.join(root, export["path"]), "\ncontrolled export drift\n", [:append])
end)

{:ok, drifted} = Part3ProofInspector.inspect(saved)
"incomplete" = drifted["formal_acceptance"]

File.write!(
  Path.join(Config.root(), "tmp/part3_completion/formal-evidence.json"),
  Jason.encode!(
    %{
      "cases" => results,
      "export_drift" => "incomplete",
      "historical_original_sha256" => Anchor.sha(original_bytes),
      "fresh_formal_run" => false,
      "scope" => "49 required original laws; historical gate revalidation only"
    },
    pretty: true
  ) <> "\n"
)

IO.puts(
  "PASS: pending, partial, failed, stale, historical accepted and drifted exports via original ProofEvidence boundary; no fresh formal run"
)
