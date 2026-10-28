defmodule HoldLedgerReviewWeb.TraceLiveTest do
  use HoldLedgerReviewWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias HoldLedgerReview.{Adversarial, ReviewStore, Trace}

  defp open_trace(conn, mode \\ "ledger") do
    {:ok, doc} = Trace.create(mode)
    {:ok, view, _} = live(conn, "/explore/" <> doc["id"])
    {view, doc}
  end

  defp event(view, type, key \\ "11", amount \\ "100") do
    form(view, "#next-event", event: %{type: type, key: key, amount: amount, outcome: "approved"})
    |> render_submit()
  end

  test "entry is one small explorer with no compulsory quiz or model dispatch", %{conn: conn} do
    {:ok, view, _} = live(conn, "/")
    assert has_element?(view, "#start-trace")
    refute has_element?(view, "#review-primer")
    refute has_element?(view, "#glossary")

    form(view, "#start-trace", start: %{amount: "100", slots: "2", mode: "ledger"})
    |> render_submit()

    assert_redirect(view)
  end

  test "the four panels and timeline follow actual execution", %{conn: conn} do
    {view, _} = open_trace(conn)

    for id <- ~w(guarantee-panel source-panel result-panel evidence-panel timeline scrubber) do
      assert has_element?(view, "#" <> id)
    end

    event(view, "request")
    assert has_element?(view, "#actual-result", "admitted")
    assert has_element?(view, "#amount-counter", "100¢ / 100¢")
    event(view, "dispatch")
    event(view, "timeout")
    assert has_element?(view, "#entries", "unknown")
    assert has_element?(view, "#actual-result", "marked_unknown")
    assert has_element?(view, "#amount-counter", "100¢ / 100¢")
    event(view, "request", "12")
    assert has_element?(view, "#actual-result", "insufficient_amount")
  end

  test "scrub and branching preserve the earlier path", %{conn: conn} do
    {view, doc} = open_trace(conn)
    event(view, "request")
    event(view, "dispatch")
    render_change(view, "scrub", %{"position" => "1"})
    assert has_element?(view, "#actual-result", "admitted")
    event(view, "void")
    assert has_element?(view, "#actual-result", "voided")
    {:ok, loaded} = Trace.get(doc["id"])
    assert length(loaded["steps"]) == 3
    assert Enum.at(loaded["steps"], 1)["parent"] == List.last(loaded["steps"])["parent"]
    {:ok, reopened, _} = live(conn, "/explore/" <> doc["id"])
    assert has_element?(reopened, "#actual-result", "voided")
  end

  test "reusing an existing branch selects its receipt rather than an unrelated leaf", %{
    conn: conn
  } do
    {view, doc} = open_trace(conn)
    event(view, "request")
    event(view, "dispatch")
    render_click(view, "select", %{"id" => "start"})
    event(view, "request")
    assert has_element?(view, "#actual-result", "admitted")
    {:ok, saved} = Trace.get(doc["id"])
    assert length(saved["steps"]) == 2
  end

  test "typed candidate editing preserves inconsistent counters until explicit recalculation", %{
    conn: conn
  } do
    {view, doc} = open_trace(conn)
    event(view, "request")
    element(view, "#edit-candidate") |> render_click()
    {:ok, loaded} = Trace.get(doc["id"])
    candidate = hd(loaded["steps"])["output"] |> put_in(["after", "used_amount"], 0)
    form(view, "#candidate-form", candidate: %{json: Jason.encode!(candidate)}) |> render_submit()
    assert has_element?(view, "#candidate-checks", "false")
    assert has_element?(view, "#branch-candidate[disabled]")
    element(view, "#recalculate") |> render_click()
    assert has_element?(view, "#candidate-form textarea", "100")
    refute has_element?(view, "#candidate-checks")
    render_submit(view, "check_candidate", %{"candidate" => %{"json" => "not json"}})
    assert has_element?(view, "[role=alert]")
    {:ok, unchanged} = Trace.get(doc["id"])
    assert length(unchanged["steps"]) == 1
  end

  test "CAS conflict in two views cannot overwrite a human note", %{conn: conn} do
    {left, doc} = open_trace(conn)
    {:ok, right, _} = live(conn, "/explore/" <> doc["id"])

    form(left, "#note-form",
      note: %{text: "Need deployment evidence.", disposition: "needs_evidence"}
    )
    |> render_submit()

    form(right, "#note-form", note: %{text: "Stale answer", disposition: "considered"})
    |> render_submit()

    assert has_element?(right, "[role=alert]", "Another tab")
    {:ok, saved} = Trace.get(doc["id"])
    assert length(saved["notes"]) == 1
    assert hd(saved["notes"])["text"] == "Need deployment evidence."
  end

  test "source inspection is allowlisted and full bytes are readable", %{conn: conn} do
    {view, _} = open_trace(conn)
    render_click(view, "source", %{"path" => "guides/specification.md"})
    assert has_element?(view, "#source-detail pre", "An exact amount fit is admitted")
    render_click(view, "source", %{"path" => "../../private"})
    assert has_element?(view, "[role=alert]")
  end

  test "coupled model exposes remote deliveries separately", %{conn: conn} do
    {view, _} = open_trace(conn, "exposure")
    event(view, "request")
    event(view, "dispatch")
    event(view, "authorize")
    assert has_element?(view, "#entries", "sent")
    assert has_element?(view, "#remote-state", "approved")
    event(view, "timeout")
    assert has_element?(view, "#entries", "unknown")
    event(view, "observe")
    assert has_element?(view, "#entries", "authorized")
    assert has_element?(view, "#evidence-panel", "unestablished")
  end

  test "forged provider action cannot create a job", %{conn: conn} do
    {view, doc} = open_trace(conn)
    render_click(view, "request_ai", %{"consent" => "true"})
    assert has_element?(view, "[role=alert]", "Unknown action")
    {:ok, saved} = Trace.get(doc["id"])
    assert saved["revision"] == 0
    refute Map.has_key?(saved, "ai_jobs")
  end

  test "old records remain readable and exportable without reinterpreting their schema", %{
    conn: conn
  } do
    {:ok, doc, _} = ReviewStore.create("P06")
    {:ok, view, _} = live(conn, "/workbench/" <> doc["id"])
    assert has_element?(view, "#archived-record")
    refute has_element?(view, "#next-event")

    response =
      get(conn, "/workbench/#{doc["id"]}/export.json") |> response(200) |> Jason.decode!()

    assert response["id"] == doc["id"]

    for source <- doc["graph_snapshot"]["excerpts"] do
      response = get(conn, "/workbench/#{doc["id"]}/source/#{source["id"]}") |> response(200)
      assert response == File.read!(Path.join(HoldLedgerReview.Config.root(), source["path"]))
      assert HoldLedgerReview.Anchor.sha(response) == source["sha256"]
    end

    assert response(get(conn, "/workbench/#{doc["id"]}/source/unknown"), 404)
  end

  test "structured starting entries require explicit totals and preserve the original trace", %{
    conn: conn
  } do
    {view, original} = open_trace(conn)
    element(view, "#edit-start") |> render_click()
    element(view, "#add-entry") |> render_click()

    params = %{
      "amount_limit" => "100",
      "hold_limit" => "2",
      "used_amount" => "0",
      "used_holds" => "0",
      "entries" => %{"0" => %{"key" => "7", "amount" => "50", "status" => "unknown"}}
    }

    render_submit(view, "save_initial", %{"state" => params})
    assert has_element?(view, "[role=alert]", "Starting counters")
    render_change(view, "initial_change", %{"state" => params})
    element(view, "#recalculate-initial") |> render_click()
    assert has_element?(view, "#state_used_amount[value='50']")

    render_submit(view, "save_initial", %{
      "state" => Map.merge(params, %{"used_amount" => "50", "used_holds" => "1"})
    })

    assert_redirect(view)
    {:ok, unchanged} = Trace.get(original["id"])
    assert unchanged["initial"]["entries"] == []
  end

  test "all eight original scenarios still compute with the original source evaluator" do
    for id <- Adversarial.seeds() do
      {:ok, witness} = Adversarial.seed(id)
      assert {:ok, evaluation, _} = Adversarial.evaluate(witness)
      assert evaluation["actual"] == evaluation["oracle"]
    end
  end

  test "a stale trace never inherits the current checkout's formal status", %{conn: conn} do
    {:ok, doc} = Trace.create()

    body =
      put_in(doc, ["identity", "source"], String.duplicate("0", 64))
      |> Map.delete("document_digest")

    bytes =
      HoldLedgerReview.Canonical.json(
        Map.put(body, "document_digest", HoldLedgerReview.Canonical.digest(body))
      )

    File.write!(
      Path.join(
        Application.fetch_env!(:hold_ledger_review_web, :review_store_dir),
        doc["id"] <> ".json"
      ),
      bytes
    )

    {:ok, view, _} = live(conn, "/explore/" <> doc["id"])
    assert has_element?(view, "#apply-event[disabled]")
    assert has_element?(view, "#formal-status", "stale")
    render_click(view, "proof", %{})
    assert has_element?(view, "#proof-detail", "different source")
  end

  test "trace export includes identity and never claims proof acceptance", %{conn: conn} do
    {:ok, doc} = Trace.create()
    body = conn |> get("/explore/#{doc["id"]}/export") |> response(200) |> Jason.decode!()
    assert body["current_source"]
    assert body["trace"]["identity"] == doc["identity"]
    assert body["scope"] == "recorded_exploration_not_formal_acceptance"
  end
end
