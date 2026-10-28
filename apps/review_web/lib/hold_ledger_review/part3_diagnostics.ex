defmodule HoldLedgerReview.Part3Diagnostics do
  @moduledoc """
  Concrete distinctions from independently identified execution results only.
  Separate input exclusions, common-domain permitted outputs, and actual
  behavioral differences. A search with no result establishes nothing general.
  """
  alias HoldLedgerReview.Canonical

  def compare(package, witness, left, right) do
    base = %{
      "baseline_id" => package["baseline"]["snapshot_id"],
      "proposal_id" => package["proposal"]["snapshot_id"],
      "context_digest" => package["context_digest"],
      "level" => "concrete_computation",
      "method" => "two isolated source-derived pointwise evaluations",
      "bounds" => %{
        "scope" => "one valid starting state and event",
        "general_relation" => "not_established"
      },
      "input" => witness,
      "output" => nil,
      "baseline_result" => nil,
      "proposal_result" => nil,
      "source_ids" => [],
      "note" => ""
    }

    actual =
      if left["evaluation"]["actual"] != right["evaluation"]["actual"] do
        [
          evidence(base, "observed_behavioral_difference", "actual", %{
            "baseline_result" => left["evaluation"]["actual"],
            "proposal_result" => right["evaluation"]["actual"],
            "note" => "Actual outputs differ on the same supported input; no universal claim"
          })
        ]
      else
        []
      end

    claims =
      (Map.keys(left["claims"]) ++ Map.keys(right["claims"]))
      |> Enum.uniq()
      |> Enum.sort()
      |> Enum.flat_map(&claim_distinctions(&1, left, right, base, witness))

    Enum.uniq_by(actual ++ claims, & &1["id"])
  end

  defp claim_distinctions(slug, left, right, base, witness) do
    a = get_in(left, ["claims", slug, "bindings"]) || []
    b = get_in(right, ["claims", slug, "bindings"]) || []
    by_id = Map.new(b, &{&1["binding_id"], &1})

    Enum.flat_map(
      a,
      &binding_distinction(&1, Map.get(by_id, &1["binding_id"]), slug, base, witness)
    )
  end

  defp binding_distinction(_old, nil, _slug, _base, _witness), do: []

  defp binding_distinction(old, new, slug, base, witness) do
    provenance = %{
      "source_ids" => ["law." <> slug],
      "baseline_result" => Map.take(old, ~w(requires post_candidate post_actual)),
      "proposal_result" => Map.take(new, ~w(requires post_candidate post_actual))
    }

    case distinction(old, new) do
      nil ->
        []

      {kind, note} ->
        additions =
          Map.merge(provenance, %{
            "note" => note,
            "output" =>
              if(kind == "permitted_alternative_output", do: witness["output"], else: nil)
          })

        [evidence(base, kind, slug <> old["binding_id"], additions)]
    end
  end

  defp distinction(%{"requires" => true}, %{"requires" => false}),
    do: {"lost_domain_input", "Pre_A(x) and not Pre_B(x): this binding was excluded"}

  defp distinction(%{"requires" => true, "post_candidate" => false}, %{
         "requires" => true,
         "post_candidate" => true
       }),
       do:
         {"permitted_alternative_output",
          "Common input domain: Post_B(x,y) and not Post_A(x,y); not an observed implementation bug"}

  defp distinction(_, _), do: nil

  defp evidence(base, kind, key, additions) do
    body = Map.merge(base, Map.merge(%{"kind" => kind}, additions))

    Map.put(
      body,
      "id",
      "e-" <>
        String.slice(
          Canonical.digest(%{
            "kind" => kind,
            "key" => key,
            "context" => base["context_digest"],
            "input" => base["input"]
          }),
          0,
          32
        )
    )
  end

  def triage(package) do
    groups = %{
      "reading" =>
        "Compare changed statements, helper definitions, imports and inventories against policy",
      "alternative_behavior" =>
        "Examine changed outputs, frame and effect guarantees and wrong alternatives",
      "evidence_scope" => "Check history domain, obligation coverage and formal acceptance scope",
      "excluded_inputs" => "Inspect eligibility, exact fit, statuses and identity boundaries",
      "outside_assumptions" =>
        "Inspect external effects, toolchain, proof and trusted dependencies"
    }

    Enum.map(
      ~w(reading alternative_behavior evidence_scope excluded_inputs outside_assumptions),
      fn lens ->
        answers = Enum.filter(package["human_findings"], &(&1["lens"] == lens))
        last = List.last(answers)
        related = Enum.filter(package["source_changes"], &relevant?(lens, &1))

        %{
          "lens" => lens,
          "question" => groups[lens],
          "status" => if(last, do: last["status"], else: "unresolved"),
          "latest" => last,
          "changes" => related,
          "triage" =>
            if(related == [],
              do: "no_trigger_found_not_a_waiver",
              else: "inspect_relevant_changes"
            )
        }
      end
    )
  end

  defp relevant?("reading", _), do: true

  defp relevant?("alternative_behavior", change),
    do: change["kind"] in ~w(claim called_definition_or_behavior)

  defp relevant?("excluded_inputs", change),
    do: change["kind"] in ~w(claim called_definition_or_behavior governing_policy)

  defp relevant?("evidence_scope", change),
    do:
      change["kind"] in ~w(lean_declaration_or_dependency obligation_or_inventory translation_or_elaboration source_or_toolchain)

  defp relevant?("outside_assumptions", change),
    do:
      change["kind"] in ~w(translation_or_elaboration review_infrastructure source_or_toolchain called_definition_or_behavior)
end
