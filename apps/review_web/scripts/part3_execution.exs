# Invoked only by the bounded local worker in a fresh OS process. `mix run`
# compiles the selected source tree before loading this file. No source code is
# evaluated or module-rewritten inside the live Phoenix VM.
alias HoldLedgerReview.{Adversarial, Anchor, Canonical, Claims, Config, Part3Snapshots}

boolean_or_nil = fn value -> if is_boolean(value), do: value, else: nil end

case Enum.drop_while(System.argv(), &(&1 == "--")) do
  [request_path, result_path] ->
    try do
      request = request_path |> File.read!() |> Jason.decode!()
      keys = ~w(schema_version request_id snapshot_id context_digest input_digest witness)
      if Enum.sort(Map.keys(request)) != Enum.sort(keys) or request["schema_version"] != 1,
        do: raise("invalid request schema")

      root = Config.root()
      snapshot = root |> Path.join(".part3-snapshot.json") |> File.read!() |> Jason.decode!()
      identity = Map.take(snapshot, ~w(schema_version commit dirty manifest))
      if snapshot["snapshot_id"] != request["snapshot_id"] or
           Canonical.digest(identity) != snapshot["snapshot_id"],
        do: raise("snapshot identity mismatch")

      check_sources = fn ->
        case Anchor.read_many_under(root, Map.keys(snapshot["manifest"])) do
          {:ok, files} ->
            if not Enum.all?(snapshot["manifest"], fn {p, hash} -> Anchor.sha(files[p]) == hash end),
              do: raise("snapshot file drift")
          _ -> raise("snapshot source unavailable")
        end
      end

      check_sources.()
      if Canonical.digest(request["witness"]) != request["input_digest"],
        do: raise("input digest mismatch")

      with :ok <- Claims.freshness(),
           {:ok, decoded} <- Adversarial.decode(request["witness"]),
           {:ok, reencoded} <- Adversarial.encode(decoded),
           true <- reencoded == request["witness"],
           true <- HoldLedger.Spec.valid?(decoded.before),
           {:ok, evaluation, details} <- Adversarial.evaluate(reencoded) do
        slugs = Adversarial.active_slugs(decoded.event)
        bindings = details.checks
        claims =
          Map.new(slugs, fn slug ->
            row = Map.fetch!(bindings, slug)
            data = %{
              "source_sha256" => Map.get(row, :source_sha256),
              "status" => Atom.to_string(row.status),
              "bindings" => Enum.map(row.rows, fn entry ->
                %{"binding_id" => Canonical.digest(entry.actual_binding_values),
                  "values" => entry.actual_binding_values,
                  "requires" => boolean_or_nil.(entry.requires),
                  "post_candidate" => boolean_or_nil.(entry.substituted_expects),
                  "post_actual" => boolean_or_nil.(entry.source_actual_expects)}
              end)
            }
            {slug, data}
          end)

        body = %{
          "schema_version" => 1,
          "request_id" => request["request_id"],
          "snapshot_id" => request["snapshot_id"],
          "context_digest" => request["context_digest"],
          "input_digest" => request["input_digest"],
          "source_manifest_digest" => Canonical.digest(snapshot["manifest"]),
          "source_generation" => Claims.snapshot().source.sha256,
          "evaluator_id" => Canonical.digest(Map.take(snapshot["manifest"], Part3Snapshots.evaluator_paths())),
          "loaded_evaluator_id" => Claims.snapshot().evaluator_id,
          "loaded_fingerprint" => Claims.snapshot().loaded_fingerprint,
          "generated_identity" => Claims.snapshot().generated_identity,
          "dependency_id" => Canonical.digest(Map.take(snapshot["manifest"], ~w(mix.lock apps/review_web/mix.lock uv.lock pyproject.toml))),
          "toolchain_id" => Canonical.digest(Map.take(snapshot["manifest"], ~w(.tool-versions lean-toolchain .python-version scripts/toolchains.json))),
          "codec_id" => snapshot["manifest"]["apps/review_web/lib/hold_ledger_review/term_codec.ex"],
          "evaluation" => evaluation,
          "claims" => claims
        }
        check_sources.()
        if Claims.freshness() != :ok, do: raise("evaluator source drift after execution")
        File.write!(result_path, Canonical.json(Map.put(body, "completion_digest", Canonical.digest(body))) <> "\n")
      else
        reason -> raise("unsupported or invalid execution: #{inspect(reason)}")
      end
    rescue
      e ->
        IO.puts(:stderr, Exception.message(e) |> String.slice(0, 500))
        System.halt(2)
    end

  _ ->
    IO.puts(:stderr, "Expected an identified request and result path")
    System.halt(2)
end
