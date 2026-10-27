defmodule HoldLedgerReviewWeb.PageController do
  use HoldLedgerReviewWeb, :controller

  def home(conn, _params) do
    text(
      conn,
      "Hold Ledger claim evaluator is available locally. The workbench UI follows in Milestone B."
    )
  end
end
