defmodule HoldLedgerReviewWeb.WorkbenchLiveTest do
  use HoldLedgerReviewWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias HoldLedgerReview.{Adversarial, ReviewStore}

  test "single workbench is the entrypoint and all old routes stay removed", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/workbench")
    assert html =~ "Decide what the ledger"
    assert html =~ "new-review-choices"
    for route <- ["/review", "/review/void_pending", "/review/receipts/fake"] do
      assert :error ==
        Phoenix.Router.route_info(HoldLedgerReviewWeb.Router, "GET", route, "localhost")
    end
  end

  test "loaded review contains focused cards, exact full witness, law matrix, graph and report links", %{conn: conn} do
    {:ok, doc, _witness} = ReviewStore.create("P06")
    {:ok, view, html} = live(conn, "/workbench/#{doc["id"]}")
    assert html =~ "Your judgment"
    assert html =~ "core.p06.escape"
    assert html =~ "catcher-matrix"
    assert html =~ "No follow-on event selected"
    assert html =~ "export.md"
    assert render_click(element(view, "#map-toggle")) =~ "design-map"
    assert render_click(element(view, "#source-toggle")) =~ "source-panel"
  end

  test "malformed latest draft never saves the preceding valid Escape probe", %{conn: conn} do
    {:ok, doc, witness} = ReviewStore.create("P04")
    {:ok, view, _} = live(conn, "/workbench/#{doc["id"]}")
    form = Adversarial.form(witness)
    assert render_change(view, "draft_changed", %{"draft" => Map.put(form, "output_json", "{")}) =~ "draft-error"
    {:ok, after_change} = ReviewStore.get(doc["id"])
    assert after_change["pinned_probes"] == []
    assert after_change["answers"] == []
  end
end
