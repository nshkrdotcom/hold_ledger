defmodule HoldLedgerReviewWeb.ClaimLensLiveTest do
  use HoldLedgerReviewWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  test "claim lens opens with source-bound proof reading and distinct evidence levels", %{
    conn: conn
  } do
    {:ok, view, _html} = live(conn, "/lens/po_a2")
    assert has_element?(view, "#lens-policy", "An exact amount fit is admitted.")
    assert has_element?(view, "#lens-source-contract", "request_eligible?")
    assert has_element?(view, "#lens-lean-reading", "What the theorem states")
    assert has_element?(view, "#lens-evidence-status", "Hypothetical edit proof")
    assert has_element?(view, "#lens-formal-status")
    assert has_element?(view, "#lens-gap", "Potential loss of required coverage")
    assert has_element?(view, "#lens-baseline-verdict", "Rejects this output")
    assert has_element?(view, "#lens-hypothetical-verdict", "Outside the claim")
    assert has_element?(view, "#lens-observed-path")
    assert has_element?(view, "#lens-variation-strict[aria-pressed=true]")
    assert has_element?(view, "#lens-modes a[href='/claims/po_a2?compare=open']")
    assert has_element?(view, "#lens-source-contract a[href^='/claims/po_a2/source/']")
  end

  test "switching witness and variation changes claim coverage without saving", %{conn: conn} do
    {:ok, view, _} = live(conn, "/lens/po_a2")
    element(view, "#lens-witness-below") |> render_click()
    assert has_element?(view, "#lens-witness-below[aria-pressed=true]")
    assert has_element?(view, "#lens-hypothetical-verdict", "Rejects this output")

    element(view, "#lens-witness-above") |> render_click()
    assert has_element?(view, "#lens-policy-verdict", "Policy permits this output")
    assert has_element?(view, "#lens-baseline-verdict", "Outside the claim")

    element(view, "#lens-witness-exact") |> render_click()
    element(view, "#lens-variation-proof_only") |> render_click()
    assert has_element?(view, "#lens-gap", "No claim-level change")
    assert has_element?(view, "#lens-variation-proof_only[aria-pressed=true]")
  end

  test "retention lens shows legitimate terminal confirmation and linked source passage", %{
    conn: conn
  } do
    {:ok, view, _} = live(conn, "/lens/po_exposure_retain")
    assert has_element?(view, "#lens-policy-verdict", "Policy permits this output")
    assert has_element?(view, "#lens-baseline-verdict", "Outside the claim")
    assert has_element?(view, "#lens-hypothetical-verdict", "Rejects this output")
    assert has_element?(view, "#lens-gap", "Potential overconstraint")
    assert has_element?(view, "#lens-proof-steps")
    element(view, "#lens-witness-void") |> render_click()
    assert has_element?(view, "#lens-baseline-verdict", "Rejects this output")
    element(view, "#lens-clause-retain-protected") |> render_click()
    assert has_element?(view, "#lens-selected-clause", "protected status")
    assert has_element?(view, "#lens-proof-steps")
  end

  test "draft review decision stays local to the page and rejects forged inputs", %{conn: conn} do
    {:ok, view, _} = live(conn, "/lens/po_a2")
    element(view, "#lens-decision-concern") |> render_click()
    assert has_element?(view, "#lens-decision-concern[aria-pressed=true]")
    assert has_element?(view, "#lens-draft-state", "possible guarantee loss")

    form(view, "#lens-review-form", review: %{text: "Check changed input domain."})
    |> render_change()

    assert has_element?(view, "#lens-review-form textarea", "Check changed input domain.")
    render_click(view, "decision", %{"choice" => "approved_by_kernel"})
    assert has_element?(view, "#lens-decision-concern[aria-pressed=true]")
    element(view, "#lens-witness-below") |> render_click()
    assert has_element?(view, "#lens-decision-unresolved[aria-pressed=true]")
  end

  test "unregistered law lens never presents a made-up policy verdict", %{conn: conn} do
    {:ok, view, _} = live(conn, "/lens/l2_identity")
    assert has_element?(view, "#lens-unavailable")
    refute has_element?(view, "#lens-policy-verdict")
  end

  test "ephemeral draft text is redacted from Phoenix event logging" do
    params = %{"review" => %{"text" => "Private draft"}, "_target" => ["review", "text"]}
    assert Phoenix.Logger.filter_values(params)["review"] == "[FILTERED]"
  end

  test "source loss after mounting removes earlier conclusions on every interaction", %{
    conn: conn
  } do
    root = HoldLedgerReview.Config.root()
    on_exit(fn -> Application.put_env(:hold_ledger_review_web, :ledger_root, root) end)

    for {event, params} <- [
          {"witness", %{"id" => "below"}},
          {"variation", %{"id" => "original"}},
          {"clause", %{"id" => "capacity-amount"}},
          {"decision", %{"choice" => "concern"}},
          {"review_note", %{"review" => %{"text" => "draft"}}}
        ] do
      Application.put_env(:hold_ledger_review_web, :ledger_root, root)
      {:ok, view, _} = live(conn, "/lens/po_a2")
      assert has_element?(view, "#lens-baseline-verdict", "Rejects this output")
      Application.put_env(:hold_ledger_review_web, :ledger_root, "/missing-ledger-checkout")

      render_click(view, event, params)
      assert has_element?(view, "#lens-unavailable")
      refute has_element?(view, "#lens-baseline-verdict")
      refute has_element?(view, "#lens-policy-verdict")
    end
  end

  test "switching studies clears the human draft", %{conn: conn} do
    {:ok, view, _} = live(conn, "/lens/po_a2")
    element(view, "#lens-decision-concern") |> render_click()
    form(view, "#lens-review-form", review: %{text: "Exact-fit concern"}) |> render_change()

    render_patch(view, "/lens/po_exposure_retain")
    assert has_element?(view, "#lens-decision-unresolved[aria-pressed=true]")
    refute has_element?(view, "#lens-review-form textarea", "Exact-fit concern")
    assert has_element?(view, "#lens-witness-confirmed[aria-pressed=true]")
  end

  test "case lab exposes direct navigation into claim lens", %{conn: conn} do
    {:ok, doc} = HoldLedgerReview.Contrast.create("po_a2")
    {:ok, view, _} = live(conn, "/claims/po_a2/#{doc["id"]}")
    assert has_element?(view, "#case-review-modes a[href='/lens/po_a2']", "Claim Lens")
    assert has_element?(view, "#case-review-modes a[href$='compare=open']", "Compare versions")
  end
end
