defmodule HoldLedgerReviewWeb.PageControllerTest do
  use HoldLedgerReviewWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert redirected_to(conn) == "/review"
  end
end
