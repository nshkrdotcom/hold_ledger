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

  test "loaded review contains focused cards, exact full witness, law matrix, graph and report links",
       %{conn: conn} do
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

  test "AI is visibly optional, and forged clicks without opt-in cannot enqueue jobs", %{conn: conn} do
    {:ok, doc, _} = ReviewStore.create("P01")
    {:ok, view, html} = live(conn, "/workbench/#{doc["id"]}")
    assert html =~ "configured inference service"
    assert has_element?(view, "#ai-deck[disabled]")
    assert has_element?(view, "#ai-challenge[disabled]")
    assert has_element?(view, "#ai-followup[disabled]")
    assert render_click(view, "ai_request", %{"kind" => "deck"}) =~
             "Explicit AI consent"
    assert {:ok, unchanged} = ReviewStore.get(doc["id"])
    assert unchanged["human_revision"] == doc["human_revision"]
    assert unchanged["ai_jobs"] == []
  end

  test "malformed latest draft never saves the preceding valid Escape probe", %{conn: conn} do
    {:ok, doc, witness} = ReviewStore.create("P04")
    {:ok, view, _} = live(conn, "/workbench/#{doc["id"]}")
    form = Adversarial.form(witness)

    assert render_change(view, "draft_changed", %{"draft" => Map.put(form, "output_json", "{")}) =~
             "draft-error"

    {:ok, after_change} = ReviewStore.get(doc["id"])
    assert after_change["pinned_probes"] == []
    assert after_change["answers"] == []
  end

  test "submit re-decodes the raw whole form before any change event", %{conn: conn} do
    {:ok, doc, witness} = ReviewStore.create("P04")
    {:ok, view, _} = live(conn, "/workbench/#{doc["id"]}")
    witness = put_in(witness, ["output", "after", "used_amount"], 99)
    raw = Adversarial.form(witness)

    view
    |> form("#candidate-form", %{"draft" => raw})
    |> render_submit(%{"draft" => %{"choice" => "unacceptable"}})

    {:ok, saved} = ReviewStore.get(doc["id"])
    assert hd(saved["pinned_probes"])["witness"] == witness
    assert hd(saved["answers"])["choice"] == "unacceptable"
    assert hd(saved["answers"])["probe_id"] == hd(saved["pinned_probes"])["id"]
    # A subsequent change is only an ephemeral draft; it cannot revise the committed answer.
    render_change(view, "draft_changed", %{"draft" => Map.put(raw, "output_json", "{")})
    assert has_element?(view, "#escape-acceptable[disabled]")
    assert has_element?(view, "#escape-unacceptable[disabled]")
    assert has_element?(view, "#escape-unsure[disabled]")
    assert render(view) =~ "Historical last-good evaluation only"
    assert {:ok, ^saved} = ReviewStore.get(doc["id"])

    view
    |> form("#candidate-form", %{"draft" => Map.put(raw, "output_json", "{")})
    |> render_submit(%{"draft" => %{"choice" => "unacceptable"}})

    assert {:ok, ^saved} = ReviewStore.get(doc["id"])
  end

  test "every known full source link returns the exact hashed file; unknown IDs fail", %{
    conn: conn
  } do
    alias HoldLedgerReview.{Anchor, Config}
    {:ok, doc, _} = ReviewStore.create("P01")

    for source <- doc["graph_snapshot"]["excerpts"] do
      response = get(conn, "/workbench/#{doc["id"]}/source/#{source["id"]}")
      bytes = response(response, 200)
      assert Anchor.sha(bytes) == source["sha256"]
      assert bytes == File.read!(Path.join(Config.root(), source["path"]))
    end

    assert response(get(conn, "/workbench/#{doc["id"]}/source/unknown"), 404)
  end
end
