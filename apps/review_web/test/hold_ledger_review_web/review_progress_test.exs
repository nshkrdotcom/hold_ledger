defmodule HoldLedgerReviewWeb.ReviewProgressTest do
  use ExUnit.Case, async: true
  alias HoldLedgerReviewWeb.ReviewProgress

  test "only the latest answer counts, and deferrals remain open" do
    review = %{
      "core_cards" => [
        %{"id" => "one", "mandatory" => true, "critical" => true},
        %{"id" => "two", "mandatory" => false, "critical" => false}
      ],
      "accepted_ai_cards" => [],
      "answers" => [],
      "review_conclusion" => nil
    }

    assert ReviewProgress.counts(review) == %{total: 1, answered: 0, deferred: 0}
    deferred = %{review | "answers" => [%{"card_id" => "one", "choice" => "deferred"}]}
    assert ReviewProgress.counts(deferred) == %{total: 1, answered: 1, deferred: 1}

    revised = %{
      deferred
      | "answers" => deferred["answers"] ++ [%{"card_id" => "one", "choice" => "acceptable"}]
    }

    assert ReviewProgress.counts(revised) == %{total: 1, answered: 1, deferred: 0}
  end
end
