defmodule HoldLedgerReviewWeb.SourceController do
  use HoldLedgerReviewWeb, :controller
  alias HoldLedgerReview.{Anchor, Config, ReviewStore}

  # No arbitrary checkout path is accepted: only this review's pinned file IDs.
  def show(conn, %{"id" => id, "source_id" => source_id}) do
    with {:ok, review} <- ReviewStore.get(id),
         true <- review["status"] in ~w(in_progress review_concluded),
         source when is_map(source) <- Enum.find(review["graph_snapshot"]["excerpts"], &(&1["id"] == source_id)),
         {:ok, bytes} <- Anchor.read_under(Config.root(), source["path"]),
         true <- Anchor.sha(bytes) == source["sha256"],
         true <- byte_size(bytes) <= 256_000 do
      conn |> put_resp_content_type("text/plain", "utf-8") |> send_resp(200, bytes)
    else
      _ -> send_resp(conn, 404, "Source unavailable or stale")
    end
  end
end
