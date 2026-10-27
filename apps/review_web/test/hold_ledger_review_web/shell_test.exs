defmodule HoldLedgerReviewWeb.ShellTest do
  use HoldLedgerReviewWeb.ConnCase

  test "claim engine starts without opening a ledger server", %{conn: conn} do
    assert response(get(conn, ~p"/"), 200) =~ "Decide what the ledger"
    assert Process.whereis(HoldLedgerReview.Claims)
    assert Process.whereis(HoldLedger.Server) == nil
  end

  test "invalid source root fails explicitly" do
    root = HoldLedgerReview.Config.root()
    on_exit(fn -> Application.put_env(:hold_ledger_review_web, :ledger_root, root) end)
    Application.put_env(:hold_ledger_review_web, :ledger_root, "/missing-ledger-checkout")
    assert_raise ArgumentError, ~r/ledger_root/, &HoldLedgerReview.Config.validate!/0
  end
end
