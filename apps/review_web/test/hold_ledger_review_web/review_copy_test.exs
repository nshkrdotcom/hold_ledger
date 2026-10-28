defmodule HoldLedgerReviewWeb.ReviewCopyTest do
  use ExUnit.Case, async: true
  alias HoldLedgerReviewWeb.ReviewCopy

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
    assert ReviewCopy.candidate_acceptance(case_data) == "Rejects alternative"
    assert ReviewCopy.accounting(true) == "Accounting balances"
  end

  test "absence, false coverage, evaluation errors and acceptance are distinct" do
    assert ReviewCopy.applicability(%{"explanation" => %{"complete" => true, "bindings" => []}}) ==
             "Not checked"

    out = %{"explanation" => %{"complete" => true, "bindings" => [binding(false, nil)]}}
    assert ReviewCopy.applicability(out) == "Does not apply"
    assert ReviewCopy.code_acceptance(out) == "Not applicable"
    assert ReviewCopy.applicability(%{"explanation" => %{"complete" => true, "bindings" => [%{"error" => "unavailable"}]}}) ==
             "Could not evaluate all bindings"
    uncertain = %{"explanation" => %{"complete" => true, "bindings" => [binding(true, true), binding(nil, nil)]}}
    assert ReviewCopy.applicability(uncertain) == "Could not evaluate"
    assert ReviewCopy.code_acceptance(uncertain) == "Unavailable"
    assert ReviewCopy.candidate_acceptance(%{"law_status" => "allows_here"}) ==
             "Accepts alternative"
    assert ReviewCopy.candidate_acceptance(%{"law_status" => "cant_check"}) == "Unavailable"
    assert ReviewCopy.accounting(nil) == "Unavailable"
  end
end
