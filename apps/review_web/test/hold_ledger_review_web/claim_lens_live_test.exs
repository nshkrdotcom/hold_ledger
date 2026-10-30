defmodule HoldLedgerReviewWeb.ClaimLensLiveTest do
  use HoldLedgerReviewWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  test "Review-first is the default and initial feedback remains gated", %{conn: conn} do
    {:ok, view, _} = live(conn, "/lens/po_a2")
    assert has_element?(view, "#lens-feedback-withheld")
    assert has_element?(view, "#lens-confirm[disabled]")
    assert has_element?(view, "#lens-case-brief", "Proposed output")
    assert has_element?(view, "#lens-evidence-drawer")
    assert has_element?(view, "#lens-demo-scope", "Two reviews to practice")
    assert has_element?(view, "#lens-demo-scope a[href='/lens/po_a2']")
    assert has_element?(view, "#lens-demo-scope a[href='/lens/po_exposure_retain']")
    refute has_element?(view, "#lens-policy-verdict")
    refute has_element?(view, "#lens-near-misses")

    element(view, "#lens-decision-permits-forbidden") |> render_click()

    form(view, "#lens-review-form",
      review: %{
        policy_anchor: "guides/specification.md",
        contract_clause: "requires: equality",
        witness: "100 cents out of 100",
        scope_limit: "Hypothetical; no Lean run",
        text: "Initial scoped argument"
      }
    )
    |> render_submit()

    assert has_element?(view, "#lens-initial-answer", "guides/specification.md")
    assert has_element?(view, "#lens-initial-answer", "Hypothetical; no Lean run")
    assert has_element?(view, "#lens-copy-packet[data-packet*='NOT checked by Lean']")
    assert has_element?(view, "#lens-near-misses", "Legitimate local release")
    assert has_element?(view, "#lens-premise-ledger")
    assert has_element?(view, "#lens-policy-verdict")
  end

  test "claim lens opens with source-bound proof reading and distinct evidence levels", %{
    conn: conn
  } do
    {:ok, view, _html} = live(conn, "/lens/po_a2?mode=explore")
    assert has_element?(view, "#lens-policy", "An exact amount fit is admitted.")
    assert has_element?(view, "#lens-source-contract", "request_eligible?")
    assert has_element?(view, "#lens-lean-reading", "What the theorem states")
    assert has_element?(view, "#lens-evidence-status", "Proof check for proposed change")
    assert has_element?(view, "#lens-formal-status")
    assert has_element?(view, "#lens-gap", "Potential loss of required coverage")
    assert has_element?(view, "#lens-baseline-verdict", "Claim rejects this output")
    assert has_element?(view, "#lens-hypothetical-verdict", "Claim says nothing about this input")
    assert has_element?(view, "#lens-observed-path")
    assert has_element?(view, "#lens-variation-strict[aria-pressed=true]")
    assert has_element?(view, "#lens-modes a[href='/claims/po_a2?compare=open']")
    assert has_element?(view, "#lens-source-contract a[href^='/claims/po_a2/source/']")
  end

  test "switching witness and variation changes claim coverage without saving", %{conn: conn} do
    {:ok, view, _} = live(conn, "/lens/po_a2?mode=explore")
    element(view, "#lens-witness-below") |> render_click()
    assert has_element?(view, "#lens-witness-below[aria-pressed=true]")
    assert has_element?(view, "#lens-hypothetical-verdict", "Claim rejects this output")

    element(view, "#lens-witness-above") |> render_click()
    assert has_element?(view, "#lens-policy-verdict", "Policy permits this output")
    assert has_element?(view, "#lens-baseline-verdict", "Claim says nothing about this input")

    element(view, "#lens-witness-exact") |> render_click()
    element(view, "#lens-variation-proof_only") |> render_click()
    assert has_element?(view, "#lens-gap", "No claim-level change")
    assert has_element?(view, "#lens-variation-proof_only[aria-pressed=true]")
  end

  test "retention lens shows legitimate terminal confirmation and linked source passage", %{
    conn: conn
  } do
    {:ok, view, _} = live(conn, "/lens/po_exposure_retain?mode=explore")
    assert has_element?(view, "#lens-policy-verdict", "Policy permits this output")
    assert has_element?(view, "#lens-baseline-verdict", "Claim says nothing about this input")
    assert has_element?(view, "#lens-hypothetical-verdict", "Claim rejects this output")
    assert has_element?(view, "#lens-gap", "Potential overconstraint")
    assert has_element?(view, "#lens-proof-steps")
    element(view, "#lens-witness-void") |> render_click()
    assert has_element?(view, "#lens-baseline-verdict", "Claim rejects this output")
    element(view, "#lens-clause-retain-protected") |> render_click()
    assert has_element?(view, "#lens-selected-clause", "protected status")
    assert has_element?(view, "#lens-proof-steps")
  end

  test "draft review decision stays local to the page and rejects forged inputs", %{conn: conn} do
    {:ok, view, _} = live(conn, "/lens/po_a2?mode=explore")
    element(view, "#lens-decision-concern") |> render_click()
    assert has_element?(view, "#lens-decision-concern[aria-pressed=true]")
    assert has_element?(view, "#lens-draft-state", "possible guarantee loss")

    form(view, "#lens-review-form", review: %{text: "Check changed input domain."})
    |> render_change()

    assert has_element?(view, "#lens-review-form textarea", "Check changed input domain.")
    render_click(view, "decision", %{"choice" => "approved_by_kernel"})
    assert has_element?(view, "#lens-decision-concern[aria-pressed=true]")
    element(view, "#lens-witness-below") |> render_click()
    refute has_element?(view, ".lens-decisions [aria-pressed=true]")
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
      {:ok, view, _} = live(conn, "/lens/po_a2?mode=explore")
      assert has_element?(view, "#lens-baseline-verdict", "Claim rejects this output")
      Application.put_env(:hold_ledger_review_web, :ledger_root, "/missing-ledger-checkout")

      render_click(view, event, params)
      assert has_element?(view, "#lens-unavailable")
      refute has_element?(view, "#lens-baseline-verdict")
      refute has_element?(view, "#lens-policy-verdict")
    end
  end

  test "switching studies clears the human draft", %{conn: conn} do
    {:ok, view, _} = live(conn, "/lens/po_a2?mode=explore")
    element(view, "#lens-decision-concern") |> render_click()
    form(view, "#lens-review-form", review: %{text: "Exact-fit concern"}) |> render_change()

    render_patch(view, "/lens/po_exposure_retain?mode=explore")
    refute has_element?(view, ".lens-decisions [aria-pressed=true]")
    refute has_element?(view, "#lens-review-form textarea", "Exact-fit concern")
    assert has_element?(view, "#lens-witness-confirmed[aria-pressed=true]")
  end

  test "Challenge omits feedback until an explicit initial answer is confirmed", %{conn: conn} do
    {:ok, view, _} = live(conn, "/lens/po_a2?mode=challenge")
    assert has_element?(view, "#lens-feedback-withheld")
    assert has_element?(view, "#lens-confirm[disabled]")
    assert has_element?(view, "#lens-source-contract")
    refute has_element?(view, ".lens-decisions [aria-pressed=true]")
    refute has_element?(view, "#lens-policy-verdict")
    refute has_element?(view, "#lens-gap")
    refute has_element?(view, "#lens-coverage")
    refute has_element?(view, "#lens-worked-challenge")
    refute has_element?(view, "#lens-selected-clause")

    render_submit(view, "reveal", %{"review" => %{"text" => "No answer chosen"}})
    refute has_element?(view, "#lens-gap")
    element(view, "#lens-decision-unresolved") |> render_click()
    refute has_element?(view, "#lens-confirm[disabled]")
    refute has_element?(view, "#lens-gap")
    form(view, "#lens-review-form", review: %{text: "Need source review"}) |> render_submit()
    assert has_element?(view, "#lens-initial-answer", "needs more evidence")
    assert has_element?(view, "#lens-gap", "Potential loss of required coverage")
    assert has_element?(view, "#lens-coverage-exact[data-change=removed]")
    assert has_element?(view, "#lens-worked-challenge", "insufficient_amount")
    assert has_element?(view, "#lens-decision-unresolved[disabled]")

    render_click(view, "decision", %{"choice" => "concern"})
    render_change(view, "review_note", %{"review" => %{"text" => "Changed after feedback"}})
    render_submit(view, "reveal", %{"review" => %{"text" => "Changed after feedback"}})
    assert has_element?(view, "#lens-initial-answer", "Need source review")
    refute has_element?(view, "#lens-initial-answer", "Changed after feedback")
    assert has_element?(view, "#lens-decision-unresolved[aria-pressed=true]")
  end

  test "Challenge attempts reset on witness, hypothesis, study, mode and try again", %{conn: conn} do
    {:ok, view, _} = live(conn, "/lens/po_a2?mode=challenge")

    for selector <- ["#lens-witness-below", "#lens-variation-original", "#lens-try-again"] do
      reveal_challenge(view)
      element(view, selector) |> render_click()
      refute has_element?(view, "#lens-gap")
      refute has_element?(view, ".lens-decisions [aria-pressed=true]")
      refute has_element?(view, "#lens-review-form textarea", "Initial answer")
    end

    reveal_challenge(view)
    render_patch(view, "/lens/po_exposure_retain?mode=challenge")
    refute has_element?(view, "#lens-gap")
    refute has_element?(view, "#lens-initial-answer")
    assert has_element?(view, "#lens-study-picker a[href='/lens/po_a2']")
    reveal_challenge(view)
    render_patch(view, "/lens/po_exposure_retain?mode=explore")
    assert has_element?(view, "#lens-gap")
    refute has_element?(view, ".lens-decisions [aria-pressed=true]")
    render_patch(view, "/lens/po_exposure_retain?mode=challenge")
    refute has_element?(view, "#lens-gap")
    assert has_element?(view, "#lens-confirm[disabled]")
  end

  test "source loss also refuses Challenge confirmation", %{conn: conn} do
    root = HoldLedgerReview.Config.root()
    on_exit(fn -> Application.put_env(:hold_ledger_review_web, :ledger_root, root) end)
    {:ok, view, _} = live(conn, "/lens/po_a2?mode=challenge")
    element(view, "#lens-decision-concern") |> render_click()
    Application.put_env(:hold_ledger_review_web, :ledger_root, "/missing-ledger-checkout")
    render_submit(view, "reveal", %{"review" => %{"text" => "Initial answer"}})
    assert has_element?(view, "#lens-unavailable")
    refute has_element?(view, "#lens-gap")
    refute has_element?(view, "#lens-initial-answer")
  end

  test "semantic hypothetical selects its reviewed clause and evidence labels stay honest", %{
    conn: conn
  } do
    {:ok, view, _} = live(conn, "/lens/po_a2?mode=explore")
    element(view, "#lens-clause-capacity-slots") |> render_click()
    element(view, "#lens-variation-strict") |> render_click()

    assert has_element?(
             view,
             "#lens-clause-capacity-amount.lens-clause-edited[aria-pressed=true]"
           )

    assert has_element?(
             view,
             "#lens-hypothetical-verdict[data-applicability=excluded]",
             "says nothing"
           )

    assert has_element?(view, "#lens-evidence-legend")
    refute has_element?(view, "#lens-evidence-status", "missing_or_stale")
    assert has_element?(view, "#lens-lean-reading", "Source text")
    element(view, "#lens-variation-proof_only") |> render_click()
    refute has_element?(view, ".lens-clause-edited")
    assert has_element?(view, "#lens-proof-control", "Requires and expects are identical")
  end

  defp reveal_challenge(view) do
    element(view, "#lens-decision-concern") |> render_click()
    form(view, "#lens-review-form", review: %{text: "Initial answer"}) |> render_submit()
    assert has_element?(view, "#lens-initial-answer")
  end

  test "claim navigation keeps the active case and offers only its own guided study", %{conn: conn} do
    for slug <- ~w(po_a2 po_exposure_retain l2_identity) do
      {:ok, doc} = HoldLedgerReview.Contrast.create(slug)
      {:ok, view, _} = live(conn, "/claims/#{slug}/#{doc["id"]}")
      assert has_element?(view, "#claim-navigation a[href='/atlas/#{slug}']", "Read claim")

      assert has_element?(
               view,
               "#claim-navigation a[href='/claims/#{slug}/#{doc["id"]}'][aria-current='page']",
               "Case Lab"
             )

      if slug in ~w(po_a2 po_exposure_retain) do
        assert has_element?(view, "#claim-navigation a[href='/lens/#{slug}']", "Guided practice")
      else
        refute has_element?(view, "#claim-navigation a[href^='/lens/']")
        assert has_element?(view, "#decision-docket", "Mark reviewed")
      end

      refute has_element?(view, "#review-steps")
      assert has_element?(view, "#case-review-modes a[href$='compare=open']", "Compare versions")
    end
  end
end
