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
    render_click(view, "open_tools", %{"tool" => "events"})

    form(view, "#next-event", event: %{type: type, key: key, amount: amount})
    |> render_submit()
  end

  defp tab(view, name) when name in ~w(proof premises record),
    do: render_click(view, "inspect", %{"view" => name})

  defp tab(_view, _name), do: :ok

  test "landing has a visible comparison, scoped decisions and just one timeline", %{conn: conn} do
    {view, _} = open(conn, "po_a2")

    for id <- ~w(contract-diff boundary-fork decision-docket timeline active-state verdict) do
      assert has_element?(view, "##{id}")
    end

    assert has_element?(view, "#example-provenance", "Example")
    assert has_element?(view, "#coverage-proposal", "No")
    assert has_element?(view, "#ledger-output", "admitted")

    refute has_element?(
             view,
             "#technical-inspector, #visual-timeline, #proof-player, #workspace-tabs, #position"
           )

    tab(view, "proof")
    assert has_element?(view, "#proof-source-workspace")
    assert has_element?(view, "#formal-status", "not_supplied")
    tab(view, "clauses")
    assert has_element?(view, "#dissector")
    assert has_element?(view, ".logic-group")
  end

  test "validity law permits the same candidate rejected by retention", %{conn: conn} do
    {view, doc} = open(conn, "po_b1_void")
    tab(view, "outputs")
    assert has_element?(view, "#selected-law-row td:nth-child(3)", "true")
    render_click(view, "edit_candidate", %{})
    view |> element("#inspect-retention") |> render_click()
    assert_patch(view, "/claims/po_exposure_retain/#{doc["id"]}")
    assert has_element?(view, "#selected-law-row td:nth-child(3)", "false")
    assert has_element?(view, "#hypothetical-output", "0¢ reserved")
  end

  test "exact fit and exclusion expose source operands without executing a postcondition outside its domain",
       %{conn: conn} do
    {view, _} = open(conn, "po_a2")
    tab(view, "clauses")
    assert has_element?(view, "#dissector", "100 ≤ 100")
    tab(view, "outputs")
    assert has_element?(view, "#ledger-output", "admitted")
    render_click(view, "select_step", %{"id" => "start"})
    event(view, "request", "11", "101")
    assert has_element?(view, "#ledger-output", "insufficient_amount")
    tab(view, "clauses")
    assert has_element?(view, "#outside-domain")
  end

  test "hypothetical branch and original branch retain distinct executions", %{conn: conn} do
    {view, doc} = open(conn)
    tab(view, "outputs")
    element(view, "#edit-candidate") |> render_click()
    element(view, "#branch-candidate") |> render_click()
    assert has_element?(view, "#hypothetical-lineage")
    event(view, "request")
    tab(view, "outputs")
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
    tab(view, "outputs")
    element(view, "#edit-candidate") |> render_click()
    render_change(view, "candidate_change", %{"output" => params})
    assert has_element?(view, "#validity-row td:nth-child(3)", "false")
    assert has_element?(view, "#branch-candidate[disabled]")
    render_click(view, "show_advanced", %{})
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
    tab(left, "record")
    tab(right, "record")
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

  test "live amount preview changes actual clauses without writing until added", %{conn: conn} do
    {view, doc} = open(conn, "po_a2")
    render_change(view, "preview_amount", %{"amount" => "101"})
    assert has_element?(view, "#scratch-status")
    assert has_element?(view, "#review-amount[value='101']")
    {:ok, before} = Trace.get(doc["id"])
    assert before["revision"] == doc["revision"]
    render_click(view, "apply_preview", %{})
    {:ok, after_doc} = Trace.get(doc["id"])
    assert length(after_doc["steps"]) == 2
    assert List.last(after_doc["steps"])["event"]["amount"] == 101
  end

  test "current-entry premise comparison never mutates the real session", %{conn: conn} do
    {view, doc} = open(conn)
    tab(view, "premises")
    render_click(view, "toggle_assumption", %{"name" => "fencing"})
    assert has_element?(view, "#premise-local", "0¢")
    assert has_element?(view, "#premise-remote", "100¢")
    assert has_element?(view, "#premise-covered", "No")
    {:ok, unchanged} = Trace.get(doc["id"])
    assert unchanged == doc
    render_click(view, "toggle_assumption", %{"name" => "fencing"})
    assert has_element?(view, "#premise-remote", "0¢")
    assert has_element?(view, "#premise-covered", "Yes")
  end

  test "example disposition preserves scratch input without claiming policy authority", %{
    conn: conn
  } do
    {view, doc} = open(conn, "po_a2")
    render_change(view, "preview_amount", %{"amount" => "99"})
    element(view, "#request-repair") |> render_click()
    assert has_element?(view, "#review-amount[value='99']")
    {:ok, saved} = Trace.get(doc["id"])
    assert length(saved["steps"]) == 1
    assert length(saved["notes"]) == 1
    assert hd(saved["notes"])["text"] =~ "Example review"
  end

  test "actual bounded search result is rechecked and cancellation stays explicit", %{conn: conn} do
    {view, _} = open(conn)
    tab(view, "clauses")
    render_click(view, "edit_candidate", %{})
    render_click(view, "hunt", %{})
    render_async(view, 5_000)
    assert has_element?(view, "#hunt-status", "found")
    tab(view, "outputs")
    assert has_element?(view, "#selected-law-row td:nth-child(3)", "false")
    tab(view, "clauses")
    render_click(view, "edit_candidate", %{})
    render_click(view, "hunt", %{})
    render_click(view, "cancel_hunt", %{})
    render_async(view, 5_000)
    assert has_element?(view, "#hunt-status", "cancelled")
  end

  test "non-request input keeps disabled amount controls in place", %{conn: conn} do
    {view, _} = open(conn)
    assert has_element?(view, "#boundary-fork h3", "No source comparison attached")
    refute has_element?(view, "#boundary-fork", "The labeled example works")
    assert has_element?(view, "#review-amount[disabled]")
    render_click(view, "open_tools", %{"tool" => "events"})
    assert has_element?(view, "#event_amount")
  end

  test "recovering the law picker does not create a new session", %{conn: conn} do
    {view, doc} = open(conn, "po_a2")
    tab(view, "record")
    render_change(view, "law_change", %{"slug" => "po_a2"})
    assert has_element?(view, "#session-record")
    assert {:ok, ^doc} = Trace.get(doc["id"])
  end

  test "scratch input cannot be silently saved by recording an event or branch", %{conn: conn} do
    {view, doc} = open(conn, "po_a2")
    render_change(view, "preview_amount", %{"amount" => "99"})
    assert has_element?(view, "#ledger-output", "99¢")
    render_click(view, "apply_event", %{"event" => %{"type" => "dispatch", "key" => "11"}})
    assert has_element?(view, "[role=alert]", "Save or discard")
    render_click(view, "branch_candidate", %{})
    assert {:ok, ^doc} = Trace.get(doc["id"])
    render_click(view, "apply_preview", %{})
    event(view, "dispatch", "11")
    {:ok, saved} = Trace.get(doc["id"])
    assert length(saved["steps"]) == 3
    assert Enum.at(saved["steps"], 1)["event"]["amount"] == 99
    assert List.last(saved["steps"])["before"]["used_amount"] == 99
    assert has_element?(view, "#ledger-output", "sent")
  end

  test "proof and premises remain independently open with additive registered source", %{
    conn: conn
  } do
    {view, _} = open(conn)
    tab(view, "premises")
    assert has_element?(view, "#proof-panel[open]")
    assert has_element?(view, "#premises-panel[open]")
    {:ok, reading} = ProofReading.document("po_exposure_retain")
    render_click(view, "lemma", %{"name" => hd(reading["references"])["name"]})
    assert has_element?(view, "#proof-script")
    assert has_element?(view, "#inline-source")
    assert has_element?(view, "#premises-panel[open]")
  end

  test "top disposition stays bounded for many stored witnesses (projection only)" do
    evidence = for n <- 1..20, do: %{"id" => Integer.to_string(n), "kind" => "lost_domain_input"}
    package = %{"id" => "projection_fixture", "evidence" => evidence, "human_revision" => 0}

    html =
      render_component(&HoldLedgerReviewWeb.ReviewComponents.disposition/1,
        package: package,
        doc: %{"notes" => []},
        selected_evidence: "20"
      )

    tree = LazyHTML.from_fragment(html)
    assert Enum.count(LazyHTML.query(tree, "#evidence-choice option")) == 20
    assert Enum.count(LazyHTML.query(tree, "button")) == 3

    assert LazyHTML.attribute(LazyHTML.query(tree, "button"), "phx-value-evidence") == [
             "20",
             "20",
             "20"
           ]
  end

  test "mutation chips and status edits update verdict without repairing counters", %{conn: conn} do
    {view, doc} = open(conn)
    render_click(view, "mutate_candidate", %{"kind" => "zero_counters"})
    assert has_element?(view, "#validity-row td:nth-child(3)", "true")
    render_click(view, "restore_candidate", %{})
    render_click(view, "cycle_status", %{"index" => "0"})
    {:ok, unchanged} = Trace.get(doc["id"])
    assert unchanged == doc
    assert has_element?(view, "#hypothetical-output", "100¢ reserved")
    assert has_element?(view, "#validity-row")
  end

  test "registered proof dependencies open inline, forged references are refused", %{conn: conn} do
    {view, _} = open(conn)
    {:ok, reading} = ProofReading.document("po_exposure_retain")
    ref = hd(reading["references"])
    render_click(view, "lemma", %{"name" => ref["name"]})
    assert has_element?(view, "#inline-source", ref["name"])
    render_click(view, "inspect_law", %{"slug" => "po_a2"})
    refute has_element?(view, "#inline-source")
    render_click(view, "close_source", %{})
    render_click(view, "lemma", %{"name" => "../../secret"})
    refute has_element?(view, "#inline-source")
    assert has_element?(view, "[role=alert]", "unavailable")
  end

  test "custom event builder stays open while fields change", %{conn: conn} do
    {view, _} = open(conn, "po_a2")
    render_click(view, "open_tools", %{"tool" => "events"})
    render_change(view, "event_change", %{"event" => %{"type" => "dispatch"}})
    assert has_element?(view, "#tool-drawer #event-builder")
    assert has_element?(view, "#event_amount[disabled]")
  end

  test "policy anchor reads only registered current source", %{conn: conn} do
    {view, _} = open(conn, "po_a2")
    assert has_element?(view, "#policy-anchor", "An exact amount fit is admitted")
    element(view, "#policy-source") |> render_click()
    assert has_element?(view, "#inline-source", "Specification")
    render_click(view, "close_source", %{})

    render_click(view, "inspect_registered_source", %{
      "id" => "unknown",
      "sha" => String.duplicate("0", 64)
    })

    refute has_element?(view, "#inline-source")
  end

  test "malformed presentation selectors cannot crash or change the case", %{conn: conn} do
    {view, doc} = open(conn)
    render_click(view, "helper", %{"phase" => "requires", "binding" => nil, "path" => ""})
    render_click(view, "select_binding", %{"index" => nil})
    render_click(view, "helper", %{"phase" => "requires", "binding" => "0", "path" => "999"})
    assert has_element?(view, "#ledger-output", "100¢")
    assert {:ok, ^doc} = Trace.get(doc["id"])
  end

  test "saving a note preserves the scratch input and intentionally inconsistent draft", %{
    conn: conn
  } do
    {view, doc} = open(conn, "po_a2")
    render_change(view, "preview_amount", %{"amount" => "99"})
    render_click(view, "restore_candidate", %{})
    render_click(view, "mutate_candidate", %{"kind" => "zero_counters"})
    assert has_element?(view, "#validity-row td:last-child", "false")

    render_submit(view, "record_note", %{
      "note" => %{"text" => "Keep this invalid counter challenge."}
    })

    assert has_element?(view, "#review-amount[value='99']")
    assert has_element?(view, "#hypothetical-output", "0¢ reserved")
    assert has_element?(view, "#validity-row td:last-child", "false")
    {:ok, saved} = Trace.get(doc["id"])
    assert saved["steps"] == doc["steps"]
    assert length(saved["notes"]) == 1
  end
end
