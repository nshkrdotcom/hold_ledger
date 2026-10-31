defmodule HoldLedgerReviewWeb.ShellTest do
  use HoldLedgerReviewWeb.ConnCase
  import Phoenix.LiveViewTest

  test "claim engine starts without opening a ledger server", %{conn: conn} do
    assert response(get(conn, ~p"/"), 200) =~ "A missing reply."
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
    for route <-
          ~w(/ /start /system /atlas /proofs /assurance /repository /glossary /how-it-fits /examples /translation) do
      html = response(get(conn, route), 200)
      refute html =~ "id=\"claim-navigation\""
      refute html =~ "id=\"review-steps\""
      assert html =~ "Main navigation"
    end
  end

  test "the shell keeps four primary destinations and help off the main task", %{conn: conn} do
    {:ok, view, _} = live(conn, ~p"/")
    assert has_element?(view, "[data-global-nav] > a[href='/']", "Overview")
    assert has_element?(view, "[data-global-nav] > a[href='/lab']", "Case Lab")
    assert has_element?(view, "[data-global-nav] > a[href='/atlas']", "Claim Atlas")
    assert has_element?(view, "[data-global-nav] > a[href='/start']", "Learn")
    refute has_element?(view, "[data-global-nav] > a:nth-child(5)")
    assert has_element?(view, "#edu-help-drawer #edu-control-help")
    assert has_element?(view, "#edu-help-drawer label[for='edu-guidance']", "Extra explanations")
  end
end
