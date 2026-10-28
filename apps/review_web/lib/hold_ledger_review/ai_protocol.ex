defmodule HoldLedgerReview.AIProtocol do
  @moduledoc """
  Schema-first, source-bound validation for the three AI proposal envelopes.
  Provider JSON Schema is only a transport constraint; every response is checked
  again here before it can be committed. No model output is an evidence verdict.
  """
  alias HoldLedgerReview.{Adversarial, Canonical}

  @kinds ~w(deck challenge followup)
  @max_bytes %{"deck" => 32_768, "challenge" => 16_384, "followup" => 16_384}
  @statuses ~w(catches allows_here does_not_apply cant_check)

  def schema(kind) when kind in @kinds do
    Application.app_dir(:hold_ledger_review_web, "priv/contracts/#{kind}.schema.json")
    |> File.read!()
    |> Jason.decode!()
  end

  @doc """
  Wire representation for the configured provider's strict-schema subset.
  Canonical schemas stay unchanged and validate every response locally.
  Event/effect oneOf branches have disjoint type constants, so anyOf preserves
  their meaning. Unique array members remain enforced by structure?/2.
  """
  def provider_schema(kind, context \\ nil) do
    schema = kind |> schema() |> wire_schema()
    constrain_targets(schema, kind, context)
  end

  defp constrain_targets(schema, _kind, nil), do: schema

  defp constrain_targets(schema, "deck", context) do
    schema
    |> put_in(["properties", "target_node_id", "enum"], [context.target_node_id])
    |> put_in(
      ["properties", "card_suggestions", "items", "properties", "target_node_id", "enum"],
      context.policy_nodes
    )
  end

  defp constrain_targets(schema, "challenge", context),
    do: put_in(schema, ["properties", "target_card_id", "enum"], [context.card_id])

  defp constrain_targets(schema, "followup", context),
    do: put_in(schema, ["properties", "card_id", "enum"], [context.card_id])

  defp wire_schema(value) when is_map(value) do
    value
    |> Map.delete("uniqueItems")
    |> Map.new(fn
      {"oneOf", branches} -> {"anyOf", wire_schema(branches)}
      {key, item} -> {key, wire_schema(item)}
    end)
  end

  defp wire_schema(value) when is_list(value), do: Enum.map(value, &wire_schema/1)
  defp wire_schema(value), do: value

  def prompt(kind) when kind in @kinds do
    Application.app_dir(:hold_ledger_review_web, "priv/prompts/#{kind}.md") |> File.read!()
  end

  @doc "Check JSON Schema's closed subset used by the shipped contracts, including nested oneOf."
  def structure?(value, schema) when is_map(schema) do
    alternatives?(value, Map.get(schema, "oneOf"), :one) and
      alternatives?(value, Map.get(schema, "anyOf"), :any) and
      scalar_rules?(value, schema) and string_rules?(value, schema) and
      number_rules?(value, schema) and object_rules?(value, schema) and
      array_rules?(value, schema)
  end

  def structure?(_, _), do: false

  defp alternatives?(_value, nil, _mode), do: true

  defp alternatives?(value, schemas, :one),
    do: Enum.count(schemas, &structure?(value, &1)) == 1

  defp alternatives?(value, schemas, :any),
    do: Enum.any?(schemas, &structure?(value, &1))

  defp scalar_rules?(value, schema) do
    type?(value, Map.get(schema, "type")) and
      (not Map.has_key?(schema, "const") or value == schema["const"]) and
      (not Map.has_key?(schema, "enum") or value in schema["enum"])
  end

  defp type?(_value, nil), do: true
  defp type?(v, types) when is_list(types), do: Enum.any?(types, &type?(v, &1))
  defp type?(v, "object"), do: is_map(v) and not is_struct(v)
  defp type?(v, "array"), do: is_list(v)
  defp type?(v, "string"), do: is_binary(v)
  defp type?(v, "integer"), do: is_integer(v)
  defp type?(v, "number"), do: is_number(v)
  defp type?(v, "boolean"), do: is_boolean(v)
  defp type?(v, "null"), do: is_nil(v)
  defp type?(_, _), do: false

  defp string_rules?(v, s) when is_binary(v) do
    String.valid?(v) and
      (not Map.has_key?(s, "minLength") or String.length(v) >= s["minLength"]) and
      (not Map.has_key?(s, "maxLength") or String.length(v) <= s["maxLength"]) and
      byte_size(v) <= 2_400
  end

  defp string_rules?(_, _), do: true

  defp number_rules?(v, s) when is_number(v) do
    (not Map.has_key?(s, "minimum") or v >= s["minimum"]) and
      (not Map.has_key?(s, "maximum") or v <= s["maximum"])
  end

  defp number_rules?(_, _), do: true

  defp object_rules?(v, s) when is_map(v) do
    fields = Map.get(s, "properties", %{})
    required = Map.get(s, "required", [])

    Enum.all?(Map.keys(v), &is_binary/1) and
      Enum.all?(required, &Map.has_key?(v, &1)) and
      (Map.get(s, "additionalProperties") != false or
         Enum.all?(Map.keys(v), &Map.has_key?(fields, &1))) and
      Enum.all?(v, fn {k, x} ->
        not Map.has_key?(fields, k) or structure?(x, fields[k])
      end)
  end

  defp object_rules?(_, _), do: true

  defp array_rules?(v, s) when is_list(v) do
    (not Map.has_key?(s, "minItems") or length(v) >= s["minItems"]) and
      (not Map.has_key?(s, "maxItems") or length(v) <= s["maxItems"]) and
      (Map.get(s, "uniqueItems") != true or length(Enum.uniq(v)) == length(v)) and
      (not Map.has_key?(s, "items") or Enum.all?(v, &structure?(&1, s["items"])))
  end

  defp array_rules?(_, _), do: true

  @doc "Return a bounded, semantically checked, persistent proposal/result record."
  def validate(kind, output, context) when kind in @kinds and is_map(context) do
    with true <- is_map(output) and byte_size(Canonical.json(output)) <= @max_bytes[kind],
         true <- structure?(output, schema(kind)),
         true <- output["request_kind"] == kind do
      semantic(kind, output, context)
    else
      _ -> {:error, :invalid_model_output}
    end
  rescue
    _ -> {:error, :invalid_model_output}
  end

  def validate(_, _, _), do: {:error, :invalid_model_output}

  @doc "Enforce the persisted completion boundary, including source and digest provenance."
  def persistable?(doc, job, output) when is_map(output) do
    kind = job["request_kind"]
    provenance = output["provenance"]

    trace_ok =
      is_map(provenance) and
        Enum.sort(Map.keys(provenance)) ==
          ~w(input_sha256 latency_ms origin prompt_sha256) and
        provenance["origin"] == "model_proposed" and
        provenance["input_sha256"] == job["input_digest"] and
        provenance["prompt_sha256"] == job["prompt_hash"] and
        is_integer(provenance["latency_ms"]) and provenance["latency_ms"] >= 0

    trace_ok and persistable_kind?(doc, kind, output)
  rescue
    _ -> false
  end

  def persistable?(_, _, _), do: false

  defp persistable_kind?(doc, "deck", output) do
    with true <-
           exact_map?(
             output,
             ~w(deck reading_checks suggested_cards deduplicated_count provenance)
           ),
         true <- structure?(output["deck"], schema("deck")),
         true <- is_integer(output["deduplicated_count"]) and output["deduplicated_count"] >= 0 do
      Enum.any?(
        doc["core_cards"] ++ doc["accepted_ai_cards"],
        &matching_deck?(doc, &1, output)
      )
    else
      _ -> false
    end
  end

  defp persistable_kind?(doc, "challenge", output) do
    with true <- exact_map?(output, ~w(challenge evaluation provenance)),
         true <- structure?(output["challenge"], schema("challenge")),
         true <- valid_references?(doc, output["challenge"]["source_ids"]),
         true <-
           Enum.any?(
             doc["core_cards"] ++ doc["accepted_ai_cards"],
             &(&1["id"] == output["challenge"]["target_card_id"])
           ),
         {:ok, decoded} <- Adversarial.decode(output["challenge"]["witness"]),
         {:ok, encoded} <- Adversarial.encode(decoded),
         true <- encoded == output["challenge"]["witness"],
         {:ok, evaluation, _} <- Adversarial.evaluate(encoded) do
      evaluation == output["evaluation"]
    else
      _ -> false
    end
  end

  defp persistable_kind?(doc, "followup", output) do
    exact_map?(output, ~w(followup provenance)) and
      structure?(output["followup"], schema("followup")) and
      valid_references?(doc, output["followup"]["source_ids"]) and
      Enum.any?(doc["answers"], &(&1["card_id"] == output["followup"]["card_id"]))
  end

  defp persistable_kind?(_, _, _), do: false

  defp matching_deck?(doc, card, output) do
    with {:ok, packet} <- HoldLedgerReview.AIPacket.build(doc, "deck", card["id"]),
         true <- packet.input_digest == output["provenance"]["input_sha256"],
         {:ok, checked} <- validate("deck", output["deck"], packet.context) do
      Map.take(checked, ~w(reading_checks suggested_cards deduplicated_count)) ==
        Map.take(output, ~w(reading_checks suggested_cards deduplicated_count))
    else
      _ -> false
    end
  end

  defp exact_map?(map, keys),
    do: Enum.sort(Map.keys(map)) == Enum.sort(keys)

  defp valid_references?(doc, ids) do
    known =
      Enum.map(doc["graph_snapshot"]["nodes"], & &1["id"]) ++
        Enum.map(doc["graph_snapshot"]["excerpts"], & &1["id"])

    is_list(ids) and ids != [] and Enum.all?(ids, &(&1 in known))
  end

  defp semantic("deck", output, ctx) do
    citations = fn item -> citations?(item["source_ids"], ctx) end

    valid =
      output["target_node_id"] == ctx.target_node_id and
        Enum.all?(output["intent_hypotheses"], citations) and
        Enum.all?(output["uncertainties"], citations) and
        Enum.all?(output["readings"], &valid_reading?(&1, ctx)) and
        Enum.all?(output["card_suggestions"], &valid_card?(&1, ctx)) and
        Enum.uniq_by(output["card_suggestions"], & &1["proposal_id"]) ==
          output["card_suggestions"]

    if valid do
      checks = Enum.map(output["readings"], &check_reading(&1, ctx.probes))
      {cards, discarded} = cards(output["card_suggestions"], ctx)

      {:ok,
       %{
         "deck" => output,
         "reading_checks" => checks,
         "suggested_cards" => cards,
         "deduplicated_count" => discarded
       }}
    else
      {:error, :unknown_model_reference}
    end
  end

  defp semantic("challenge", output, ctx) do
    with true <- output["target_card_id"] == ctx.card_id,
         true <- citations?(output["source_ids"], ctx),
         {:ok, decoded} <- Adversarial.decode(output["witness"]),
         {:ok, canonical} <- Adversarial.encode(decoded),
         true <- canonical == output["witness"],
         {:ok, evaluation, _details} <- Adversarial.evaluate(canonical) do
      {:ok, %{"challenge" => output, "evaluation" => evaluation}}
    else
      _ -> {:error, :invalid_challenge}
    end
  end

  defp semantic("followup", output, ctx) do
    if output["card_id"] == ctx.card_id and citations?(output["source_ids"], ctx) and
         normalize(output["question"]) != normalize(ctx.card_question) and
         is_map(ctx.latest_answer) do
      {:ok, %{"followup" => output}}
    else
      {:error, :invalid_followup}
    end
  end

  defp valid_reading?(reading, ctx) do
    citations?(reading["source_ids"], ctx) and reading["claim_slug"] in ctx.claim_slugs and
      Enum.all?(reading["predictions"], &valid_prediction?(&1, ctx)) and
      length(Enum.uniq_by(reading["predictions"], & &1["probe_id"])) ==
        length(reading["predictions"])
  end

  defp valid_prediction?(prediction, ctx),
    do:
      Map.has_key?(ctx.probes, prediction["probe_id"]) and
        prediction["predicted_status"] in @statuses

  defp valid_card?(card, ctx) do
    citations?(card["source_ids"], ctx) and card["target_node_id"] in ctx.policy_nodes and
      Enum.all?(card["probe_ids"], &Map.has_key?(ctx.probes, &1))
  end

  defp citations?(ids, ctx) when is_list(ids),
    do: ids != [] and Enum.all?(ids, &(&1 in ctx.source_ids))

  defp citations?(_, _), do: false

  defp check_reading(reading, probes) do
    %{
      "claim_slug" => reading["claim_slug"],
      "predictions" =>
        Enum.map(reading["predictions"], fn prediction ->
          probe = Map.fetch!(probes, prediction["probe_id"])
          row = Enum.find(probe["evaluation"]["law_rows"], &(&1["slug"] == reading["claim_slug"]))

          actual = if row, do: row["label"], else: nil

          verified =
            cond do
              actual == nil or actual == "cant_check" -> "cannot_evaluate"
              actual == prediction["predicted_status"] -> "prediction_matches"
              true -> "prediction_conflicts"
            end

          %{
            "probe_id" => prediction["probe_id"],
            "predicted_status" => prediction["predicted_status"],
            "actual_status" => actual,
            "verification" => verified,
            "computed_example" => probe["witness"]
          }
        end)
    }
  end

  defp cards(proposals, ctx) do
    prior = ctx.existing_cards

    Enum.reduce(proposals, {[], 0}, fn proposal, {accepted, discarded} ->
      fingerprint = fingerprint(proposal)
      id = "ai." <> String.slice(fingerprint, 0, 40)

      duplicates =
        Enum.any?(prior ++ accepted, fn c ->
          c["id"] == id or
            (c["kind"] == proposal["kind"] and
               c["target_node_id"] == proposal["target_node_id"] and
               near_duplicate?(c["question"], proposal["question"]))
        end)

      if duplicates do
        {accepted, discarded + 1}
      else
        card = %{
          "id" => id,
          "kind" => proposal["kind"],
          "target_node_id" => proposal["target_node_id"],
          "question" => proposal["question"],
          "source_ids" => proposal["source_ids"],
          "mandatory" => false,
          "critical" => false,
          "critical_reason" => "",
          "origin" => "ai_proposed",
          "ai_proposal_id" => proposal["proposal_id"]
        }

        {accepted ++ [card], discarded}
      end
    end)
  end

  defp fingerprint(c) do
    Canonical.digest(%{
      "kind" => c["kind"],
      "target" => c["target_node_id"],
      "meaning" => normalize(c["question"]),
      "probes" => Enum.sort(c["probe_ids"])
    })
  end

  defp normalize(text) when is_binary(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^[:alnum:]\s]/u, " ")
    |> String.split()
    |> Enum.join(" ")
  end

  defp near_duplicate?(left, right) do
    a = MapSet.new(String.split(normalize(left)))
    b = MapSet.new(String.split(normalize(right)))
    overlap = MapSet.intersection(a, b) |> MapSet.size()
    union = MapSet.union(a, b) |> MapSet.size()
    union > 0 and overlap / union >= 0.8
  end
end
