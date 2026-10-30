defmodule HoldLedgerReviewWeb.ShellTest do
  use HoldLedgerReviewWeb.ConnCase

  test "claim engine starts without opening a ledger server", %{conn: conn} do
    assert response(get(conn, ~p"/"), 200) =~ "Understand payment holds"
    assert response(get(conn, ~p"/lab"), 200) =~ "Opening Case Lab"
    assert Process.whereis(HoldLedgerReview.Claims)
    assert Process.whereis(HoldLedger.Server) == nil
  end

  test "invalid source root fails explicitly" do
    root = HoldLedgerReview.Config.root()
    on_exit(fn -> Application.put_env(:hold_ledger_review_web, :ledger_root, root) end)
    Application.put_env(:hold_ledger_review_web, :ledger_root, "/missing-ledger-checkout")
    assert_raise ArgumentError, ~r/ledger_root/, &HoldLedgerReview.Config.validate!/0
  end

  test "general pages do not imply a selected claim or review progress", %{conn: conn} do
    for route <- ~w(/ /start /system /atlas /proofs /assurance /repository /glossary) do
      html = response(get(conn, route), 200)
      refute html =~ "id=\"claim-navigation\""
      refute html =~ "id=\"review-steps\""
      assert html =~ "Main navigation"
    end
  end
end
