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
