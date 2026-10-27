defmodule HoldLedgerReviewWeb.ExportController do
  use HoldLedgerReviewWeb, :controller
  alias HoldLedgerReview.{ReviewReport, ReviewStore}

  def export(conn, %{"id" => id, "format" => format}) when format in ~w(md json) do
    case ReviewStore.get(id) do
      {:ok, review} ->
        {body, content_type} = case format do
          "md" -> {ReviewReport.markdown(review), "text/markdown; charset=utf-8"}
          "json" -> {ReviewReport.json(review), "application/json"}
        end
        send_download(conn, {:binary, body}, filename: "review.#{format}", content_type: content_type)
      {:error, _} -> send_resp(conn, 404, "Review unavailable")
    end
  end
end
