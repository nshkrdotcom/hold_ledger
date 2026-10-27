defmodule HoldLedgerReviewWeb.ReceiptController do
  use HoldLedgerReviewWeb, :controller

  def export(conn, %{"id" => id}) do
    case HoldLedgerReview.Receipts.read(id) do
      {:ok, r} ->
        send_download(conn, {:binary, HoldLedgerReview.Receipts.markdown(r)},
          filename: "hold-ledger-review-" <> id <> ".md",
          content_type: "text/markdown"
        )

      _ ->
        send_resp(conn, 404, "Receipt not found")
    end
  end
end
