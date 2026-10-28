defmodule HoldLedgerReviewWeb.TraceController do
  use HoldLedgerReviewWeb, :controller
  alias HoldLedgerReview.Trace

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
end
