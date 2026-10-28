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

    render_click(view, "apply_preview", %{})
  end

  defp tab(view, name) when name in ~w(proof premises record artifacts),
    do: render_click(view, "inspect", %{"view" => name})

  defp tab(_view, _name), do: :ok

  test "landing has a visible comparison, scoped decisions and just one timeline", %{conn: conn} do
    {view, _} = open(conn, "po_a2")

    for id <- ~w(contract-diff boundary-fork timeline active-state verdict proof-panel) do
      assert has_element?(view, "##{id}")
    end

    assert has_element?(view, "#example-provenance", "Example")
    assert has_element?(view, "#selected-claim", "Requires of the result")
    assert has_element?(view, "#output-differences")
    assert has_element?(view, "#nearby-observation")
    assert has_element?(view, "#repair-unavailable")
    assert has_element?(view, "#coverage-proposal", "No")
    assert has_element?(view, "#ledger-output", "Accepted")

    refute has_element?(
             view,
             "#technical-inspector, #visual-timeline, #proof-player, #workspace-tabs, #position"
           )

    tab(view, "proof")
    assert has_element?(view, "#proof-source-workspace")
    tab(view, "artifacts")
    assert has_element?(view, "#formal-status", "not_supplied")
    tab(view, "clauses")
    assert has_element?(view, "#dissector")
    assert has_element?(view, ".logic-group")
  end

  test "validity law permits the same candidate rejected by retention", %{conn: conn} do
    {view, doc} = open(conn, "po_b1_void")
    tab(view, "outputs")
    assert has_element?(view, "#selected-law-row td:last-child", "Accepts alternative")
    render_click(view, "edit_candidate", %{})
    view |> element("#inspect-retention") |> render_click()
    assert_patch(view, "/claims/po_exposure_retain/#{doc["id"]}")
    assert has_element?(view, "#selected-law-row td:last-child", "Rejects alternative")
    assert has_element?(view, "#hypothetical-output", "0¢ reserved")
  end

  test "exact fit and exclusion expose source operands without executing a postcondition outside its domain",
       %{conn: conn} do
    {view, _} = open(conn, "po_a2")
    tab(view, "clauses")

    element(view, "#dissector button[phx-click=helper][phx-value-path='']", "Definition")
    |> render_click()

    assert has_element?(view, "#dissector", "100 ≤ 100")
    tab(view, "outputs")
    assert has_element?(view, "#ledger-output", "Accepted")
    render_click(view, "select_step", %{"id" => "start"})
    event(view, "request", "11", "101")
    assert has_element?(view, "#ledger-output", "Not enough available money")
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
    assert has_element?(view, "#ledger-output", "Accepted")
    {:ok, saved} = Trace.get(doc["id"])
    assert List.last(saved["steps"])["origin"] == "hypothetical_continuation"
    original = hd(saved["steps"])
    render_click(view, "select_step", %{"id" => original["id"]})
    event(view, "request")
    assert has_element?(view, "#ledger-output", "Not enough available money")
  end

  test "candidate counters are explicit, invalid input clears verdicts and saving binds source",
       %{conn: conn} do
    {view, doc} = open(conn)
    params = Contrast.output_form(hd(doc["steps"])["output"]) |> Map.put("used_amount", "0")
    tab(view, "outputs")
    element(view, "#edit-candidate") |> render_click()
    render_change(view, "candidate_change", %{"output" => params})
    assert has_element?(view, "#validity-row td:last-child", "Accounting does not balance")
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
    element(left, "#add-observation") |> render_click()
    element(right, "#add-observation") |> render_click()
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
    tab(view, "record")
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
    assert has_element?(view, "#selected-law-row td:last-child", "Rejects alternative")
    tab(view, "clauses")
    render_click(view, "edit_candidate", %{})
    render_click(view, "hunt", %{})
    render_click(view, "cancel_hunt", %{})
    render_async(view, 5_000)
    assert has_element?(view, "#hunt-status", "cancelled")
  end

  test "non-request input keeps disabled amount controls in place", %{conn: conn} do
    {view, _} = open(conn)
    refute has_element?(view, "#boundary-fork")
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

  test "subsequent events run freely without a hidden history write", %{conn: conn} do
    {view, doc} = open(conn, "po_a2")
    render_change(view, "preview_amount", %{"amount" => "99"})
    render_click(view, "apply_event", %{"event" => %{"type" => "dispatch", "key" => "11"}})
    assert has_element?(view, "#ledger-output", "Authorization pending")
    assert {:ok, ^doc} = Trace.get(doc["id"])
    render_click(view, "apply_preview", %{})
    {:ok, saved} = Trace.get(doc["id"])
    assert length(saved["steps"]) == 3
    assert Enum.at(saved["steps"], 1)["event"]["amount"] == 99
    assert List.last(saved["steps"])["before"]["used_amount"] == 99
  end

  test "proof and premises remain independently open with additive registered source", %{
    conn: conn
  } do
    {view, _} = open(conn)
    tab(view, "premises")
    assert has_element?(view, "#proof-panel")
    assert has_element?(view, "#premises-panel")
    {:ok, reading} = ProofReading.document("po_exposure_retain")
    render_click(view, "lemma", %{"name" => hd(reading["references"])["name"]})
    assert has_element?(view, "#proof-script")
    assert has_element?(view, "#inline-source")
    assert has_element?(view, "#premises-panel")
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
    assert has_element?(view, "#validity-row td:last-child", "Accounting balances")
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
    assert has_element?(view, "#case-tools #event-builder")
    assert has_element?(view, "#event_amount[disabled]")
  end

  test "policy anchor reads only registered current source", %{conn: conn} do
    {view, _} = open(conn, "po_a2")
    assert has_element?(view, "#policy-anchor", "all remaining capacity")
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
    assert has_element?(view, "#validity-row td:last-child", "Accounting does not balance")

    render_submit(view, "record_note", %{
      "note" => %{"text" => "Keep this invalid counter challenge."}
    })

    assert has_element?(view, "#review-amount[value='99']")
    assert has_element?(view, "#hypothetical-output", "0¢ reserved")
    assert has_element?(view, "#validity-row td:last-child", "Accounting does not balance")
    {:ok, saved} = Trace.get(doc["id"])
    assert saved["steps"] == doc["steps"]
    assert length(saved["notes"]) == 1
  end

  test "a note on an unsaved multi-event experiment does not save or discard its steps", %{
    conn: conn
  } do
    {view, doc} = open(conn, "po_a2")
    render_change(view, "preview_amount", %{"amount" => "99"})
    render_click(view, "apply_event", %{"event" => %{"type" => "dispatch", "key" => "11"}})

    render_submit(view, "record_note", %{
      "note" => %{"text" => "Review the pending authorization."}
    })

    {:ok, saved} = Trace.get(doc["id"])
    assert length(saved["notes"]) == 1
    assert saved["steps"] == doc["steps"]
    assert has_element?(view, "#ledger-output", "99¢ reserved")
    render_click(view, "apply_preview", %{})
    {:ok, saved} = Trace.get(doc["id"])
    assert length(saved["steps"]) == 3
    assert hd(saved["notes"])["text"] =~ "Unsaved experiment"
  end

  test "output differences are live, do not persist a draft, and clear on restore", %{conn: conn} do
    {view, original} = open(conn, "po_exposure_retain")
    assert has_element?(view, "#output-differences")
    assert has_element?(view, "#output-differences", "Reserved")
    assert has_element?(view, "#output-differences", "100¢")

    render_click(view, "restore_candidate", %{})
    assert has_element?(view, "#same-output", "Same as code result")
    render_click(view, "mutate_candidate", %{"kind" => "drop_effects"})
    assert has_element?(view, "#output-differences", "Removed action")
    {:ok, unchanged} = Trace.get(original["id"])
    assert unchanged == original
  end

  test "proof stages and observed clause selections connect bidirectionally where reviewed", %{
    conn: conn
  } do
    {view, doc} = open(conn, "po_a2")
    assert has_element?(view, "#connection-scope", "source-reading aids")
    render_click(view, "proof_stage", %{"index" => "2"})
    assert has_element?(view, "#dissector .connected-clause")
    assert has_element?(view, "#selected-reading-links")

    view
    |> element("#clause-0-requires-root > .logic-line > button[phx-click=select_clause]")
    |> render_click()

    assert has_element?(view, "#dissector .selected-clause")
    assert has_element?(view, "#selected-reading-links")
    assert {:ok, ^doc} = Trace.get(doc["id"])
  end

  test "stale clause selection refuses its source generation without changing the trace", %{
    conn: conn
  } do
    {view, doc} = open(conn, "po_a2")

    render_click(view, "select_clause", %{
      "generation" => "outdated",
      "phase" => "requires",
      "binding" => "0",
      "path" => ""
    })

    assert has_element?(view, "[role=alert]", "stale or unavailable")
    assert {:ok, ^doc} = Trace.get(doc["id"])
  end

  test "nearby observation uses original CAS and does not save pending scratch events", %{
    conn: conn
  } do
    {view, original} = open(conn, "po_a2")
    render_change(view, "preview_amount", %{"amount" => "99"})
    element(view, "#add-observation") |> render_click()
    assert has_element?(view, "#note-form")
    assert has_element?(view, "#repair-unavailable")
    view |> form("#note-form", note: %{text: "Check exact-fit boundary."}) |> render_submit()

    assert has_element?(view, "#scratch-status")
    assert has_element?(view, "#review-amount[value='99']")
    {:ok, saved} = Trace.get(original["id"])
    assert saved["steps"] == original["steps"]
    assert hd(saved["notes"])["text"] =~ "Unsaved experiment"
    assert has_element?(view, "#note-form") == false
  end

  test "basis buttons bind the actual observed output and clear prior selection", %{conn: conn} do
    {view, original} = open(conn, "po_exposure_retain")
    view |> element("button[phx-click=basis][phx-value-basis=actual]") |> render_click()
    assert has_element?(view, "#clause-0-actual-root")
    refute has_element?(view, "#clause-0-candidate-root")
    render_click(view, "proof_stage", %{"index" => "4"})
    assert has_element?(view, "#clause-0-actual-root.connected-clause")
    view |> element("button[phx-click=basis][phx-value-basis=candidate]") |> render_click()
    assert has_element?(view, "#clause-0-candidate-root")
    refute has_element?(view, "#clause-0-actual-root")
    refute has_element?(view, "#selected-reading-links")
    assert {:ok, ^original} = Trace.get(original["id"])
  end
end
