defmodule HoldLedgerReviewWeb.QuestionLiveTest do
  use HoldLedgerReviewWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias HoldLedgerReview.{Contrast, Questions, Trace}

  test "one explicit source-sharing submission sends and logs the question without saving scratch",
       %{conn: conn} do
    {:ok, doc} = Contrast.create("po_a2")
    {:ok, view, _} = live(conn, "/claims/po_a2/#{doc["id"]}")
    assert has_element?(view, "#question-sharing", "Shares case + source")
    refute has_element?(view, "#question-panel")
    assert Questions.list("", Questions, doc["id"]) == []

    view
    |> form("#header-question-form", question: %{text: "Why is capacity reserved?"})
    |> render_submit()

    assert has_element?(view, "#question-answer", "Why is capacity reserved?")
    refute has_element?(view, "#question-consent, #question-consent-form, #panel-question-form")
    assert [row] = Questions.list("", Questions, doc["id"])
    assert row["consent"]["packet_digest"] == row["packet"]["digest"]
    assert row["consent"]["actor"] == row["packet"]["actor"]
    {:ok, same} = Trace.get(doc["id"])
    assert same == doc
  end

  test "typing and inspecting context never dispatches; stale submission is refused", %{
    conn: conn
  } do
    {:ok, doc} = Contrast.create("po_a2")
    {:ok, view, _} = live(conn, "/claims/po_a2/#{doc["id"]}")
    view |> form("#header-question-form", question: %{text: "Why?"}) |> render_change()
    view |> element("#question-sharing") |> render_click()
    assert has_element?(view, "#question-context", "lib/hold_ledger/spec.ex")
    assert Questions.list("", Questions, doc["id"]) == []

    view
    |> form("#panel-question-form", question: %{text: "Why?"})
    |> render_submit(question: %{context_id: "stale"})

    assert has_element?(view, "#question-panel [role=alert]", "case changed")
    assert Questions.list("", Questions, doc["id"]) == []
  end
end
