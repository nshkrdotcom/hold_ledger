defmodule HoldLedgerReviewWeb.ReviewCopyTest do
  use ExUnit.Case, async: true
  alias HoldLedgerReviewWeb.ReviewCopy

  test "display titles follow the catalog without changing authored capitalization" do
    for slug <- ~w(po_a2 po_exposure_retain po_a4_duplicate po_b1_timeout po_s) do
      assert ReviewCopy.title(%{"slug" => slug, "title" => "Old display title"}) ==
               HoldLedgerReviewWeb.Education.title(slug)
    end

    assert ReviewCopy.title(%{"slug" => "outside_catalog", "title" => "Read the Lean API"}) ==
             "Read the Lean API"

    assert ReviewCopy.title(%{}) == "Ledger claim"
  end

  defp binding(requires, actual) do
    %{
      "requires" => %{"value" => requires},
      "actual" => if(is_nil(actual), do: nil, else: %{"value" => actual})
    }
  end

  test "aggregate bindings cannot be narrowed by selecting a row" do
    case_data = %{
      "explanation" => %{
        "complete" => true,
        "bindings" => [binding(false, nil), binding(true, true), binding(true, false)]
      },
      "law_status" => "catches"
    }

    assert ReviewCopy.applicability(case_data) == "Applies (2 of 3 bindings)"
    assert ReviewCopy.code_acceptance(case_data) == "Rejects code result"
    assert ReviewCopy.candidate_acceptance(case_data) == "Rejects what-if output"
    assert ReviewCopy.accounting(true) == "Account is valid"
  end

  test "absence, false coverage, evaluation errors and acceptance are distinct" do
    assert ReviewCopy.applicability(%{"explanation" => %{"complete" => true, "bindings" => []}}) ==
             "Not checked"

    out = %{"explanation" => %{"complete" => true, "bindings" => [binding(false, nil)]}}
    assert ReviewCopy.applicability(out) == "Claim says nothing about this input"
    assert ReviewCopy.code_acceptance(out) == "Outside this claim's input"

    assert ReviewCopy.applicability(%{
             "explanation" => %{"complete" => true, "bindings" => [%{"error" => "unavailable"}]}
           }) ==
             "Could not evaluate all bindings"

    uncertain = %{
      "explanation" => %{
        "complete" => true,
        "bindings" => [binding(true, true), binding(nil, nil)]
      }
    }

    assert ReviewCopy.applicability(uncertain) == "Could not evaluate"
    assert ReviewCopy.code_acceptance(uncertain) == "Unavailable"

    assert ReviewCopy.candidate_acceptance(%{"law_status" => "allows_here"}) ==
             "Accepts what-if output"

    assert ReviewCopy.candidate_acceptance(%{"law_status" => "cant_check"}) == "Unavailable"
    assert ReviewCopy.accounting(nil) == "Unavailable"
  end
end
