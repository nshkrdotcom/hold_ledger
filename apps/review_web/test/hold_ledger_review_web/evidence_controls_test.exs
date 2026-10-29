defmodule HoldLedgerReviewWeb.EvidenceControlsTest do
  use HoldLedgerReviewWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias HoldLedgerReview.{Contrast, ProofReading}

  defp open(conn, slug) do
    {:ok, doc} = Contrast.create(slug)
    {:ok, view, _} = live(conn, "/claims/#{slug}/#{doc["id"]}")
    view
  end

  defp source_text(view, selector) do
    view |> render() |> LazyHTML.from_fragment() |> LazyHTML.query(selector) |> LazyHTML.text()
  end

  test "Proof opens the complete helper declaration and remains repeatable", %{conn: conn} do
    view = open(conn, "l2_identity")
    view |> element("#inspector-tools [phx-value-view=proof]") |> render_click()
    assert has_element?(view, "#proof-script[data-source-view=full]")
    {:ok, reading} = ProofReading.document("l2_identity")

    lines =
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("#proof-script code")
      |> Enum.map(&LazyHTML.text/1)

    assert lines == String.split(hd(reading["declarations"])["text"], "\n")
    view |> element("#full-proof") |> render_click()
    assert has_element?(view, "#proof-script[data-source-view=excerpt]")
    view |> element("#inspector-tools [phx-value-view=proof]") |> render_click()
    assert has_element?(view, "#proof-script[data-source-view=full]")
  end

  test "Conditions exposes exact source assumptions and promise without inventing values", %{
    conn: conn
  } do
    view = open(conn, "l2_identity")
    {:ok, reading} = ProofReading.document("l2_identity")
    assert source_text(view, "#conditions-requires") == reading["contract"]["requires"]
    assert source_text(view, "#conditions-expects") == reading["contract"]["expects"]
    assert has_element?(view, "#condition-source-status", "Evaluation unavailable")
    refute has_element?(view, "#binding-0")
    view |> element("#inspector-tools [phx-value-view=clauses]") |> render_click()

    assert_push_event(view, "focus_evidence", %{
      id: "clauses-panel",
      open_ids: ["condition-source"]
    })
  end

  test "native conditions and full proof retain every registered declaration", %{conn: conn} do
    view = open(conn, "po_exposure_model")
    {:ok, reading} = ProofReading.document("po_exposure_model")
    assert length(reading["declarations"]) == 4

    headers =
      view
      |> render()
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("#condition-source pre")
      |> Enum.map(&LazyHTML.text/1)

    assert headers == Enum.map(reading["declarations"], & &1["header"])

    view |> element("#inspector-tools [phx-value-view=proof]") |> render_click()

    for declaration <- reading["declarations"] do
      assert has_element?(view, "[data-declaration='#{declaration["name"]}']")
    end
  end
end
