defmodule HoldLedgerReviewWeb.ReviewLiveTest do
  use HoldLedgerReviewWeb.ConnCase
  import Phoenix.LiveViewTest
  alias HoldLedgerReview.{Packet, Receipts, Session}

  setup do
    dir = Path.join(System.tmp_dir!(), "review-receipts-#{System.unique_integer([:positive])}")
    Application.put_env(:hold_ledger_review_web, :receipt_dir, dir)

    on_exit(fn ->
      Application.delete_env(:hold_ledger_review_web, :receipt_dir)
      File.rm_rf!(dir)
    end)

    :ok
  end

  test "prediction, challenge, claim switch and branch lineage", %{conn: conn} do
    {:ok, v, _} = live(conn, "/review/void_pending")
    refute has_element?(v, "#actual-output")
    refute has_element?(v, "#predicate-matrix")

    v
    |> form("#prediction-form", %{"note" => "Keep exposure"})
    |> render_submit(%{"choice" => "retain"})

    assert has_element?(v, "#actual-output", ":voiding")
    v |> element("#candidate-early_release_no_effect") |> render_click()
    assert has_element?(v, "#branch-label", "Counterfactual")
    assert has_element?(v, "#matrix-early_release_no_effect", "excluded")
    v |> element("#claim-retention") |> render_click()
    assert has_element?(v, "#matrix-early_release_no_effect", "passes selected")
    v |> element("#follow-event") |> render_click()
    assert has_element?(v, "#follow-output", ":admitted")
    v |> element("#candidate-correct") |> render_click()
    refute has_element?(v, "#follow-output")
    v |> element("#follow-event") |> render_click()
    assert has_element?(v, "#follow-output", ":insufficient_amount")
    v |> element("#law-po_exposure_retain") |> render_click()
    assert has_element?(v, ".source-excerpt", "requires:")
    assert has_element?(v, "#proof-status", "not_supplied")
  end

  test "every prediction reveals and refresh starts a separate session", %{conn: conn} do
    for choice <- ~w(retain release uncertain) do
      {:ok, v, _} = live(conn, "/review/void_pending")
      v |> form("#prediction-form") |> render_submit(%{"choice" => choice})
      assert has_element?(v, "#actual-output")
    end

    {:ok, a, _} = live(conn, "/review/void_pending")
    {:ok, b, _} = live(conn, "/review/void_pending")
    a |> form("#prediction-form") |> render_submit(%{"choice" => "retain"})
    refute has_element?(b, "#actual-output")
    {:ok, exact, _} = live(conn, "/review/exact_fit")
    exact |> form("#prediction-form") |> render_submit(%{"choice" => "admit"})
    render_click(exact, "select_candidate", %{"id" => "early_release"})
    assert has_element?(exact, "#review-error", "unknown_candidate")
  end

  test "human rationale and evidence, immutable receipt and export", %{conn: conn} do
    {:ok, v, _} = live(conn, "/review/void_pending")
    v |> form("#prediction-form") |> render_submit(%{"choice" => "uncertain"})
    render_click(v, "record_review", %{"decision" => "accept_scope"})
    assert has_element?(v, "#review-error", "rationale_and_evidence_required")

    render_click(v, "record_review", %{
      "decision" => "accept_scope",
      "rationale" => "Retains exposure",
      "evidence" => ["void_pending.policy"],
      "formally_checked" => "true"
    })

    assert has_element?(v, "#review-error", "checked_evidence_required")
    render_click(v, "record_review", %{"decision" => "insufficient_evidence", "rationale" => ""})
    {path, _} = assert_redirect(v)
    {:ok, receipt, _} = live(conn, path)
    assert has_element?(receipt, "#receipt-decision", "insufficient_evidence")
    assert has_element?(receipt, "#export-receipt")
    exported = get(conn, path <> "/export")
    assert response(exported, 200) =~ "not_supplied"
    assert response(exported, 200) =~ "not a proof certificate"
  end

  test "stale packet prevents acceptance but permits an honest incomplete record" do
    {:ok, p} = Packet.build("void_pending", report: nil)
    s = Session.new(%{p | source_sha256: Map.put(p.source_sha256, "mix.exs", "old")})
    {:ok, s} = Session.act(s, "predict", %{"choice" => "retain"})

    params = %{
      "decision" => "accept_scope",
      "rationale" => "Reason",
      "evidence" => ["void_pending.policy"]
    }

    assert {:error, :stale_or_disputed_source} = Receipts.record(s, params)
    assert {:ok, id} = Receipts.record(s, %{"decision" => "insufficient_evidence"})
    assert {:ok, r} = Receipts.read(id)
    assert r["stale_at_recording"]
    assert {:ok, other} = Receipts.record(s, %{"decision" => "insufficient_evidence"})
    assert id == other
    assert {:ok, ^r} = Receipts.read(id)
    assert {:error, :invalid_id} = Receipts.read("../../etc/passwd")
  end

  test "scripted question is asynchronous, cited, escaped and leaves facts alone", %{conn: conn} do
    {:ok, v, _} = live(conn, "/review/void_pending")
    v |> form("#prediction-form") |> render_submit(%{"choice" => "retain"})

    v
    |> form("#question-form", %{"question" => "Why can validity permit release?"})
    |> render_submit()

    render_async(v)
    assert has_element?(v, "#explanation-status", "ready")
    assert has_element?(v, ".explanation-item")
    v |> element("#flag-explanation") |> render_click()
    assert has_element?(v, "#actual-output", ":voiding")
    assert has_element?(v, "#proof-status", "not_supplied")
  end

  test "late async response cannot overwrite a different candidate" do
    {:ok, p} = Packet.build("void_pending", report: nil)
    s = Session.new(p)
    socket = %Phoenix.LiveView.Socket{assigns: %{s: s, explanation_status: :idle}}
    response = {:ok, {p.packet_sha256, "early_release", {:ok, %{mode: "forged"}}}}

    assert {:noreply, unchanged} =
             HoldLedgerReviewWeb.ReviewLive.handle_async(:explanation, response, socket)

    assert unchanged.assigns.s.explanation == nil
  end
end
