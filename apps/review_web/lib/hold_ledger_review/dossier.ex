defmodule HoldLedgerReview.Dossier do
  @moduledoc """
  Stable, human-owned questions anchored in the current graph and selected
  policy case. Question identities do not depend on AI or probe outcomes.
  """
  alias HoldLedgerReview.Adversarial

  @choices %{
    "reading" => ~w(accurate inaccurate unsure deferred),
    "escape" => ~w(acceptable unacceptable unsure deferred),
    "silence" => ~w(should_cover intentionally_excluded unsure deferred),
    "assumption" => ~w(supported disputed unknown deferred),
    "trace" => ~w(sufficient_for_review gap_suspected unsure deferred)
  }
  def choices(kind), do: Map.get(@choices, kind, [])

  def for_seed(seed_id, graph) do
    {:ok, witness} = Adversarial.seed(seed_id)
    event = witness["event"]["type"]
    state = witness["before"]["entries"]
    status = Enum.find_value(state, fn e ->
      if e["key"] == witness["event"]["key"], do: e["status"]
    end)
    row = Enum.find(graph["nodes"], fn node ->
      node["id"] == policy_id(event, status)
    end)
    target = row["id"]
    # Source-linked law context is discovered from graph edges, not from an
    # answer-key list of expected catchers. It is review evidence, not proof.
    law_sources = graph["edges"]
      |> Enum.filter(&(&1["from_id"] == target and &1["kind"] == "candidate_relevance"))
      |> Enum.take(6)
      |> Enum.flat_map(fn edge ->
        case Enum.find(graph["nodes"], &(&1["id"] == edge["to_id"])) do
          nil -> []
          node -> node["source_ids"]
        end
      end)
    source = Enum.uniq(row["source_ids"] ++ law_sources) |> Enum.take(10)
    trace = if(event == "request", do: "admission / counters / effects", else: "retention / identity / effects")
    [
      card(seed_id, "reading", target,
        "Does this policy row and the exact law source express the intended #{event} rule?", source, true, false, ""),
      card(seed_id, "escape", target,
        "Would the displayed hypothetical #{event} outcome be acceptable for this before-state?", source, true, true,
        "Changes to capacity, identity, admission or required effect must be judged explicitly"),
      card(seed_id, "trace", target,
        "Is the examined evidence about #{trace} sufficient for this named policy row?", source, true, false, ""),
      card(seed_id, "silence", target,
        "Should the requirement cover inputs outside the displayed law's proven pointwise domain?", source, false, false, ""),
      card(seed_id, "assumption", target,
        "Is the external terminal confirmation / journal / processor premise justified for deployment?", source, false, false, "")
    ]
  end

  defp policy_id("void", "authorized"), do: "policy.events.14"
  defp policy_id("void", "reserved"), do: "policy.events.13"
  defp policy_id("timeout", _), do: "policy.events.07"
  defp policy_id("request", _), do: "policy.events.01"
  defp policy_id(_, _), do: "policy.events.01"

  defp card(seed, kind, target, question, sources, mandatory, critical, reason) do
    %{"id" => "core.#{String.downcase(seed)}.#{kind}", "kind" => kind,
      "target_node_id" => target, "question" => question, "source_ids" => sources,
      "mandatory" => mandatory, "critical" => critical, "critical_reason" => reason,
      "origin" => "deterministic", "ai_proposal_id" => nil}
  end

  @doc "Deterministic *interpretation of a recorded judgment*, not an AI or proof verdict."
  def implication(card, choice, evidence \\ nil) do
    if choice not in choices(card["kind"]) do
      {:error, :invalid_choice}
    else
      text = case {card["kind"], choice} do
        {_, "deferred"} -> "Explicitly deferred; keep an open finding in the exported scope."
        {"reading", "accurate"} -> "Human agrees with this reading only; policy sufficiency is not approved."
        {"reading", "inaccurate"} -> "Source reading disputed; attach a correction, not a behavioral approval."
        {"reading", _} -> "Reading unresolved; inspect original AST and competing examples."
        {"escape", "unacceptable"} -> escape_rejection(evidence)
        {"escape", "acceptable"} -> escape_acceptance(evidence)
        {"escape", _} -> "Behavior judgment unresolved; examine source and additional probes."
        {"silence", "should_cover"} -> "Candidate additional domain requirement; source silence is not a failed proof."
        {"silence", "intentionally_excluded"} -> "Human explicitly identifies an intentional scope exclusion."
        {"silence", _} -> "Ask the policy owner whether this region is intended to be covered."
        {"assumption", "supported"} -> "User-cited deployment evidence supports this premise; no automatic attestation."
        {"assumption", "disputed"} -> "Deployment dependency disputed; cannot count as verified externally."
        {"assumption", _} -> "External premise needs independently sourced evidence and an owner."
        {"trace", "sufficient_for_review"} -> "Human reviewed named tested dimensions only, not whole-policy completeness."
        {"trace", "gap_suspected"} -> "Open a source-linked requirement/pin investigation; no automatic defect claim."
        {"trace", _} -> "List unexamined policy dimensions and law/Lean catalog remainder."
      end
      {:ok, text}
    end
  end

  defp escape_rejection(nil), do: "Unacceptable hypothesis; pointwise catcher set not evaluated."
  defp escape_rejection(e) do
    caught = Enum.filter(e["law_rows"] || [], &(&1["label"] == "catches")) |> Enum.map(& &1["slug"])
    if caught == [] do
      "Candidate gap among examined supported pointwise checks; unexamined laws remain unknown."
    else
      "Named tested claim(s) #{Enum.join(caught, ", ")} exclude this candidate here; not a universal policy verdict."
    end
  end
  defp escape_acceptance(nil), do: "Human accepts a hypothetical; no claim implication established yet."
  defp escape_acceptance(e) do
    if Enum.any?(e["law_rows"] || [], &(&1["label"] == "catches")) do
      "Possible maintained-claim/policy mismatch: a named pointwise claim catches an accepted hypothetical."
    else
      "Human accepts this local behavior; no general law/policy sufficiency is established."
    end
  end
end
