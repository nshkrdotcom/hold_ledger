defmodule HoldLedgerReviewWeb.EducationLiveTest do
  use HoldLedgerReviewWeb.ConnCase, async: false
  import Phoenix.LiveViewTest
  alias HoldLedgerReviewWeb.Education
  alias HoldLedgerReview.Claims

  test "editorial inventory covers every registered group exactly once" do
    {:ok, current} = Claims.catalog()
    {:ok, explanations} = Education.claims()
    registered = Enum.map(current, & &1["slug"]) |> Enum.sort()

    assert registered == Education.editorial_slugs()
    assert registered == (Enum.map(explanations, & &1["slug"]) |> Enum.sort())
    assert length(explanations) == length(Enum.uniq(registered))
    assert Enum.all?(explanations, &(&1["title"] != "" and &1["family"] != "Unmapped"))
    assert Enum.sum(Enum.map(Education.families(), fn f ->
             Enum.count(explanations, &(&1["family"] == f.id))
           end)) == length(registered)
    assert Education.inventory(explanations).unmapped == []
    assert Education.inventory(explanations).elixir + Education.inventory(explanations).lean == length(registered)
    assert Enum.count(explanations, &(&1["kind"] == "native_lean")) == 14
    assert Enum.count(explanations, &(&1["kind"] == "elixir_law")) == 35
  end

  test "dashboard and educational destinations render without opening an experiment", %{conn: conn} do
    for path <- ~w(/ /start /system /guarantees /atlas /proofs /assurance /repository /glossary /atlas/po_a2 /atlas/po_composite_recovery) do
      assert {:ok, _view, html} = live(conn, path)
      assert html =~ "HOLD LEDGER"
      assert html =~ "Evidence boundaries"
    end
  end

  test "the introductory story changes on selection, always labels the example", %{conn: conn} do
    {:ok, view, _} = live(conn, "/start")
    assert has_element?(view, "#edu-story", "ILLUSTRATIVE HOLD WALKTHROUGH")
    render_click(view, "scenario", %{"step" => "3"})
    assert has_element?(view, "#edu-story", "The reply never arrives")
    render_click(view, "scenario", %{"step" => "4"})
    assert has_element?(view, "#edu-story", "Another 100¢ cannot fit")
  end

  test "architecture and guarantee selections expose the correct bound", %{conn: conn} do
    {:ok, system, _} = live(conn, "/system")
    render_click(system, "status", %{"id" => "voiding"})
    assert has_element?(system, "#edu-status-detail", "not terminal evidence")
    render_click(system, "component", %{"id" => "spec"})
    assert has_element?(system, "#edu-component-detail", "independent")

    {:ok, policy, _} = live(conn, "/guarantees")
    render_click(policy, "guarantee", %{"id" => "identity"})
    assert has_element?(policy, ".edu-guarantee-card", "Repeated keys")
  end

  test "atlas searches across the authoritative catalog and distinguishes native Lean", %{conn: conn} do
    {:ok, view, _} = live(conn, "/atlas")
    assert has_element?(view, "#edu-atlas-results .edu-claim-row")

    form(view, "#edu-atlas-filters", %{
      "q" => "",
      "family" => "Composite & recovery",
      "kind" => "native_lean",
      "priority" => "all"
    })
    |> render_change()

    assert has_element?(view, "#edu-atlas-results", "Replay committed work")
    refute has_element?(view, "#edu-atlas-results", "Keep requests inside the state rules")

    {:ok, detail, _} = live(conn, "/atlas/po_composite_recovery")
    assert has_element?(detail, "#edu-claim-profile", "Replay committed work")
    assert has_element?(detail, ".edu-profile-panel", "Native Lean")
    assert has_element?(detail, ".edu-profile-bridge", "Registration is not formal acceptance")
  end

  test "glossary definitions include limits and are filterable", %{conn: conn} do
    {:ok, view, _} = live(conn, "/glossary?q=requires")
    assert has_element?(view, "#term-requires", "precondition")
    refute has_element?(view, "#term-omega")
    form(view, "#edu-glossary-filter", %{"q" => "processor"}) |> render_change()
    assert has_element?(view, "#term-processor", "external")
  end
end
