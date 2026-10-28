defmodule HoldLedgerReviewWeb.Part3FileController do
  use HoldLedgerReviewWeb, :controller

  alias HoldLedgerReview.{
    Anchor,
    Part3ProofInspector,
    Part3Snapshots,
    Part3Store,
    Part3Verification
  }

  @max_source 256_000

  # Identified change IDs, not arbitrary browser-supplied paths.
  def change(conn, %{"id" => id, "side" => side, "change_id" => change_id})
      when side in ~w(baseline proposal) do
    with {:ok, p, :ok} <- Part3Store.get(id),
         c when is_map(c) <- Enum.find(p["source_changes"], &(&1["id"] == change_id)),
         {:ok, bytes} <- Part3Snapshots.source(p[side]["snapshot_id"], c["path"]),
         true <- byte_size(bytes) <= @max_source,
         true <- Anchor.sha(bytes) == c[side <> "_sha256"] do
      conn |> put_resp_content_type("text/plain", "utf-8") |> send_resp(200, bytes)
    else
      _ -> send_resp(conn, 404, "Identified source missing, oversized or stale")
    end
  end

  # Registered law slug selects the file; the client never supplies its path.
  def law(conn, %{"id" => id, "side" => side, "slug" => slug})
      when side in ~w(baseline proposal) do
    sid_or_error =
      with {:ok, p, :ok} <- Part3Store.get(id),
           sid = p[side]["snapshot_id"],
           {:ok, catalog_raw} <- Part3Snapshots.source(sid, "verification/laws.json"),
           {:ok, %{"laws" => laws}} <- Jason.decode(catalog_raw),
           record when is_map(record) <- Enum.find(laws, &(&1["slug"] == slug)),
           {:ok, bytes} <- Part3Snapshots.source(sid, record["file"]),
           true <- byte_size(bytes) <= @max_source,
           true <- Anchor.sha(bytes) == p[side]["manifest"][record["file"]] do
        {:ok, bytes}
      else
        _ -> :error
      end

    case sid_or_error do
      {:ok, bytes} -> conn |> put_resp_content_type("text/plain", "utf-8") |> send_resp(200, bytes)
      _ -> send_resp(conn, 404, "Registered source missing, oversized or stale")
    end
  end

  def artifact(conn, %{"id" => id, "side" => side, "sha256" => sha})
      when side in ~w(baseline proposal) do
    with {:ok, p, :ok} <- Part3Store.get(id),
         {:ok, proof} <- Part3ProofInspector.inspect(p),
         version when is_map(version) <-
           Enum.find(proof["versions"], &(&1["side"] == side)),
         item when is_map(item) <-
           Enum.find(version["artifacts"], &(&1["sha256"] == sha and &1["status"] == "present")),
         {:ok, bytes} <- Part3Verification.read_artifact(version["snapshot_id"], item["path"]),
         true <- Anchor.sha(bytes) == item["sha256"] and byte_size(bytes) == item["bytes"] do
      conn |> put_resp_content_type("text/plain", "utf-8") |> send_resp(200, bytes)
    else
      _ -> send_resp(conn, 404, "Artifact missing, oversized or stale")
    end
  end
end
