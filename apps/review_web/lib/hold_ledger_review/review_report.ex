defmodule HoldLedgerReview.ReviewReport do
  @moduledoc "Readable scoped exports. A human judgment is not checker or deployment acceptance."
  alias HoldLedgerReview.{Canonical, Dossier}

  def json(review), do: Canonical.json(review) <> "\n"

  def markdown(review) do
    source = review["source"]
    nodes = review["graph_snapshot"]["nodes"]
    laws = Enum.filter(nodes, &(&1["kind"] == "law"))
    native = Enum.filter(nodes, &(&1["kind"] == "lean"))

    tested =
      review["pinned_probes"]
      |> Enum.flat_map(& &1["evaluation"]["law_rows"])
      |> Enum.map(& &1["slug"])
      |> Enum.uniq()

    remainder = Enum.reject(laws, &(String.replace_prefix(&1["id"], "law.", "") in tested))
    latest = Map.new(review["answers"], &{&1["card_id"], &1})
    cards = review["core_cards"] ++ review["accepted_ai_cards"]
    conclusion = review["review_conclusion"]

    [
      "# Hold Ledger — pointwise human review\n\n",
      "Review ID: `#{review["id"]}` · status: **#{review["status"]}** · document revision #{review["document_revision"]} · human revision #{review["human_revision"]}\n\n",
      "This is a named, incomplete-by-default investigation. It is **not** a proof certificate, external-processor attestation, deployment approval, or a universal specification-completeness claim.\n\n",
      "## Source and independent proof evidence\n\n",
      "- Compiled claim source digest: `#{source["compiled_source_digest"]}`\n",
      "- Evaluator loaded-generation ID: `#{source["evaluator_id"]}`\n",
      "- Packet digest: `#{source["packet_digest"]}`\n",
      "- Independent checker status: **#{source["proof_report_snapshot"]["status"]}** — #{source["proof_report_snapshot"]["detail"]}\n",
      "- Formal claims and policy adequacy are separate; no report supplied means no formal checker evidence supplied.\n\n",
      "## Design map and inspected scope\n\n",
      "Target policy nodes: #{Enum.map_join(review["target_policy_nodes"], ", ", &"`#{&1}`")}\n\n",
      "Map: #{length(nodes)} nodes, #{length(review["graph_snapshot"]["edges"])} typed edges (parsed/source-explicit, inferred, or human-confirmed). #{length(laws)} DSL laws, #{length(native)} native Lean-only obligations.\n\n",
      "Source links are relative checkout paths with full source-file SHA-256. Inferred edges are **navigation suggestions, not entailments**.\n\n",
      Enum.map(review["graph_snapshot"]["excerpts"], fn s ->
        "- `#{s["id"]}`: `#{s["path"]}` (`#{s["sha256"]}`)\n"
      end),
      "\n## Questions and human answer history\n\n",
      Enum.map(cards, fn card ->
        answer = latest[card["id"]]

        "### #{card["id"]}: #{card["question"]}\n\n" <>
          "Kind: #{card["kind"]}; mandatory: #{card["mandatory"]}; critical: #{card["critical"]} (#{card["critical_reason"]}); sources: #{Enum.join(card["source_ids"], ", ")}\n\n" <>
          if(answer,
            do:
              "Latest human choice: **#{answer["choice"]}**. #{implication(card, answer, review)}\n\n",
            else: "Not answered.\n\n"
          )
      end),
      "### Supersession chronology\n\n",
      Enum.map(review["answers"], fn a ->
        "- #{a["at_utc"]} human `#{a["answer_id"]}` / card `#{a["card_id"]}`: **#{a["choice"]}**, reason: #{a["reason"]}, probe: #{inspect(a["probe_id"])}, supersedes: #{inspect(a["supersedes_answer_id"])}, revealed first: #{a["revealed_before_answer"]}\n"
      end),
      "\n## Pinned witnesses: actual / oracle / hypothetical / optional follow-on\n\n",
      Enum.map(review["pinned_probes"], &format_probe/1),
      "\n## Catalog remainder and scope limits\n\n",
      "Examined DSL law IDs: #{if(tested == [], do: "None", else: Enum.join(tested, ", "))}\n\n",
      "Unexamined DSL catalog (not a finding of missing proof): #{if(remainder == [], do: "None", else: Enum.map_join(remainder, ", ", &String.replace_prefix(&1["id"], "law.", "")))}\n\n",
      "Native Lean obligations: #{Enum.map_join(native, ", ", &String.replace_prefix(&1["id"], "law.", ""))}. **Not a pointwise DSL probe**; independent checker status above applies only within its recorded report scope.\n\n",
      "Unchecked dimensions may include transition, result, counters, effects, identity, continued remote exposure, journal/replay, external fencing and unknown policy intent. A missing examined catcher is a **candidate gap to investigate**, never a statement that no maintained law exists.\n\n",
      "## AI job and provenance record\n\n",
      if(review["ai_jobs"] == [],
        do: "AI disabled / no jobs in this review. No synthetic model response is asserted.\n\n",
        else:
          Enum.map(review["ai_jobs"], fn j ->
            "- #{j["job_id"]}: #{j["request_kind"]}, #{j["status"]}, based on human revision #{j["based_on_human_revision"]}; output is a proposal, not a formal fact.\n"
          end)
      ),
      "\n## Scoped conclusion\n\n",
      if(is_nil(conclusion),
        do: "**Unfinished review — no human conclusion confirmed.**\n\n",
        else:
          "Human-confirmed outcome: **#{conclusion["outcome"]}**. Scope: #{conclusion["scope"]}. Reason: #{conclusion["rationale"]}. Unresolved: #{Enum.join(conclusion["unresolved_ids"], ", ")}. Evidence: #{Enum.join(conclusion["evidence_ids"], ", ")}. Confirmed #{conclusion["confirmed_at_utc"]}.\n\n"
      ),
      "The human determines adequacy within the named scope. Pointwise probes do not establish every input, formal status, remote processor truthfulness, or deployment safety.\n"
    ]
    |> IO.iodata_to_binary()
  end

  defp implication(card, answer, review) do
    probe = Enum.find(review["pinned_probes"], &(&1["id"] == answer["probe_id"]))

    case Dossier.implication(
           card,
           answer["choice"],
           if(probe, do: probe["evaluation"], else: nil)
         ) do
      {:ok, text} -> text
      _ -> "Invalid answer vocabulary; manual investigation needed."
    end
  end

  defp format_probe(p) do
    e = p["evaluation"]

    [
      "### #{p["id"]} · #{p["origin"]}\n\n",
      "Fingerprint: `#{p["fingerprint"]}` · evaluated against `#{p["source_digest"]}` · scope `#{e["scope"]}`\n\n",
      "- Before/event: `#{Jason.encode!(p["witness"]["before"])}` / `#{Jason.encode!(p["witness"]["event"])}`\n",
      "- Actual: `#{Jason.encode!(e["actual"])}`\n",
      "- Independent oracle: `#{Jason.encode!(e["oracle"])}`\n",
      "- Hypothetical: `#{Jason.encode!(p["witness"]["output"])}`\n",
      "- Follow-on actual: `#{Jason.encode!(e["follow_on_actual"])}`\n",
      "- Follow-on hypothetical: `#{Jason.encode!(e["follow_on_candidate"])}`\n",
      "- Pointwise checks (only relevant supported DSL source AST):\n",
      Enum.map(e["law_rows"], fn law ->
        "  - `#{law["slug"]}`: **#{law["label"]}**, #{law["reason"]}; bindings #{law["bindings_tested"]}; exhaustive for source domain: #{law["exhaustive_for_source_domain"]}; law SHA `#{law["source_sha256"]}`\n"
      end),
      "\n"
    ]
  end
end
