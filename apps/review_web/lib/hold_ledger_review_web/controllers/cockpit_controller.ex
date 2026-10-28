defmodule HoldLedgerReviewWeb.CockpitController do
  use HoldLedgerReviewWeb, :controller

  alias HoldLedgerReview.{
    Anchor,
    Part3ProofInspector,
    Part3RepairPacket,
    Part3Snapshots,
    Part3Store,
    Part3Verification,
    Trace
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

  def change(conn, _), do: send_resp(conn, 404, "Unknown source side or identity")

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
      {:ok, bytes} ->
        conn |> put_resp_content_type("text/plain", "utf-8") |> send_resp(200, bytes)

      _ ->
        send_resp(conn, 404, "Registered source missing, oversized or stale")
    end
  end

  def law(conn, _), do: send_resp(conn, 404, "Unknown registered law or side")

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

  def artifact(conn, _), do: send_resp(conn, 404, "Unknown artifact or side")

  def export(conn, %{"id" => id}) do
    case Trace.get(id) do
      {:ok, doc} ->
        body =
          Jason.encode!(
            %{
              "trace" => doc,
              "current_source" => Trace.current?(doc),
              "scope" => "recorded_exploration_not_formal_acceptance"
            },
            pretty: true
          )

        send_download(conn, {:binary, body},
          filename: id <> ".json",
          content_type: "application/json"
        )

      _ ->
        send_resp(conn, 404, "Trace unavailable")
    end
  end

  # Explicit local GET/download only. No revision write, provider dispatch or
  # implicit consent is performed by exporting this fixed-scope data packet.
  def repair(conn, %{"id" => id, "file" => file}) do
    case Regex.run(~r/\A(e-[0-9a-f]{32})\.(json|md)\z/, file) do
      [_, evidence_id, format] ->
        repair(conn, %{"id" => id, "evidence_id" => evidence_id, "format" => format})

      _ ->
        send_resp(conn, 404, "Unknown local repair format or evidence identity")
    end
  end

  def repair(conn, %{"id" => id, "evidence_id" => evidence_id, "format" => format})
      when format in ~w(json md) do
    with {:ok, package, :ok} <- Part3Store.get(id),
         {:ok, packet} <- Part3RepairPacket.build(package, evidence_id) do
      {bytes, type} =
        case format do
          "json" -> {Part3RepairPacket.json(packet), "application/json"}
          "md" -> {Part3RepairPacket.markdown(packet), "text/markdown; charset=utf-8"}
        end

      send_download(conn, {:binary, bytes},
        filename: "hold-ledger-repair-#{evidence_id}.#{format}",
        content_type: type
      )
    else
      _ -> send_resp(conn, 409, "Current-source repair export refused; no permission to send")
    end
  end

  def repair(conn, _), do: send_resp(conn, 404, "Unknown local repair format")

  def generated(conn, %{"slug" => slug, "sha" => sha}) do
    case HoldLedgerReview.ProofReading.artifact(slug, sha) do
      {:ok, bytes} ->
        conn |> put_resp_content_type("text/plain", "utf-8") |> send_resp(200, bytes)

      _ ->
        send_resp(conn, 404, "Generated source missing or stale")
    end
  end

  def source(conn, %{"slug" => slug, "source_id" => id, "sha" => sha}) do
    case HoldLedgerReview.ProofReading.source(slug, id, sha) do
      {:ok, bytes} ->
        conn |> put_resp_content_type("text/plain", "utf-8") |> send_resp(200, bytes)

      _ ->
        send_resp(conn, 404, "Identified source missing or stale")
    end
  end
end
