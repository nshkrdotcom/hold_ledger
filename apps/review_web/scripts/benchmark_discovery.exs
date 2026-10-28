# Run from apps/review_web only with --allow-external-source-data.
# This script intentionally does not import or open priv/benchmark/rubric.json.
# It cannot place hidden answer labels, target catchers or mutant annotations in a request.

alias HoldLedgerReview.{Adversarial, AI, Canonical, ReviewStore}

args =
  case System.argv() do
    ["--" | arguments] -> arguments
    arguments -> arguments
  end

consent = "--allow-external-source-data" in args

unless consent and Enum.all?(args, &(&1 == "--allow-external-source-data")) do
  IO.puts(
    :stderr,
    "Refused: explicitly pass --allow-external-source-data to send source and synthetic draft data to the configured inference provider"
  )

  System.halt(2)
end

case AI.available?() do
  {:ok, _} ->
    :ok

  {:error, reason} ->
    IO.puts(:stderr, "Live configured inference NOT RUN: #{inspect(reason)}")
    System.halt(3)
end

# Keep bounded original provider responses in this ignored benchmark report,
# including rejected proposals. They are observations, never accepted app cards.
run_observed = fn packet ->
  started = System.monotonic_time(:millisecond)

  result =
    AI.run(packet, consent,
      complete: fn client, request ->
        response = Inference.complete(client, request)

        observation =
          case response do
            {:ok, value} ->
              raw = value.object || Inference.Response.text(value)
              encoded = Jason.encode!(raw)

              if byte_size(encoded) <= 32_768,
                do: %{"raw_response" => raw},
                else: %{"raw_response_omitted" => "response_over_budget"}

            {:error, error} ->
              %{
                "error_category" => to_string(error.category),
                "error_message" => String.slice(error.message, 0, 2000)
              }
          end

        Process.put(:benchmark_provider_observation, observation)
        response
      end
    )

  observation = Process.delete(:benchmark_provider_observation) || %{}
  {result, Map.put(observation, "latency_ms", System.monotonic_time(:millisecond) - started)}
end

# Scenarios are internal setup only. The packet builder removes their filenames,
# hidden fixture labels, expected matrices and all reviewer state for discovery.
scenarios = ~w(P01 P03 P04)
started_at = DateTime.utc_now() |> DateTime.to_iso8601()

results =
  Enum.map(scenarios, fn seed ->
    {:ok, review, witness} = ReviewStore.create(seed)
    card = Enum.find(review["core_cards"], &(&1["kind"] == "escape"))

    source_registry =
      Enum.map(review["graph_snapshot"]["excerpts"], &Map.take(&1, ~w(id path sha256))) ++
        Enum.flat_map(review["graph_snapshot"]["nodes"], fn node ->
          case node["source_ids"] do
            [source_id] ->
              source = Enum.find(review["graph_snapshot"]["excerpts"], &(&1["id"] == source_id))

              if source,
                do: [Map.put(Map.take(source, ~w(path sha256)), "id", node["id"])],
                else: []

            _ ->
              []
          end
        end)

    {:ok, deck_packet} = AI.prepare(review, "deck", card["id"])
    IO.puts("Starting configured discovery for #{seed}")
    {deck_result, deck_observation} = run_observed.(deck_packet)
    IO.inspect(elem(deck_result, 0), label: "Discovery result")
    {:ok, challenge_packet} = AI.prepare(review, "challenge", card["id"], witness)
    {challenge_result, challenge_observation} = run_observed.(challenge_packet)
    IO.inspect(elem(challenge_result, 0), label: "Challenge result")

    deck =
      case deck_result do
        {:ok, output} -> %{"status" => "configured_model_response_validated", "output" => output}
        {:error, reason} -> %{"status" => "failed", "error_class" => to_string(reason)}
      end

    challenge =
      case challenge_result do
        {:ok, output} ->
          %{
            "status" => "configured_model_response_validated",
            "output" => output,
            "novel_witness" =>
              Map.take(output["challenge"]["witness"], ~w(before event output)) not in Enum.map(
                Enum.map(Adversarial.seeds(), fn id ->
                  {:ok, w} = Adversarial.seed(id)
                  w
                end) ++
                  Enum.map(deck_packet.context.probes, fn {_id, p} -> p["witness"] end),
                &Map.take(&1, ~w(before event output))
              )
          }

        {:error, reason} ->
          %{"status" => "failed", "error_class" => to_string(reason), "novel_witness" => false}
      end

    %{
      "case" =>
        "case-#{length(review["target_policy_nodes"])}-#{String.slice(Canonical.digest(%{"seed" => seed}), 0, 10)}",
      "target_node_id" => card["target_node_id"],
      "source_digest" => review["source"]["compiled_source_digest"],
      "source_registry" => source_registry,
      "discovery_request_digest" => deck_packet.input_digest,
      "discovery_sent_context" =>
        Map.take(
          Jason.decode!(deck_packet.user),
          ~w(source_nodes permitted_claim_slugs permitted_card_target_node_ids known_probes)
        )
        |> Map.put(
          "source_excerpt_manifest",
          Enum.map(Jason.decode!(deck_packet.user)["source_excerpts"], &Map.drop(&1, ["text"]))
        ),
      "server_probe_evidence_not_sent_to_model" => deck_packet.context.probes,
      "discovery" => Map.put(deck, "provider_observation", deck_observation),
      "challenge" => Map.put(challenge, "provider_observation", challenge_observation)
    }
  end)

client = AI.client()

report = %{
  "evidence_kind" => "configured_model_live_evaluation",
  "not_a_formal_proof" => true,
  "run_started_at_utc" => started_at,
  "run_finished_at_utc" => DateTime.utc_now() |> DateTime.to_iso8601(),
  "provider" => to_string(client.provider),
  "model" => client.model,
  "reasoning_effort" => to_string(Keyword.fetch!(client.defaults, :reasoning_effort)),
  "response_contracts" => ~w(deck challenge),
  "source_data_consent" => "operator_explicit_cli_opt_in",
  "cases" => results
}

dir = Path.join(HoldLedgerReview.Config.root(), "tmp/review_studio/benchmarks")
File.mkdir_p!(dir)
file = Path.join(dir, "discovery-#{String.slice(Canonical.digest(report), 0, 20)}.json")
:ok = ReviewStore.atomic_write(file, Canonical.json(report) <> "\n")
IO.puts("Configured-model benchmark saved: #{file}")
IO.puts("Score offline: python3 apps/review_web/scripts/score_discovery.py #{file}")
