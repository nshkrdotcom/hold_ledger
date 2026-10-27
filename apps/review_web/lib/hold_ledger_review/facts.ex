defmodule HoldLedgerReview.Facts do
  alias HoldLedger.{Ledger, Spec}

  def build(c) do
    actual = Ledger.step(c.before, c.event)
    oracle = Spec.expected_step(c.before, c.event)
    candidates = [{"correct", actual} | c.candidates]

    %{
      actual: actual,
      oracle: oracle,
      disputed?: actual != oracle or actual != c.expected,
      candidates: Map.new(candidates),
      matrix: Map.new(candidates, fn {id, output} -> {id, predicates(c, output)} end),
      domains: Map.new(c.laws, fn {slug, _, _} -> {slug, domain?(slug, c.before, c.event)} end)
    }
  end

  def predicates(c, {next, result, effects} = output) do
    Map.new(c.claims, fn
      "valid" -> {"valid", Spec.valid?(next)}
      "effects" -> {"effects", Spec.effects_valid?(c.before, c.event, next, result, effects)}
      "retention" -> {"retention", Spec.exposed_entry?(next, 1, 100)}
      "admission" -> {"admission", output == c.expected}
    end)
  end

  def domain?("po_a2", s, {:request, k, a}), do: Spec.request_eligible?(s, k, a)

  def domain?("po_exposure_retain", s, event) do
    Spec.valid?(s) and Spec.lookup(elem(s, 4), 1) === {:ok, {1, 100, :authorized}} and
      not Spec.release_evidence?(event, 1)
  end

  def domain?(_, s, _), do: Spec.valid?(s)

  def follow({state, _, _}, event) do
    if Spec.valid?(state), do: {:ok, Ledger.step(state, event)}, else: {:error, :invalid_state}
  end
end
