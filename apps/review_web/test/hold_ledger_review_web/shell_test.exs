defmodule HoldLedgerReviewWeb.ShellTest do
  use HoldLedgerReviewWeb.ConnCase
  import Phoenix.LiveViewTest

  test "local shell and independent core", %{conn: conn} do
    assert {:ok, _, _} = live(conn, "/review")
    assert {:ok, view, _} = live(conn, "/review/void_pending")
    assert has_element?(view, "#empty-state")
    assert Process.whereis(HoldLedger.Server) == nil
  end

  test "invalid root is actionable" do
    root = HoldLedgerReview.Config.root()
    on_exit(fn -> Application.put_env(:hold_ledger_review_web, :ledger_root, root) end)
    Application.put_env(:hold_ledger_review_web, :ledger_root, "/missing-ledger-checkout")
    assert_raise ArgumentError, ~r/ledger_root/, &HoldLedgerReview.Config.validate!/0
  end
end
