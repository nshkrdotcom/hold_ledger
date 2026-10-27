defmodule HoldLedgerReviewWeb.PageControllerTest do
  use HoldLedgerReviewWeb.ConnCase

  test "GET / is a neutral development entrypoint", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert response(conn, 200) =~ "claim evaluator"
  end

  test "superseded routes do not resolve" do
    for route <- ["/review", "/review/void_pending", "/review/receipts/fake"] do
      assert :error = Phoenix.Router.route_info(HoldLedgerReviewWeb.Router, "GET", route, "localhost")
    end
  end
end
