defmodule HoldLedgerReview.Part3Snapshots do
  @moduledoc "Reads operator-staged, immutable local source snapshots. The browser can only\nchoose 64-hex identities previously staged by the terminal tool. These trees\nare trusted executable code, not a sandbox for arbitrary uploads.\n"
  alias HoldLedgerReview.{Anchor, Canonical, Config}
  @identity_keys ~w(schema_version commit dirty manifest)
  @keys @identity_keys ++ ["snapshot_id"]
  @required ~w(mix.exs mix.lock .tool-versions lean-toolchain verification/laws.json verification/obligations.json lib/hold_ledger/ledger.ex lib/hold_ledger/spec.ex apps/review_web/mix.exs apps/review_web/mix.lock apps/review_web/lib/hold_ledger_review/term_codec.ex)
  @evaluator ~w(apps/review_web/lib/hold_ledger_review/proof_reading/links.ex apps/review_web/lib/hold_ledger_review/proof_reading.ex apps/review_web/lib/hold_ledger_review/contrast.ex apps/review_web/priv/claim_readings.json apps/review_web/lib/hold_ledger_review/claims/explanation.ex apps/review_web/lib/hold_ledger_review/review_store.ex apps/review_web/lib/hold_ledger_review/trace.ex apps/review_web/lib/hold_ledger_review/adversarial.ex apps/review_web/lib/hold_ledger_review/claim_probe.ex apps/review_web/lib/hold_ledger_review/claims.ex apps/review_web/lib/hold_ledger_review/claims/source.ex apps/review_web/lib/hold_ledger_review/claims/compiler.ex apps/review_web/lib/hold_ledger_review/term_codec.ex apps/review_web/lib/hold_ledger_review/canonical.ex apps/review_web/lib/hold_ledger_review/config.ex apps/review_web/lib/hold_ledger_review/anchor.ex apps/review_web/scripts/part3_execution.exs apps/review_web/scripts/part3_worker.py scripts/local_run.py apps/review_web/lib/hold_ledger_review/part3_snapshots.ex apps/review_web/lib/hold_ledger_review/part3_result.ex apps/review_web/lib/hold_ledger_review/part3_contract_delta.ex apps/review_web/lib/hold_ledger_review/part3_diagnostics.ex apps/review_web/lib/hold_ledger_review/part3_docket.ex apps/review_web/lib/hold_ledger_review/part3_repair_packet.ex apps/review_web/lib/hold_ledger_review/part3_boundary_search.ex apps/review_web/lib/hold_ledger_review/part3_package.ex apps/review_web/lib/hold_ledger_review/part3_verification.ex apps/review_web/lib/hold_ledger_review/part3_proof_inspector.ex apps/review_web/lib/hold_ledger_review/part3_editor.ex apps/review_web/lib/hold_ledger_review/part3_store.ex apps/review_web/lib/hold_ledger_review/part3_runner.ex apps/review_web/lib/hold_ledger_review/part3_ai.ex apps/review_web/lib/hold_ledger_review/part3_ai_jobs.ex apps/review_web/lib/hold_ledger_review/proof_evidence.ex scripts/provision.py apps/review_web/scripts/stage_part3_snapshot.py)
  @build_root Path.expand("../../../..", __DIR__)
  for path <- @evaluator do
    @external_resource Path.join(@build_root, path)
  end

  @build_hashes Map.new(@evaluator, fn path ->
                  {path, Anchor.sha(File.read!(Path.join(@build_root, path)))}
                end)
  @hex ~r/\A[0-9a-f]{64}\z/
  def evaluator_paths do
    @evaluator
  end

  def directory do
    Path.join(Config.root(), "tmp/review_studio/snapshots")
  end

  def root(id) when is_binary(id) do
    Path.join(directory(), id)
  end

  def identities do
    Path.wildcard(Path.join(directory(), "[0-9a-f]*"))
    |> Enum.map(&Path.basename/1)
    |> Enum.filter(&Regex.match?(@hex, &1))
    |> Enum.sort()
  end

  def load(id) when is_binary(id) do
    with true <- Regex.match?(@hex, id),
         {:ok, bytes} <- Anchor.read_under(root(id), ".part3-snapshot.json"),
         true <- byte_size(bytes) <= 200_000,
         {:ok, raw} <- Jason.decode(bytes),
         true <- valid_shape?(raw, id),
         :ok <- verify_files(id, raw["manifest"]),
         :ok <- trusted_dependencies(raw["manifest"]) do
      {:ok,
       raw
       |> Map.put(
         "toolchain_id",
         identity_of(
           raw,
           ~w(.tool-versions lean-toolchain .python-version scripts/toolchains.json)
         )
       )
       |> Map.put(
         "dependency_id",
         identity_of(raw, ~w(mix.lock apps/review_web/mix.lock uv.lock pyproject.toml))
       )
       |> Map.put(
         "codec_id",
         raw["manifest"]["apps/review_web/lib/hold_ledger_review/term_codec.ex"]
       )
       |> Map.put("evaluator_id", identity_of(raw, @evaluator))}
    else
      _ -> {:error, :invalid_or_stale_snapshot}
    end
  end

  def load(_) do
    {:error, :invalid_or_stale_snapshot}
  end

  defp valid_shape?(raw, id) do
    valid_shape_identity?(raw, id) and valid_shape_manifest?(raw, id) and
      valid_shape_content?(raw, id)
  end

  defp valid_shape_identity?(raw, id) do
    valid_shape_identity_check_0?(id, raw) and valid_shape_identity_check_1?(raw)
  end

  defp valid_shape_manifest?(raw, _id) do
    valid_shape_manifest_check_2?(raw) and valid_shape_manifest_check_3?(raw)
  end

  defp valid_shape_content?(raw, id) do
    Canonical.digest(Map.take(raw, @identity_keys)) == id
  end

  defp path?(p) when is_binary(p) do
    byte_size(p) in 1..240 and Path.type(p) == :relative and
      not Enum.any?(Path.split(p), &(&1 in ["..", ".", ".git", "tmp", "deps", "_build"])) and
      not String.contains?(p, "\\")
  end

  defp path?(_) do
    false
  end

  defp verify_files(id, manifest) do
    case Anchor.read_many_under(root(id), Map.keys(manifest)) do
      {:ok, files} ->
        if manifest_matches?(manifest, files) and
             exact_source_inventory?(id, manifest) do
          :ok
        else
          {:error, :snapshot_drift}
        end

      _ ->
        {:error, :snapshot_drift}
    end
  end

  defp exact_source_inventory?(id, manifest) do
    expected = Map.keys(manifest) |> MapSet.new() |> MapSet.put(".part3-snapshot.json")

    case inventory(root(id), "", MapSet.new()) do
      {:ok, actual} -> actual == expected
      _ -> false
    end
  end

  # Prune ignored build trees BEFORE traversal; a hash check must not walk
  # hundreds of thousands of dependency files on every completion or render.
  defp inventory(root, relative, names) do
    with {:ok, children} <- File.ls(Path.join(root, relative)) do
      Enum.reduce_while(children, {:ok, names}, &inventory_child(&1, &2, root, relative))
    end
  end

  defp inventory_child(name, {:ok, names}, root, relative) do
    path = Path.join(relative, name)

    if name in ~w(tmp _build deps node_modules .venv .local) do
      {:cont, {:ok, names}}
    else
      inventory_entry(File.lstat(Path.join(root, path)), root, path, names)
    end
  end

  defp inventory_entry({:ok, %{type: :directory}}, root, path, names) do
    case inventory(root, path, names) do
      {:ok, updated} -> {:cont, {:ok, updated}}
      error -> {:halt, error}
    end
  end

  defp inventory_entry({:ok, %{type: :regular}}, _root, path, names),
    do: {:cont, {:ok, MapSet.put(names, path)}}

  defp inventory_entry(_, _, _, _), do: {:halt, {:error, :unsafe_source}}

  defp trusted_dependencies(manifest) do
    paths =
      ~w(mix.lock apps/review_web/mix.lock uv.lock pyproject.toml .python-version scripts/toolchains.json .tool-versions lean-toolchain)

    if Enum.all?(paths, &dependency_matches?(&1, manifest)) do
      :ok
    else
      {:error, :untrusted_dependencies}
    end
  end

  defp manifest_matches?(manifest, files),
    do: Enum.all?(manifest, fn {path, expected} -> Anchor.sha(files[path]) == expected end)

  defp dependency_matches?(path, manifest) do
    case Anchor.read_under(Config.root(), path) do
      {:ok, bytes} -> Anchor.sha(bytes) == manifest[path]
      _ -> false
    end
  end

  @doc "The selected parser, protocol, runner and codec source must also match the\ncurrently trusted Phoenix installation before any new evidence is created.\nComparing two old snapshots is not license to use an unrelated live validator.\n"
  def trusted_analysis?(snapshot) do
    case Anchor.read_many_under(Config.root(), @evaluator) do
      {:ok, bytes} ->
        Enum.all?(@evaluator, fn path ->
          snapshot["manifest"][path] == Anchor.sha(bytes[path]) and
            @build_hashes[path] == Anchor.sha(bytes[path])
        end)

      _ ->
        false
    end
  end

  def compatible?(a, b) do
    a["codec_id"] == b["codec_id"] and a["evaluator_id"] == b["evaluator_id"] and
      a["dependency_id"] == b["dependency_id"] and a["toolchain_id"] == b["toolchain_id"]
  end

  def identity_of(snapshot, paths) do
    manifest = snapshot["manifest"] || snapshot
    Canonical.digest(Map.take(manifest, paths))
  end

  def source(id, path) when is_binary(id) and is_binary(path) do
    with {:ok, snapshot} <- load(id),
         true <- Map.has_key?(snapshot["manifest"], path),
         {:ok, bytes} <- Anchor.read_under(root(id), path) do
      {:ok, bytes}
    else
      _ -> {:error, :source_unavailable}
    end
  end

  defp valid_shape_identity_check_0?(id, raw) do
    is_map(raw) and Enum.sort(Map.keys(raw)) == Enum.sort(@keys) and raw["schema_version"] == 1 and
      raw["snapshot_id"] == id
  end

  defp valid_shape_identity_check_1?(raw) do
    is_boolean(raw["dirty"])
  end

  defp valid_shape_manifest_check_2?(raw) do
    (is_nil(raw["commit"]) or
       (is_binary(raw["commit"]) and Regex.match?(~r/\A[0-9a-f]{40}\z/, raw["commit"]))) and
      is_map(raw["manifest"]) and map_size(raw["manifest"]) in 1..1500 and
      Enum.all?(@required, &Map.has_key?(raw["manifest"], &1))
  end

  defp valid_shape_manifest_check_3?(raw) do
    Enum.all?(raw["manifest"], fn {p, h} ->
      path?(p) and is_binary(h) and Regex.match?(@hex, h)
    end)
  end
end
