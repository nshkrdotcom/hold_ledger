defmodule HoldLedgerReview.Cases do
  @moduledoc "Closed, policy-backed teaching scenarios; never executable user input."
  def all, do: Enum.map(["void_pending", "timeout_unknown", "exact_fit"], &fetch!/1)

  def fetch(id) do
    if id in ["void_pending", "timeout_unknown", "exact_fit"],
      do: {:ok, fetch!(id)},
      else: {:error, :unknown_case}
  end

  def fetch!("void_pending") do
    before = {100, 2, 100, 1, [{1, 100, :authorized}]}
    pending = {100, 2, 100, 1, [{1, 100, :voiding}]}
    released = {100, 2, 0, 0, [{1, 100, :voided}]}

    %{
      id: "void_pending",
      title: "Pending void",
      question: "When may this authorization stop consuming capacity?",
      before: before,
      event: {:void, 1},
      follow: {:request, 2, 100},
      expected: {pending, :voiding, [{:void, 1}]},
      candidates: [
        {"early_release", {released, :voided, [{:void, 1}]}},
        {"lost_effect", {pending, :voiding, []}},
        {"early_release_no_effect", {released, :voided, []}}
      ],
      laws: [
        {"po_b1_void", "Lifecycle", 2},
        {"po_b3", "Effects", 2},
        {"po_exposure_retain", "Retention", 5}
      ],
      operation: "void",
      claims: ["valid", "effects", "retention"]
    }
  end

  def fetch!("timeout_unknown") do
    unknown = {100, 2, 100, 1, [{1, 100, :unknown}]}

    %{
      id: "timeout_unknown",
      title: "Lost reply / timeout",
      question: "Does a missing reply establish that the processor declined?",
      before: {100, 2, 100, 1, [{1, 100, :sent}]},
      event: {:timeout, 1},
      follow: {:request, 2, 100},
      expected: {unknown, :marked_unknown, []},
      candidates: [
        {"release_on_timeout", {{100, 2, 0, 0, [{1, 100, :voided}]}, :marked_unknown, []}},
        {"invent_decline", {{100, 2, 0, 0, [{1, 100, :declined}]}, :declined, []}}
      ],
      laws: [{"po_b1_timeout", "Lifecycle", 2}],
      operation: "timeout",
      claims: ["valid", "retention"]
    }
  end

  def fetch!("exact_fit") do
    before = {100, 1, 0, 0, []}

    %{
      id: "exact_fit",
      title: "Exact-fit admission",
      question: "What must succeed when a fresh request exactly fits?",
      before: before,
      event: {:request, 11, 100},
      follow: {:dispatch, 11},
      expected: {{100, 1, 100, 1, [{11, 100, :reserved}]}, :admitted, []},
      candidates: [
        {"reject_equality", {before, :insufficient_amount, []}},
        {"always_reject", {before, :insufficient_holds, []}}
      ],
      laws: [{"po_a2", "Request", 3}],
      operation: "request",
      claims: ["valid", "admission"]
    }
  end
end
