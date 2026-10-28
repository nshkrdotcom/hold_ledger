defmodule HoldLedgerReviewWeb.CockpitLiveTest do
  use HoldLedgerReviewWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias HoldLedgerReview.{Contrast, ProofReading, Trace}

  defp open(conn, slug \\ "po_exposure_retain") do
    {:ok, doc} = Contrast.create(slug)
    {:ok, view, _} = live(conn, "/claims/#{slug}/#{doc["id"]}")
    {view, doc}
  end

  defp event(view, type, key \\ "2", amount \\ "100") do
    form(view, "#next-event", event: %{type: type, key: key, amount: amount, outcome: "approved"})
    |> render_submit()
  end

  test "default case joins contrast, actual clauses, proof and timeline", %{conn: conn} do
    {view, _} = open(conn)

    for id <- ~w(contrast dissector lean-bridge assumptions timeline scrubber) do
      assert has_element?(view, "##{id}")
    end

    assert has_element?(view, "#ledger-output", "100¢ reserved")
    assert has_element?(view, "#hypothetical-output", "0¢ reserved")
    assert has_element?(view, "#validity-row td:nth-child(2)", "true")
    assert has_element?(view, "#validity-row td:nth-child(3)", "true")
    assert has_element?(view, "#selected-law-row td:nth-child(3)", "false")
    assert has_element?(view, "#dissector", "voided")
    assert has_element?(view, "#lean-bridge pre", "po_exposure_retain/5")
    assert has_element?(view, "#proof-step pre", "have valid")
    refute has_element?(view, "#glossary")
  end

  test "validity law permits the same candidate rejected by retention", %{conn: conn} do
    {view, doc} = open(conn, "po_b1_void")
    assert has_element?(view, "#selected-law-row td:nth-child(3)", "true")
    view |> element("#inspect-retention") |> render_click()
    assert_patch(view, "/claims/po_exposure_retain/#{doc["id"]}")
    assert has_element?(view, "#selected-law-row td:nth-child(3)", "false")
    assert has_element?(view, "#hypothetical-output", "0¢ reserved")
  end

  test "exact fit and exclusion expose source operands without executing a postcondition outside its domain",
       %{conn: conn} do
    {view, _} = open(conn, "po_a2")
    assert has_element?(view, "#dissector", "100 · 100")
    assert has_element?(view, "#ledger-output", "admitted")
    render_click(view, "select_step", %{"id" => "start"})
    event(view, "request", "11", "101")
    assert has_element?(view, "#outside-domain")
    assert has_element?(view, "#ledger-output", "insufficient_amount")
  end

  test "hypothetical branch and original branch retain distinct executions", %{conn: conn} do
    {view, doc} = open(conn)
    element(view, "#edit-candidate") |> render_click()
    element(view, "#branch-candidate") |> render_click()
    assert has_element?(view, "#hypothetical-lineage")
    event(view, "request")
    assert has_element?(view, "#ledger-output", "admitted")
    {:ok, saved} = Trace.get(doc["id"])
    assert List.last(saved["steps"])["origin"] == "hypothetical_continuation"
    original = hd(saved["steps"])
    render_click(view, "select_step", %{"id" => original["id"]})
    event(view, "request")
    assert has_element?(view, "#ledger-output", "insufficient_amount")
  end

  test "candidate counters are explicit, invalid input clears verdicts and saving binds source",
       %{conn: conn} do
    {view, doc} = open(conn)
    params = Contrast.output_form(hd(doc["steps"])["output"]) |> Map.put("used_amount", "0")
    element(view, "#edit-candidate") |> render_click()
    render_change(view, "candidate_change", %{"output" => params})
    assert has_element?(view, "#validity-row td:nth-child(3)", "false")
    assert has_element?(view, "#branch-candidate[disabled]")
    element(view, "#recalculate") |> render_click()
    assert has_element?(view, "#output_used_amount[value='100']")
    render_click(view, "save_challenge", %{})
    {:ok, saved} = Trace.get(doc["id"])
    assert length(saved["challenges"]) == 1
    assert hd(saved["challenges"])["source_identity"] == doc["identity"]
    render_change(view, "candidate_change", %{"output" => Map.put(params, "used_amount", "oops")})
    assert has_element?(view, "#invalid-candidate")
    refute has_element?(view, "#contrast-matrix")
  end

  test "two tabs cannot overwrite a note and forged provider events do not dispatch", %{
    conn: conn
  } do
    {left, doc} = open(conn)
    {:ok, right, _} = live(conn, "/claims/po_exposure_retain/#{doc["id"]}")
    form(left, "#note-form", note: %{text: "Check processor fencing."}) |> render_submit()
    form(right, "#note-form", note: %{text: "Stale judgment."}) |> render_submit()
    assert has_element?(right, "[role=alert]", "Another tab")
    render_click(left, "request_ai", %{"consent" => "true"})
    assert has_element?(left, "[role=alert]", "Unknown action")
    {:ok, saved} = Trace.get(doc["id"])
    assert length(saved["notes"]) == 1
    refute Map.has_key?(saved, "ai_jobs")
  end

  test "source URLs bind registered path and bytes; export does not certify a proof", %{
    conn: conn
  } do
    {_, doc} = open(conn)
    {:ok, reading} = ProofReading.document("po_exposure_retain")
    source = Enum.find(reading["sources"], &(&1["path"] == "test/support/lean/Retention.lean"))
    path = "/claims/po_exposure_retain/source/#{source["id"]}/#{source["sha256"]}"

    assert response(get(conn, path), 200) ==
             File.read!(source["path"] |> then(&Path.join(HoldLedgerReview.Config.root(), &1)))

    assert response(
             get(conn, String.replace(path, source["sha256"], String.duplicate("0", 64))),
             404
           )

    body = get(conn, "/sessions/#{doc["id"]}/export") |> response(200) |> Jason.decode!()
    assert body["current_source"]
    assert body["scope"] == "recorded_exploration_not_formal_acceptance"
  end

  test "all catalog obligations expose actual declarations and native claims remain non-executable" do
    {:ok, laws} = ProofReading.catalog()
    assert length(laws) == 49

    for law <- laws do
      assert {:ok, reading} = ProofReading.document(law["slug"])
      assert reading["declarations"] != []

      assert Enum.all?(reading["declarations"], &(&1["text"] != "")) or
               is_map(reading["inline_proof"]),
             law["slug"]

      if law["kind"] == "lean",
        do: assert(reading["contract"]["status"] == "native_statement_only")
    end
  end
end
