defmodule HoldLedgerReview.Part3Result do
  @moduledoc """Reject mismatched or malformed child evidence before durable ingestion."""
  alias HoldLedgerReview.{Adversarial, Canonical, Part3Package, Part3Snapshots, TermCodec}
  alias HoldLedgerReview.Claims.{Compiler, Source}

  @fields ~w(schema_version request_id snapshot_id context_digest input_digest source_manifest_digest source_generation evaluator_id loaded_evaluator_id codec_id dependency_id toolchain_id evaluation claims completion_digest)
  @statuses ~w(catches allows_here doesnt_apply cant_check not_probed)

  def validate(result, package, attempt, witness) do
    snapshot = if attempt["snapshot_id"] == package["baseline"]["snapshot_id"], do: package["baseline"], else: package["proposal"]
    with true <- is_map(result) and Enum.sort(Map.keys(result)) == Enum.sort(@fields),
         true <- result["schema_version"] == 1 and
           result["request_id"] == attempt["id"] and result["snapshot_id"] == attempt["snapshot_id"] and
           result["context_digest"] == package["context_digest"] and
           result["input_digest"] == attempt["input_digest"] and
           result["input_digest"] == Canonical.digest(witness),
         true <- result["source_manifest_digest"] == Canonical.digest(snapshot["manifest"]) and
           result["codec_id"] == snapshot["codec_id"] and
           result["dependency_id"] == snapshot["dependency_id"] and
           result["toolchain_id"] == snapshot["toolchain_id"] and
           result["evaluator_id"] == snapshot["evaluator_id"],
         true <- Part3Package.sha?(result["source_generation"]) and Part3Package.sha?(result["loaded_evaluator_id"]),
         {:ok, source} <- Source.snapshot(Part3Snapshots.root(snapshot["snapshot_id"])),
         true <- result["source_generation"] == source.sha256,
         true <- result["completion_digest"] == Canonical.digest(Map.delete(result, "completion_digest")),
         true <- valid_evaluation?(result["evaluation"], witness),
         {:ok, decoded} <- Adversarial.decode(witness),
         {:ok, expected} <- source_active_slugs(source, Part3Snapshots.root(snapshot["snapshot_id"]), decoded.event),
         true <- Enum.sort(Map.keys(result["claims"])) == expected,
         true <- Enum.sort(Enum.map(result["evaluation"]["law_rows"], & &1["slug"])) == Enum.sort(expected),
         true <- valid_claims?(result["claims"], source) do
      :ok
    else
      _ -> {:error, :invalid_or_forged_replay_result}
    end
  end

  # Static extraction of the child snapshot's supported claim operations;
  # NEVER choose its scope from the live Phoenix Claims generation. This only
  # parses source AST using the original audited compiler; it evaluates no
  # proposal code in the live VM.
  defp source_active_slugs(source, root, event) do
    operation = case event do
      {:request, _, _} -> :request
      {:void, _} -> :void
      {:timeout, _} -> :timeout
      {:dispatch, _} -> :dispatch
    end
    {raw, _errors} = Source.extract(root, source)
    expected = raw
      |> Enum.flat_map(fn {slug, claim} ->
        case Compiler.prepare(claim) do
          {:ok, law} when law.operation in [:step, operation] -> [slug]
          _ -> []
        end
      end)
      |> Enum.sort()
    {:ok, expected}
  rescue
    _ -> {:error, :unsupported_snapshot_claim_scope}
  end

  defp valid_evaluation?(e, witness) do
    is_map(e) and Enum.sort(Map.keys(e)) == Enum.sort(~w(candidate_hash actual oracle law_rows follow_on_actual follow_on_candidate scope)) and
      e["scope"] == "pointwise_pure_ledger" and e["candidate_hash"] == Canonical.digest(witness["output"]) and
      Enum.all?(~w(actual oracle), &match?({:ok, _}, TermCodec.decode_output(e[&1]))) and
      Enum.all?(~w(follow_on_actual follow_on_candidate), &(is_nil(e[&1]) or match?({:ok, _}, TermCodec.decode_output(e[&1])))) and
      is_list(e["law_rows"]) and length(e["law_rows"]) <= 50 and
      Enum.all?(e["law_rows"], fn row ->
        is_map(row) and is_binary(row["slug"]) and
          is_binary(row["source_sha256"]) and
          is_integer(row["bindings_tested"]) and row["bindings_tested"] in 0..8 and
          is_boolean(row["exhaustive_for_source_domain"]) and
          is_binary(row["reason"]) and is_binary(row["label"])
      end)
  end

  defp valid_claims?(claims, source) when is_map(claims) and map_size(claims) <= 50 do
    known = Map.new(source.catalog, &{&1["slug"], &1["file"]})
    Enum.all?(claims, fn {slug, claim} ->
      is_binary(slug) and Map.has_key?(known, slug) and
        is_map(claim) and Enum.sort(Map.keys(claim)) == ~w(bindings source_sha256 status) and
        (claim["source_sha256"] == source.file_sha256[known[slug]] or
         (is_nil(claim["source_sha256"]) and claim["bindings"] == [] and claim["status"] in ~w(cant_check not_probed))) and
        claim["status"] in @statuses and is_list(claim["bindings"]) and length(claim["bindings"]) <= 8 and
        Enum.all?(claim["bindings"], fn b ->
          is_map(b) and Enum.sort(Map.keys(b)) == ~w(binding_id post_actual post_candidate requires values) and
            is_map(b["values"]) and b["binding_id"] == Canonical.digest(b["values"]) and
            Enum.all?(~w(post_actual post_candidate requires), &(b[&1] in [true, false, nil]))
        end)
    end)
  end
  defp valid_claims?(_, _), do: false
end
