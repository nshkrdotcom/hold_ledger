defmodule HoldLedgerReviewWeb.EducationLiveTest do
  use HoldLedgerReviewWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias HoldLedgerReview.Claims
  alias HoldLedgerReviewWeb.Education

  test "editorial inventory covers every registered group exactly once" do
    {:ok, current} = Claims.catalog()
    {:ok, explanations} = Education.claims()
    registered = Enum.map(current, & &1["slug"]) |> Enum.sort()

    editorial =
      Path.expand("../../priv/education_claims.json", __DIR__)
      |> File.read!()
      |> Jason.decode!()
      |> Map.fetch!("claims")
      |> Enum.map(& &1["slug"])

    assert length(editorial) == length(Enum.uniq(editorial))
    assert Enum.sort(editorial) == registered
    assert registered == Education.editorial_slugs()
    assert registered == Enum.map(explanations, & &1["slug"]) |> Enum.sort()
    assert length(explanations) == length(Enum.uniq(registered))
    assert Enum.all?(explanations, &(&1["title"] != "" and &1["family"] != "Unmapped"))

    assert Enum.sum(
             Enum.map(Education.families(), fn f ->
               Enum.count(explanations, &(&1["family"] == f.id))
             end)
           ) == length(registered)

    assert Education.inventory(explanations).unmapped == []

    assert Education.inventory(explanations).elixir + Education.inventory(explanations).lean ==
             length(registered)

    native = Enum.filter(explanations, &(&1["kind"] == "native_lean"))
    assert length(native) == 14
    assert Enum.all?(native, &String.ends_with?(&1["education_source_path"], ".lean"))
    assert Enum.count(explanations, &(&1["kind"] == "elixir_law")) == 35
  end

  test "dashboard and educational destinations render without opening an experiment", %{
    conn: conn
  } do
    for path <-
          ~w(/ /start /system /guarantees /atlas /proofs /assurance /repository /glossary /atlas/po_a2 /atlas/po_composite_recovery) do
      assert {:ok, view, html} = live(conn, path)
      assert html =~ "HOLD LEDGER"
      assert has_element?(view, "a[href='/assurance']")
    end
  end

  test "general pages and missing claims do not invent a selected claim", %{conn: conn} do
    for path <- ~w(/ /start /system /proofs /assurance /repository /glossary /atlas /atlas/missing) do
      {:ok, view, _} = live(conn, path)
      refute has_element?(view, "#claim-navigation")
    end

    {:ok, profile, _} = live(conn, "/atlas/po_a2")
    assert has_element?(profile, "#claim-navigation a[href='/atlas/po_a2'][aria-current='page']")
    assert has_element?(profile, "#claim-navigation a[href='/claims/po_a2']")
    assert has_element?(profile, "#claim-navigation a[href='/lens/po_a2']")

    {:ok, other, _} = live(conn, "/atlas/po_composite_recovery")
    assert has_element?(other, "#claim-navigation a[href='/claims/po_composite_recovery']")
    refute has_element?(other, "#claim-navigation a[href^='/lens/']")
  end

  test "example readings retain source order and the existing correct-control fixture" do
    assert Enum.map(Education.examples(), & &1["id"]) ==
             ~w(M1 M2 M3 M4 M5 M6 M7 M8 M9 M10 P01 P02 P03 P04 P05 P06 P07 P08)

    assert Enum.map(Education.examples(~w(P08 M4 P04)), & &1["id"]) == ~w(M4 P04 P08)

    [example] = Education.examples(["P08"])
    assert example["correct_control"]
    fixture = Jason.decode!(example["fixture_json"])
    assert get_in(fixture, ["before", "entries", Access.at(0), "status"]) == "reserved"
    assert fixture["output"]["result"] == "voided"
    assert fixture["output"]["effects"] == []
  end

  test "related examples expose their meaning and input without circular directory links", %{
    conn: conn
  } do
    {:ok, profile, _} = live(conn, "/atlas/po_a2")
    assert has_element?(profile, "#example-m4 h3", "M4")
    assert has_element?(profile, "#example-m5")
    assert has_element?(profile, "#example-p04", "Proposed output · not run")
    assert has_element?(profile, "#example-m4", "Expected from the source")
    assert has_element?(profile, "#example-m4 details summary", "Input and source details")
    assert has_element?(profile, "#example-m4 code", "{:request, 11, 100}")
    assert has_element?(profile, "#example-p04 pre", "insufficient_amount")
    assert has_element?(profile, "#example-p04 code", "apps/review_web/priv/scenarios/P04.json")
    refute has_element?(profile, "a[href='/repository#mutation-examples']")
    refute has_element?(profile, "a[href='/repository#review-exercises']")

    {:ok, repository, _} = live(conn, "/repository")
    assert length(repository |> render() |> LazyHTML.from_fragment() |> LazyHTML.query(".edu-example-card")) == 18
    assert has_element?(repository, "#example-p08", "Correct local cancellation")
    assert has_element?(repository, "#example-p08 pre", "reserved")
    assert has_element?(repository, "a[href='#mutation-example-directory']")
    assert has_element?(repository, "a[href='#policy-exercise-directory']")
  end

  test "editorial draft status stays separate from catalog registration", %{conn: conn} do
    for slug <- ~w(po_a2 po_composite_recovery) do
      {:ok, profile, _} = live(conn, "/atlas/" <> slug)
      assert has_element?(profile, "#edu-claim-profile", "Registered claim")
      assert has_element?(profile, "#edu-claim-editorial", "Editorial draft")
      assert has_element?(profile, "#edu-claim-editorial", "Owner review of this explanation is not recorded here.")
    end
  end

  test "background reading and optional self-checks appear where the ideas are used", %{
    conn: conn
  } do
    for {path, id, host} <- [
          {"/start", "edu-hold-primer", "https://docs.stripe.com/payments/place-a-hold-on-a-payment-method"},
          {"/system", "edu-retry-primer", "https://docs.stripe.com/api/idempotent_requests"},
          {"/proofs", "edu-statement-primer", "https://lean-lang.org/theorem_proving_in_lean4/Propositions-and-Proofs/"},
          {"/proofs", "edu-domain-primer", "https://lean-lang.org/theorem_proving_in_lean4/Quantifiers-and-Equality/"},
          {"/assurance", "edu-kernel-primer", "https://lean-lang.org/doc/reference/latest/ValidatingProofs/"}
        ] do
      {:ok, view, _} = live(conn, path)
      assert has_element?(view, "##{id} a[href='#{host}']")
      assert has_element?(view, "##{id} details.edu-self-check summary")
    end

    {:ok, overview, _} = live(conn, "/")
    assert has_element?(overview, "#edu-overview-lesson", "A ledger can refuse every request")

    {:ok, glossary, html} = live(conn, "/glossary")
    assert has_element?(glossary, "#edu-reading-directory")
    [before_results, _] = String.split(html, "id=\"edu-glossary-results\"", parts: 2)
    assert before_results =~ "id=\"edu-reading-directory\""
  end

  test "the introductory story changes on selection, always labels the example", %{conn: conn} do
    {:ok, view, _} = live(conn, "/start")
    assert has_element?(view, "#edu-story", "Example walkthrough")
    render_click(view, "scenario", %{"step" => "3"})
    assert has_element?(view, "#edu-story", "The reply never arrives")
    render_click(view, "scenario", %{"step" => "4"})
    assert has_element?(view, "#edu-story", "The second request is refused")
    assert has_element?(view, "button[phx-value-step='4'][aria-pressed='true']")
  end

  test "architecture and guarantee selections expose the correct bound", %{conn: conn} do
    {:ok, system, _} = live(conn, "/system")
    render_click(system, "status", %{"id" => "voiding"})
    assert has_element?(system, "#edu-status-detail", "keeps its amount and slot")
    render_click(system, "status", %{"id" => "voided"})
    assert has_element?(system, "#edu-status-detail", "before dispatch")
    assert has_element?(system, "#edu-status-detail", "confirmed")
    render_click(system, "component", %{"id" => "spec"})
    assert has_element?(system, "#edu-component-detail", "Spec")

    {:ok, policy, _} = live(conn, "/guarantees")
    render_click(policy, "guarantee", %{"id" => "identity"})
    assert has_element?(policy, ".edu-guarantee-card", "same key")
  end

  test "atlas searches across the authoritative catalog and distinguishes native Lean", %{
    conn: conn
  } do
    {:ok, view, _} = live(conn, "/atlas")
    assert has_element?(view, "#edu-atlas-results .edu-claim-row")

    form(view, "#edu-atlas-filters", %{
      "q" => "",
      "family" => "Composite & recovery",
      "kind" => "native_lean",
      "priority" => "all"
    })
    |> render_change()

    assert has_element?(view, "[data-claim-slug='po_composite_recovery']")
    refute has_element?(view, "[data-claim-slug='po_a2']")

    {:ok, detail, _} = live(conn, "/atlas/po_composite_recovery")
    assert has_element?(detail, "#edu-claim-profile", "Lean-only")
    assert has_element?(detail, "#edu-claim-source a[href='/claims/po_composite_recovery']")
  end

  test "atlas search finds source-grounded scenarios and wrong behavior", %{conn: conn} do
    {:ok, claim} = Education.find_claim("po_a2")
    {:ok, view, _} = live(conn, "/atlas")

    for field <- ~w(scenario wrong_behavior) do
      query = String.slice(claim[field], 0, 90)

      form(view, "#edu-atlas-filters", %{
        "q" => query,
        "family" => "all",
        "kind" => "all",
        "priority" => "all"
      })
      |> render_change()

      assert has_element?(view, "[data-claim-slug='po_a2']")
    end
  end

  test "a claim profile keeps scope and provenance in its copyable summary", %{conn: conn} do
    {:ok, claim} = Education.find_claim("po_a2")
    {:ok, view, html} = live(conn, "/atlas/po_a2")

    assert has_element?(view, "#edu-claim-scenario", claim["scenario"])
    assert has_element?(view, "#edu-claim-scope", claim["does_not_cover"])
    assert has_element?(view, "#edu-claim-source a[href='/claims/po_a2']")
    assert has_element?(view, "a[href='/lens/po_a2']")

    [summary] =
      html
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("#edu-copy-claim")
      |> LazyHTML.attribute("data-copy-text")

    assert summary =~ claim["does_not_cover"]
    assert summary =~ claim["education_source_path"]
    assert Enum.all?(claim["provenance"], &(summary =~ &1["path"]))
  end

  test "glossary definitions include limits and are filterable", %{conn: conn} do
    {:ok, view, _} = live(conn, "/glossary?q=requires")
    assert has_element?(view, "#term-requires")
    refute has_element?(view, "#term-omega")
    form(view, "#edu-glossary-filter", %{"q" => "processor"}) |> render_change()
    assert has_element?(view, "#term-processor")
  end

  test "glossary keeps source identifiers searchable when a display term changes", %{conn: conn} do
    {:ok, view, _} = live(conn, "/glossary?q=pointwise")
    assert has_element?(view, "#term-pointwise")
    assert has_element?(view, "#term-pointwise [data-source-path]")
  end

  test "glossary searches authored aliases and handles empty results", %{conn: conn} do
    {:ok, view, _} = live(conn, "/glossary?q=semantic%20gap")
    assert has_element?(view, "#term-policy-gap")
    refute has_element?(view, "#term-pointwise")
    form(view, "#edu-glossary-filter", %{"q" => "no-such-glossary-entry"}) |> render_change()
    refute has_element?(view, "#edu-glossary-results details")
    assert has_element?(view, ".edu-empty h2", "No matching terms.")
  end
end
