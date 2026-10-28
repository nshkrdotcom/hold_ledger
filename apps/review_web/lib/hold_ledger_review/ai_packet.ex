defmodule HoldLedgerReview.AIPacket do
  @moduledoc """
  Bounded checkout-backed inference packets. Discovery deliberately omits human
  answers, fixture names, computed probe labels, rubric and mutant mappings.
  Reconciliation is a separate request with explicit human and computed facts.
  """
  alias HoldLedgerReview.{
    Adversarial,
    AIProtocol,
    Anchor,
    Canonical,
    Claims,
    Config,
    ProofEvidence
  }

  @source_budget 65_536
  @max_excerpt 8_000

  @doc "Refuse prepared packets after source, loaded-code, report or prompt drift."
  def freshness(packet) do
    with :ok <- Claims.freshness(),
         generation = Claims.snapshot(),
         true <- generation.source.sha256 == packet.source_digest,
         true <- packet.system == AIProtocol.prompt(packet.kind),
         true <-
           Canonical.digest(%{"system" => packet.system, "user" => packet.user}) ==
             packet.input_digest,
         true <-
           Enum.all?(packet.source_manifest, fn {path, digest} ->
             ProofEvidence.digest_file(Config.root(), path) == digest
           end),
         true <- current_report?(packet.proof_report, generation) do
      :ok
    else
      _ -> {:error, :stale_source}
    end
  end

  defp current_report?(saved, generation) do
    report =
      ProofEvidence.load(
        Config.root(),
        Application.get_env(:hold_ledger_review_web, :proof_report),
        Enum.map(generation.source.catalog, & &1["slug"])
      )

    saved["status"] == Atom.to_string(report.status) and
      saved["detail"] == String.slice(report.detail, 0, 300) and
      saved["report_sha256"] == Map.get(report, :report_sha256)
  end

  def build(review, kind, card_id \\ nil, witness \\ nil)
      when kind in ~w(deck challenge followup) do
    cards = review["core_cards"] ++ review["accepted_ai_cards"]

    card =
      if(is_nil(card_id), do: List.first(cards), else: Enum.find(cards, &(&1["id"] == card_id)))

    if is_nil(card) do
      {:error, :unknown_card}
    else
      build_for_card(review, kind, card, witness)
    end
  end

  defp build_for_card(review, kind, card, witness) do
    cards = review["core_cards"] ++ review["accepted_ai_cards"]
    graph = review["graph_snapshot"]
    target = card["target_node_id"]
    nodes = relevant_nodes(graph, target)
    source_ids = nodes |> Enum.flat_map(& &1["source_ids"]) |> Enum.uniq()

    connected = neighborhood_ids(graph, target)

    preferred =
      nodes
      |> Enum.filter(&(&1["id"] == target or &1["id"] in connected))
      |> Enum.flat_map(& &1["source_ids"])

    with {:ok, excerpts} <- select_excerpts(graph["excerpts"], source_ids, preferred) do
      included = MapSet.new(Enum.map(excerpts, & &1["id"]))

      nodes =
        nodes
        |> Enum.filter(fn n ->
          n["id"] == target or Enum.any?(n["source_ids"], &MapSet.member?(included, &1))
        end)
        |> Enum.map(fn n ->
          Map.take(n, ~w(id kind title))
          |> Map.put("source_ids", Enum.filter(n["source_ids"], &MapSet.member?(included, &1)))
        end)

      allowed_sources = Enum.uniq(Enum.map(nodes, & &1["id"]) ++ Enum.map(excerpts, & &1["id"]))

      allowed_claims =
        for n <- nodes, n["kind"] == "law", do: String.replace_prefix(n["id"], "law.", "")

      {public_probes, private_probes} = probes(review, kind)
      policy_nodes = for n <- graph["nodes"], n["kind"] == "policy_row", do: n["id"]

      base = %{
        "request_kind" => kind,
        "target_node_id" => target,
        "active_question" => Map.take(card, ~w(id kind question target_node_id)),
        "policy_rows" =>
          graph["nodes"]
          |> Enum.filter(&(&1["kind"] == "policy_row"))
          |> Enum.map(&Map.take(&1, ~w(id title))),
        "source_nodes" => nodes,
        "source_excerpts" => excerpts,
        "proof_report" => review["source"]["proof_report_snapshot"],
        "permitted_claim_slugs" => allowed_claims,
        "permitted_card_target_node_ids" => policy_nodes,
        "known_probes" => public_probes,
        "external_premises_are_unverified" => true
      }

      with {:ok, user_data} <- pass_data(kind, review, card, witness, base, private_probes) do
        user_message = Canonical.json(user_data)
        system_message = AIProtocol.prompt(kind)
        prompt_hash = Canonical.digest(system_message)
        input_digest = Canonical.digest(%{"system" => system_message, "user" => user_message})

        ctx = %{
          target_node_id: target,
          card_id: card["id"],
          card_question: card["question"],
          source_ids: allowed_sources,
          claim_slugs: allowed_claims,
          policy_nodes: policy_nodes,
          probes: private_probes,
          existing_cards: cards ++ review["suggested_ai_cards"],
          latest_answer: latest_answer(review, card["id"])
        }

        {:ok,
         %{
           kind: kind,
           context: ctx,
           system: system_message,
           user: user_message,
           prompt_hash: prompt_hash,
           input_digest: input_digest,
           source_manifest: review["source"]["source_manifest"],
           proof_report: review["source"]["proof_report_snapshot"],
           source_digest: review["source"]["compiled_source_digest"]
         }}
      end
    end
  end

  defp relevant_nodes(graph, target) do
    connected = neighborhood_ids(graph, target)

    # An entire law catalogue remains discoverable in the UI. A request contains
    # the policy neighborhood, registered source claims, root reducer/oracle, and
    # boundary nodes; never a hidden expected-catcher/answer table.
    graph["nodes"]
    |> Enum.filter(&relevant_node?(&1, target, connected))
    |> Enum.sort_by(&{node_priority(&1, target, connected), &1["id"]})
  end

  defp neighborhood_ids(graph, target) do
    graph["edges"]
    |> Enum.filter(&(&1["from_id"] == target or &1["to_id"] == target))
    |> Enum.map(fn e -> if(e["from_id"] == target, do: e["to_id"], else: e["from_id"]) end)
    |> Enum.take(32)
  end

  defp relevant_node?(node, target, connected) do
    node["id"] == target or node["id"] in connected or
      node["kind"] in ~w(law boundary) or
      node["id"] in ~w(reducer.step spec.expected_step spec.release_evidence? spec.valid?)
  end

  defp node_priority(node, target, connected) do
    cond do
      node["id"] == target or node["id"] in connected -> 0
      node["kind"] == "spec" -> 1
      node["kind"] == "boundary" -> 2
      node["kind"] == "reducer" -> 3
      true -> 4
    end
  end

  defp select_excerpts(excerpts, ids, preferred) do
    by_id = Map.new(excerpts, &{&1["id"], &1})

    ids
    |> Enum.flat_map(fn id -> if Map.has_key?(by_id, id), do: [by_id[id]], else: [] end)
    |> Enum.sort_by(&excerpt_priority(&1, preferred))
    |> Enum.reduce_while({[], 0}, &append_excerpt/2)
    |> case do
      {:error, _} = error -> error
      {items, _used} -> {:ok, items}
    end
  end

  # Source meaning must fit before large proof libraries and inventories.
  # Stable sorting retains policy-neighborhood ordering within each category.
  defp excerpt_priority(%{"path" => "guides/specification.md"}, _preferred), do: 0
  defp excerpt_priority(%{"path" => "lib/hold_ledger/" <> _}, _preferred), do: 1

  defp excerpt_priority(%{"path" => "test/laws/" <> _, "id" => id}, preferred),
    do: if(id in preferred, do: 2, else: 4)

  defp excerpt_priority(%{"path" => "guides/" <> _}, _preferred), do: 3
  defp excerpt_priority(%{"path" => "test/support/lean/" <> _}, _preferred), do: 5
  defp excerpt_priority(_, _preferred), do: 6

  defp excerpt_cap(%{"path" => "lib/hold_ledger/" <> _}), do: 24_000
  defp excerpt_cap(_), do: @max_excerpt

  defp append_excerpt(excerpt, {acc, used}) do
    remaining = @source_budget - used

    if remaining <= 400 do
      {:cont, {acc, used}}
    else
      append_verified_excerpt(excerpt, acc, used, remaining)
    end
  end

  defp append_verified_excerpt(excerpt, acc, used, remaining) do
    # Read exact checkout bytes independently of DesignGraph's bounded preview.
    with {:ok, full} <- Anchor.read_under(Config.root(), excerpt["path"]),
         true <- Anchor.sha(full) == excerpt["sha256"] do
      {text, truncated} = noncontiguous_excerpt(full, min(excerpt_cap(excerpt), remaining - 400))

      next =
        Map.take(excerpt, ~w(id path sha256))
        |> Map.put("text", text)
        |> Map.put("excerpt_truncated", truncated)

      {:cont, {acc ++ [next], used + byte_size(text)}}
    else
      _ -> {:halt, {:error, :stale_source}}
    end
  end

  defp noncontiguous_excerpt(text, max_bytes) when byte_size(text) <= max_bytes,
    do: {text, false}

  defp noncontiguous_excerpt(text, max_bytes) do
    marker =
      "\n[Source excerpt: non-contiguous middle omitted; both ends verified against full-file SHA-256]\n"

    allowance = max(div(max_bytes - byte_size(marker), 2), 0)
    prefix = utf8_prefix(text, allowance)
    suffix = utf8_suffix(text, max_bytes - byte_size(marker) - byte_size(prefix))
    {prefix <> marker <> suffix, true}
  end

  defp utf8_prefix(text, max_bytes) do
    bytes = min(byte_size(text), max_bytes)
    trim_utf8(text, bytes)
  end

  defp utf8_suffix(text, max_bytes) do
    count = min(byte_size(text), max(max_bytes, 0))
    suffix = binary_part(text, byte_size(text) - count, count)
    trim_utf8_head(suffix)
  end

  defp trim_utf8(text, count) when count >= 0 do
    candidate = binary_part(text, 0, count)
    if String.valid?(candidate), do: candidate, else: trim_utf8(text, count - 1)
  end

  defp trim_utf8_head(text) when byte_size(text) > 0 do
    if String.valid?(text),
      do: text,
      else: trim_utf8_head(binary_part(text, 1, byte_size(text) - 1))
  end

  defp trim_utf8_head(_), do: ""

  defp probes(review, kind) when kind in ~w(deck challenge) do
    # These are transparent synthetic thought experiments, never recorded model
    # observations. Opaque IDs prevent fixture filename leakage. Results stay
    # on the server for independent post-response prediction checks only.
    seed_event =
      case Adversarial.seed(review["seed_id"]) do
        {:ok, w} -> w["event"]["type"]
        _ -> nil
      end

    seed_witnesses =
      Adversarial.seeds()
      |> Enum.flat_map(fn id ->
        matching_seed(id, seed_event)
      end)

    # A single seed event (currently exact-fit request) would otherwise make a
    # valid 2–3-prediction reading impossible. Add a shape-valid synthetic
    # counterfactual, not an answer label or an observed mutant output.
    candidates =
      if length(seed_witnesses) == 1 do
        [only] = seed_witnesses
        seed_witnesses ++ [shift_candidate_counter(only)]
      else
        seed_witnesses
      end

    candidates
    |> Enum.reduce({[], %{}}, fn witness, {public, private} ->
      case Adversarial.evaluate(witness) do
        {:ok, evaluation, _} ->
          opaque_id = "probe." <> String.slice(Canonical.digest(witness), 0, 32)

          {[%{"probe_id" => opaque_id, "witness" => witness} | public],
           Map.put(private, opaque_id, %{"witness" => witness, "evaluation" => evaluation})}

        _ ->
          {public, private}
      end
    end)
    |> then(fn {public, private} -> {Enum.reverse(public), private} end)
  end

  defp probes(_review, _kind), do: {[], %{}}

  defp matching_seed(id, event) do
    case Adversarial.seed(id) do
      {:ok, %{"event" => %{"type" => ^event}} = witness} -> [witness]
      _ -> []
    end
  end

  defp shift_candidate_counter(witness) do
    old = get_in(witness, ["output", "after", "used_amount"])
    next = if old < 1_000_000, do: old + 1, else: old - 1
    put_in(witness, ["output", "after", "used_amount"], next)
  end

  defp pass_data("deck", _review, _card, _witness, base, _private), do: {:ok, base}

  defp pass_data("challenge", _review, _card, witness, base, _private) do
    with {:ok, native} <- Adversarial.decode(witness),
         {:ok, canonical} <- Adversarial.encode(native),
         true <- canonical == witness do
      {:ok, Map.put(base, "currently_displayed_typed_witness", canonical)}
    else
      _ -> {:error, :invalid_draft}
    end
  end

  defp pass_data("followup", review, card, _witness, base, _private) do
    answer = latest_answer(review, card["id"])

    history =
      review["answers"] |> Enum.filter(&(&1["card_id"] == card["id"])) |> Enum.take(-3)

    if answer do
      computed = answer_evidence(review, answer)

      prior =
        review["ai_jobs"]
        |> Enum.filter(&(&1["request_kind"] == "followup" and &1["status"] == "complete"))
        |> List.last()

      {:ok,
       base
       |> Map.put(
         "human_answer",
         Map.take(answer, ~w(card_id choice reason evidence_ids revealed_before_answer at_utc))
       )
       |> Map.put(
         "recent_human_answer_history",
         Enum.map(history, &Map.take(&1, ~w(choice reason at_utc)))
       )
       |> Map.put("computed_counterexample_or_boundary", computed)
       |> Map.put(
         "previous_model_question",
         if(prior, do: get_in(prior, ["validated_output", "followup", "question"]), else: nil)
       )}
    else
      {:error, :answer_required}
    end
  end

  defp answer_evidence(review, answer) do
    case Enum.find(review["pinned_probes"], &(&1["id"] == answer["probe_id"])) do
      nil -> seed_evidence(review["seed_id"])
      probe -> Map.take(probe, ~w(witness evaluation))
    end
  end

  defp seed_evidence(seed_id) do
    with {:ok, seed} <- Adversarial.seed(seed_id),
         {:ok, evaluation, _} <- Adversarial.evaluate(seed) do
      %{"witness" => seed, "evaluation" => evaluation}
    else
      _ -> nil
    end
  end

  defp latest_answer(review, id) do
    review["answers"] |> Enum.reverse() |> Enum.find(&(&1["card_id"] == id))
  end
end
