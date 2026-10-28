defmodule HoldLedgerReviewWeb.EducationComponentsTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest
  alias HoldLedgerReviewWeb.EducationComponents

  test "the first-visit primer is open, with all eight lessons and five self-checks" do
    document =
      render_component(&EducationComponents.primer/1, reviews: []) |> LazyHTML.from_fragment()

    assert document |> LazyHTML.filter("#review-primer[open]") |> Enum.count() == 1

    assert document |> LazyHTML.query(".primer-body > section") |> Enum.count() ==
             10

    assert document |> LazyHTML.query("#primer-self-check > details") |> Enum.count() == 5
    assert document |> LazyHTML.filter("a[href='#new-review-choices']") |> Enum.count() == 1
  end

  test "returning reviewers can reopen the same primer" do
    document =
      render_component(&EducationComponents.primer/1, reviews: [%{}]) |> LazyHTML.from_fragment()

    assert document |> LazyHTML.filter("#review-primer:not([open])") |> Enum.count() == 1
  end
end
