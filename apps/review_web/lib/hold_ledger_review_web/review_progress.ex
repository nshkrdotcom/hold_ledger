defmodule HoldLedgerReviewWeb.ReviewProgress do
  @moduledoc "Presentation-only progress over the latest human answers."

  def latest(review, card_id),
    do: Enum.find(Enum.reverse(review["answers"]), &(&1["card_id"] == card_id))

  def counts(review) do
    required =
      Enum.filter(
        review["core_cards"] ++ review["accepted_ai_cards"],
        &(&1["mandatory"] || &1["critical"])
      )

    answers = Enum.map(required, &latest(review, &1["id"]))

    %{
      total: length(required),
      answered: Enum.count(answers, &(&1 != nil)),
      deferred: Enum.count(answers, &(&1 != nil && &1["choice"] == "deferred"))
    }
  end

  def step(review, revealed) do
    progress = counts(review)

    cond do
      review["review_conclusion"] != nil -> 5
      progress.answered == progress.total -> 5
      progress.answered > 0 -> 4
      revealed -> 3
      true -> 2
    end
  end
end
