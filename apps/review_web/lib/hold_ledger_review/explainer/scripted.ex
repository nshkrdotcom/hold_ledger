defmodule HoldLedgerReview.Explainer.Scripted do
  @moduledoc "Supplies the offline explanations for the three supported cases."
  def response(p, context) do
    prefix = p.case.id <> "."

    observation =
      case p.case.id do
        "void_pending" ->
          "A released state without effects passes validity and effects for this input, but fails exposed-entry retention. These are concrete evaluations, not universal proofs."

        "timeout_unknown" ->
          "A timeout leaves this sent hold unknown and keeps its counters. po_b1_timeout establishes validity preservation; it does not by itself establish universal retention."

        "exact_fit" ->
          "Rejecting every request can preserve validity. The eligible-admission claim also requires this exact-fit request to succeed."
      end

    %{
      "items" => [
        %{"text" => observation, "source_ids" => [prefix <> "code", prefix <> "spec.valid"]},
        %{
          "text" =>
            "Inspect the selected " <>
              context.candidate <>
              " output and compare each conclusion with the original law. Which unacceptable result still passes?",
          "source_ids" => [prefix <> "law." <> elem(hd(p.case.laws), 0)]
        },
        %{
          "text" =>
            "This packet does not establish journal durability or processor honesty. A missing checker report is not proof acceptance. A human judgment must state its own scope.",
          "source_ids" => [prefix <> "policy"]
        }
      ]
    }
  end
end
