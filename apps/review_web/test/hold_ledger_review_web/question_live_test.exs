defmodule HoldLedgerReviewWeb.QuestionLiveTest do
  use HoldLedgerReviewWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias HoldLedgerReview.{Contrast, Trace}

  test "header prepares a question without sending or saving the scratch case", %{conn: conn} do
    {:ok, doc} = Contrast.create("po_a2")
    {:ok, view, _} = live(conn, "/claims/po_a2/#{doc["id"]}")
    assert has_element?(view, ".site-header #question-assistant")
    refute has_element?(view, "#question-panel")

    view
    |> form("#header-question-form", question: %{text: "Why is capacity reserved?"})
    |> render_submit()

    assert has_element?(view, "#question-panel")
    assert has_element?(view, "#question-consent:not(:checked)")
    assert has_element?(view, "#question-send[disabled]")
    assert has_element?(view, "#question-context", "lib/hold_ledger/spec.ex")
    {:ok, same} = Trace.get(doc["id"])
    assert same == doc
    view |> element("#question-close") |> render_click()
    refute has_element?(view, "#question-panel")
  end
end
