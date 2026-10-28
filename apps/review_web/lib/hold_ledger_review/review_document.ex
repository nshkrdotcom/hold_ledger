defmodule HoldLedgerReview.ReviewDocument do
  @moduledoc "Validates the current stored document before any reader or writer uses nested fields."
  alias HoldLedgerReview.{Adversarial, Claims, Dossier, TermCodec}

  @fields ~w(id seed_id document_revision human_revision target_policy_nodes status source graph_snapshot core_cards accepted_ai_cards suggested_ai_cards pinned_probes answers human_commands ai_jobs review_conclusion created_at_utc updated_at_utc)

  def valid?(doc, id) when is_map(doc) do
    keys?(doc, @fields) and doc["id"] == id and metadata?(doc) and
      source?(doc["source"]) and graph?(doc["graph_snapshot"]) and collections?(doc) and
      conclusion?(doc["review_conclusion"]) and references?(doc)
  rescue
    _ -> false
  end

  def valid?(_, _), do: false

  defp metadata?(doc) do
    doc["seed_id"] in Adversarial.seeds() and nonnegative?(doc["human_revision"]) and
      positive?(doc["document_revision"]) and doc["human_revision"] < doc["document_revision"] and
      doc["status"] in ~w(in_progress review_concluded stale_read_only corrupt_read_only) and
      strings?(doc["target_policy_nodes"]) and text?(doc["created_at_utc"]) and
      text?(doc["updated_at_utc"])
  end

  defp source?(source) do
    keys?(
      source,
      ~w(packet_digest compiled_source_digest evaluator_id source_manifest prompt_digests proof_report_snapshot)
    ) and
      Enum.all?(~w(packet_digest compiled_source_digest evaluator_id), &text?(source[&1])) and
      digest_map?(source["source_manifest"]) and is_map(source["prompt_digests"]) and
      proof?(source["proof_report_snapshot"])
  end

  defp digest_map?(map) when is_map(map) and map_size(map) > 0,
    do: Enum.all?(map, fn {path, digest} -> text?(path) and text?(digest) end)

  defp digest_map?(_), do: false

  defp proof?(proof) do
    keys?(proof, ~w(status detail report_sha256)) and
      proof["status"] in ~w(not_supplied development_only selected_checked full_catalog_checked failed incomplete stale) and
      is_binary(proof["detail"]) and optional_text?(proof["report_sha256"])
  end

  defp graph?(graph) do
    {:ok, valid} =
      Claims.memoize(__MODULE__, {:graph_shape, graph}, fn ->
        {:ok, valid_graph?(graph)}
      end)

    valid
  end

  defp valid_graph?(graph) do
    keys?(graph, ~w(nodes edges excerpts)) and items?(graph["nodes"], 500, &node?/1) and
      items?(graph["edges"], 2000, &edge?/1) and items?(graph["excerpts"], 200, &excerpt?/1)
  end

  defp node?(n),
    do:
      keys?(n, ~w(id kind title source_ids)) and texts?(n, ~w(id kind title)) and
        n["kind"] in ~w(policy_row spec reducer law lean boundary) and
        strings?(n["source_ids"])

  defp edge?(e),
    do:
      keys?(e, ~w(from_id to_id kind provenance reason)) and
        texts?(e, ~w(from_id to_id kind provenance reason)) and
        e["provenance"] in ~w(source_explicit inferred human_confirmed)

  defp excerpt?(e), do: keys?(e, ~w(id path sha256 text)) and texts?(e, ~w(id path sha256 text))

  defp collections?(doc) do
    items?(doc["core_cards"], 100, &card?/1) and
      items?(doc["accepted_ai_cards"], 100, &card?/1) and
      items?(doc["suggested_ai_cards"], 100, &card?/1) and
      items?(doc["pinned_probes"], 100, &probe?/1) and
      items?(doc["answers"], 500, &answer?/1) and
      items?(doc["human_commands"], 500, &command?/1) and
      items?(doc["ai_jobs"], 100, &job?/1)
  end

  defp card?(c) do
    keys?(
      c,
      ~w(id kind target_node_id question source_ids mandatory critical critical_reason origin ai_proposal_id)
    ) and
      texts?(c, ~w(id kind target_node_id question)) and Dossier.choices(c["kind"]) != [] and
      strings?(c["source_ids"]) and is_boolean(c["mandatory"]) and is_boolean(c["critical"]) and
      is_binary(c["critical_reason"]) and c["origin"] in ~w(deterministic human ai_proposed) and
      optional_text?(c["ai_proposal_id"])
  end

  defp probe?(p) do
    keys?(p, ~w(id fingerprint origin witness evaluation source_digest)) and
      texts?(p, ~w(id fingerprint origin source_digest)) and
      match?({:ok, _}, Adversarial.decode(p["witness"])) and evaluation?(p["evaluation"])
  end

  defp evaluation?(e) do
    keys?(e, ~w(candidate_hash actual oracle law_rows follow_on_actual follow_on_candidate scope)) and
      text?(e["candidate_hash"]) and e["scope"] == "pointwise_pure_ledger" and
      output?(e["actual"]) and output?(e["oracle"]) and
      optional_output?(e["follow_on_actual"]) and optional_output?(e["follow_on_candidate"]) and
      items?(e["law_rows"], 49, &law_row?/1)
  end

  defp law_row?(r) do
    keys?(r, ~w(slug label reason source_sha256 bindings_tested exhaustive_for_source_domain)) and
      texts?(r, ~w(slug label reason source_sha256)) and
      r["label"] in ~w(catches allows_here does_not_apply cant_check) and
      nonnegative?(r["bindings_tested"]) and is_boolean(r["exhaustive_for_source_domain"])
  end

  defp answer?(a) do
    keys?(
      a,
      ~w(answer_id request_id card_id actor probe_id choice reason evidence_ids revealed_before_answer supersedes_answer_id at_utc)
    ) and
      texts?(a, ~w(answer_id request_id card_id choice at_utc)) and a["actor"] == "human" and
      is_binary(a["reason"]) and strings?(a["evidence_ids"]) and
      is_boolean(a["revealed_before_answer"]) and optional_text?(a["probe_id"]) and
      optional_text?(a["supersedes_answer_id"])
  end

  defp command?(c) do
    keys?(c, ~w(request_id command_digest kind probe_id answer_id)) and
      texts?(c, ~w(request_id command_digest kind)) and
      c["kind"] in ~w(answer_escape answer_card pin_candidate finish_review start_job accept_ai_card add_human_card) and
      optional_text?(c["probe_id"]) and
      optional_text?(c["answer_id"])
  end

  defp job?(j) do
    keys?(
      j,
      ~w(job_id request_kind status prompt_hash input_digest source_digest based_on_human_revision validated_output completion_digest error_class at_utc)
    ) and
      texts?(j, ~w(job_id prompt_hash input_digest source_digest at_utc)) and
      j["request_kind"] in ~w(deck challenge followup) and
      j["status"] in ~w(pending complete failed interrupted discarded_late) and
      nonnegative?(j["based_on_human_revision"]) and job_result?(j)
  end

  defp job_result?(j),
    do:
      (is_nil(j["validated_output"]) or is_map(j["validated_output"])) and
        optional_text?(j["completion_digest"]) and optional_text?(j["error_class"])

  defp conclusion?(nil), do: true

  defp conclusion?(c) do
    keys?(c, ~w(outcome scope rationale evidence_ids unresolved_ids confirmed_at_utc)) and
      texts?(c, ~w(outcome scope rationale confirmed_at_utc)) and
      c["outcome"] in ~w(meets_intent_in_reviewed_scope needs_design_change needs_policy_or_evidence) and
      strings?(c["evidence_ids"]) and
      strings?(c["unresolved_ids"])
  end

  defp references?(doc) do
    graph = doc["graph_snapshot"]
    nodes = MapSet.new(graph["nodes"], & &1["id"])
    sources = MapSet.new(graph["excerpts"], & &1["id"])
    probes = MapSet.new(doc["pinned_probes"], & &1["id"])
    cards = doc["core_cards"] ++ doc["accepted_ai_cards"]
    known = nodes |> MapSet.union(sources) |> MapSet.union(probes)

    valid_core?(doc) and unique_records?(doc) and
      Enum.all?(graph["edges"], &edge_links?(&1, nodes)) and
      Enum.all?(cards, &card_links?(&1, nodes, known)) and
      Enum.all?(doc["answers"], &answer_links?(&1, cards, probes, known))
  end

  defp valid_core?(doc) do
    core = doc["core_cards"]

    Enum.sort(Enum.map(core, & &1["kind"])) == ~w(assumption escape reading silence trace) and
      Enum.count(core, & &1["mandatory"]) == 3 and
      Enum.filter(core, & &1["critical"]) |> Enum.map(& &1["kind"]) == ["escape"]
  end

  defp unique_records?(doc) do
    collections = [
      {doc["core_cards"] ++ doc["accepted_ai_cards"] ++ doc["suggested_ai_cards"], "id"},
      {doc["answers"], "answer_id"},
      {doc["pinned_probes"], "id"},
      {doc["human_commands"], "request_id"},
      {doc["ai_jobs"], "job_id"}
    ]

    Enum.all?(collections, fn {records, key} ->
      length(Enum.uniq_by(records, & &1[key])) == length(records)
    end)
  end

  defp edge_links?(edge, nodes),
    do: MapSet.member?(nodes, edge["from_id"]) and MapSet.member?(nodes, edge["to_id"])

  defp card_links?(card, nodes, known),
    do:
      MapSet.member?(nodes, card["target_node_id"]) and
        Enum.all?(card["source_ids"], &MapSet.member?(known, &1))

  defp answer_links?(answer, cards, probes, known) do
    case Enum.find(cards, &(&1["id"] == answer["card_id"])) do
      nil ->
        false

      card ->
        answer["choice"] in Dossier.choices(card["kind"]) and
          answer_probe?(answer["probe_id"], card["kind"], probes) and
          Enum.all?(answer["evidence_ids"], &MapSet.member?(known, &1))
    end
  end

  defp answer_probe?(nil, kind, _probes), do: kind != "escape"
  defp answer_probe?(id, _kind, probes), do: MapSet.member?(probes, id)

  defp keys?(map, keys), do: is_map(map) and Enum.sort(Map.keys(map)) == Enum.sort(keys)
  defp texts?(map, keys), do: Enum.all?(keys, &text?(map[&1]))
  defp text?(s), do: is_binary(s) and byte_size(s) > 0
  defp optional_text?(nil), do: true
  defp optional_text?(s), do: text?(s)
  defp strings?(items), do: items?(items, 500, &text?/1)

  defp items?(items, max, check),
    do: is_list(items) and length(items) <= max and Enum.all?(items, check)

  defp nonnegative?(n), do: is_integer(n) and n >= 0
  defp positive?(n), do: is_integer(n) and n > 0
  defp output?(o), do: match?({:ok, _}, TermCodec.decode_output(o))
  defp optional_output?(nil), do: true
  defp optional_output?(o), do: output?(o)
end
