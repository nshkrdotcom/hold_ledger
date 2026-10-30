defmodule HoldLedgerReviewWeb.ScrubberComponentsTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest

  alias HoldLedgerReviewWeb.ScrubberComponents

  defp capacity(overrides) do
    ledger =
      Map.merge(
        %{
          "amount_limit" => 100,
          "hold_limit" => 2,
          "used_amount" => 100,
          "used_holds" => 1,
          "entries" => [
            %{"key" => 11, "amount" => 100, "status" => "unknown"}
          ]
        },
        overrides
      )

    render_component(&ScrubberComponents.capacity_view/1,
      id: "test-capacity",
      ledger: ledger,
      title: "Recorded account"
    )
    |> LazyHTML.from_fragment()
  end

  test "an uncertain hold keeps its displayed capacity and finished identities stay separate" do
    html =
      capacity(%{
        "entries" => [
          %{"key" => 11, "amount" => 100, "status" => "unknown"},
          %{"key" => 12, "amount" => 75, "status" => "voided"}
        ]
      })

    assert LazyHTML.text(LazyHTML.query(html, "#test-capacity-held")) == "100¢"
    assert LazyHTML.text(LazyHTML.query(html, "#test-capacity-available")) == "0¢"
    assert LazyHTML.text(LazyHTML.query(html, ".capacity-active-records")) =~ "Outcome unknown"
    assert LazyHTML.text(LazyHTML.query(html, ".capacity-finished-records")) =~ "Request 12"
    assert LazyHTML.text(LazyHTML.query(html, ".capacity-finished-records")) =~ "Cancelled"
    refute LazyHTML.text(LazyHTML.query(html, ".capacity-active-records")) =~ "Request 12"
  end

  test "large limits use a bounded decorative rack and preserve exact counts" do
    html = capacity(%{"hold_limit" => 1_000_000, "used_holds" => 999_999})
    assert Enum.count(LazyHTML.query(html, ".capacity-slot")) == 8
    assert LazyHTML.text(LazyHTML.query(html, "#test-capacity-slots-used")) == "999999"
    assert LazyHTML.text(LazyHTML.query(html, "#test-capacity-slots-free")) == "1"
    assert LazyHTML.text(html) =~ "1000000"
    assert LazyHTML.text(html) =~ "999992 more slots"
  end

  test "inconsistent recorded counters are not recomputed from the hold entries" do
    html = capacity(%{"used_amount" => 0, "used_holds" => 0})
    assert LazyHTML.text(LazyHTML.query(html, "#test-capacity-held")) == "0¢"
    assert LazyHTML.text(LazyHTML.query(html, "#test-capacity-available")) == "100¢"
    assert LazyHTML.text(LazyHTML.query(html, "#test-capacity-slots-used")) == "0"
    assert LazyHTML.text(LazyHTML.query(html, ".capacity-active-records")) =~ "100¢"
  end

  test "over-capacity and negative values remain readable instead of looking valid" do
    html = capacity(%{"used_amount" => 120, "used_holds" => -1})
    assert LazyHTML.text(LazyHTML.query(html, "#test-capacity-held")) == "120¢"
    assert LazyHTML.text(LazyHTML.query(html, "#test-capacity-available")) == "-20¢"
    assert LazyHTML.text(LazyHTML.query(html, "#test-capacity-slots-used")) == "-1"
    assert LazyHTML.text(html) =~ "Recorded amount is outside the limit"
    assert LazyHTML.text(html) =~ "Recorded slot count is outside the limit"
    assert Enum.count(LazyHTML.query(html, ".capacity-slot")) <= 8
  end

  test "zero capacity does not divide by zero or render an unbounded rack" do
    html = capacity(%{"amount_limit" => 0, "hold_limit" => 0})
    assert LazyHTML.text(LazyHTML.query(html, "#test-capacity-available")) == "-100¢"
    assert Enum.empty?(LazyHTML.query(html, ".capacity-slot"))
    assert LazyHTML.text(html) =~ "No hold slots configured"
  end
end
