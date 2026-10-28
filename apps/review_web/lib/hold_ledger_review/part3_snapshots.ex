defmodule HoldLedgerReview.Part3Snapshots do
  @moduledoc """
  Reads operator-staged, immutable local source snapshots. The browser can only
  choose 64-hex identities previously staged by the terminal tool. These trees
  are trusted executable code, not a sandbox for arbitrary uploads.
  """
  alias HoldLedgerReview.{Anchor, Canonical, Claims, Config}

  @identity_keys ~w(schema_version commit dirty manifest)
  @keys @identity_keys ++ ["snapshot_id"]
  @required ~w(mix.exs mix.lock .tool-versions lean-toolchain verification/laws.json verification/obligations.json lib/hold_ledger/ledger.ex lib/hold_ledger/spec.ex apps/review_web/mix.exs apps/review_web/mix.lock apps/review_web/lib/hold_ledger_review/term_codec.ex)
  @evaluator ~w(apps/review_web/lib/hold_ledger_review/adversarial.ex apps/review_web/lib/hold_ledger_review/claim_probe.ex apps/review_web/lib/hold_ledger_review/claims.ex apps/review_web/lib/hold_ledger_review/claims/source.ex apps/review_web/lib/hold_ledger_review/claims/compiler.ex apps/review_web/lib/hold_ledger_review/term_codec.ex apps/review_web/lib/hold_ledger_review/canonical.ex apps/review_web/lib/hold_ledger_review/config.ex apps/review_web/lib/hold_ledger_review/anchor.ex apps/review_web/scripts/part3_execution.exs apps/review_web/scripts/part3_worker.py scripts/local_run.py apps/review_web/lib/hold_ledger_review/part3_snapshots.ex apps/review_web/lib/hold_ledger_review/part3_result.ex apps/review_web/lib/hold_ledger_review/part3_contract_delta.ex apps/review_web/lib/hold_ledger_review/part3_diagnostics.ex apps/review_web/lib/hold_ledger_review/part3_boundary_search.ex apps/review_web/lib/hold_ledger_review/part3_package.ex apps/review_web/lib/hold_ledger_review/part3_verification.ex apps/review_web/lib/hold_ledger_review/part3_proof_inspector.ex apps/review_web/lib/hold_ledger_review/part3_editor.ex)
  @hex ~r/\A[0-9a-f]{64}\z/

  def evaluator_paths, do: @evaluator

  def directory, do: Path.join(Config.root(), "tmp/review_studio/snapshots")
  def root(id) when is_binary(id), do: Path.join(directory(), id)
  def identities, do: Path.wildcard(Path.join(directory(), "[0-9a-f]*")) |> Enum.map(&Path.basename/1) |> Enum.filter(&Regex.match?(@hex, &1)) |> Enum.sort()

  def load(id) when is_binary(id) do
    with true <- Regex.match?(@hex, id),
         {:ok, bytes} <- Anchor.read_under(root(id), ".part3-snapshot.json"),
         true <- byte_size(bytes) <= 200_000,
         {:ok, raw} <- Jason.decode(bytes),
         true <- valid_shape?(raw, id),
         :ok <- verify_files(id, raw["manifest"]),
         :ok <- trusted_dependencies(raw["manifest"]) do
      {:ok, raw |> Map.put("toolchain_id", identity_of(raw, ~w(.tool-versions lean-toolchain))) |> Map.put("dependency_id", identity_of(raw, ~w(mix.lock apps/review_web/mix.lock))) |> Map.put("codec_id", raw["manifest"]["apps/review_web/lib/hold_ledger_review/term_codec.ex"]) |> Map.put("evaluator_id", identity_of(raw, @evaluator))}
    else
      _ -> {:error, :invalid_or_stale_snapshot}
    end
  end

  def load(_), do: {:error, :invalid_or_stale_snapshot}

  defp valid_shape?(raw, id) do
    is_map(raw) and Enum.sort(Map.keys(raw)) == Enum.sort(@keys) and
      raw["schema_version"] == 1 and raw["snapshot_id"] == id and
      is_boolean(raw["dirty"]) and
      (is_nil(raw["commit"]) or (is_binary(raw["commit"]) and Regex.match?(~r/\A[0-9a-f]{40}\z/, raw["commit"]))) and
      is_map(raw["manifest"]) and map_size(raw["manifest"]) in 1..1500 and
      Enum.all?(@required, &Map.has_key?(raw["manifest"], &1)) and
      Enum.all?(raw["manifest"], fn {p, h} -> path?(p) and is_binary(h) and Regex.match?(@hex, h) end) and
      Canonical.digest(Map.take(raw, @identity_keys)) == id
  end

  defp path?(p) when is_binary(p) do
    byte_size(p) in 1..240 and Path.type(p) == :relative and
      not Enum.any?(Path.split(p), &(&1 in ["..", ".", ".git", "tmp", "deps", "_build"])) and
      not String.contains?(p, "\\")
  end

  defp path?(_), do: false

  defp verify_files(id, manifest) do
    case Anchor.read_many_under(root(id), Map.keys(manifest)) do
      {:ok, files} ->
        if Enum.all?(manifest, fn {path, expected} -> Anchor.sha(files[path]) == expected end) and
             exact_source_inventory?(id, manifest), do: :ok, else: {:error, :snapshot_drift}
      _ -> {:error, :snapshot_drift}
    end
  end

  # Unmanifested executable source files cannot quietly appear after staging.
  # Only explicit ignored build/output directories are exempt; their pinned
  # dependencies remain part of the operator-trust assumption, not a sandbox.
  defp exact_source_inventory?(id, manifest) do
    expected = Map.keys(manifest) |> MapSet.new() |> MapSet.put(".part3-snapshot.json")
    Path.wildcard(Path.join(root(id), "**/*"), match_dot: true)
    |> Enum.reduce_while(MapSet.new(), fn full, names ->
      relative = Path.relative_to(full, root(id))
      parts = Path.split(relative)
      if Enum.any?(parts, &(&1 in ["tmp", "_build", "deps", "node_modules", ".venv"])) do
        {:cont, names}
      else
        case File.lstat(full) do
          {:ok, %{type: :directory}} -> {:cont, names}
          {:ok, %{type: :regular}} -> {:cont, MapSet.put(names, relative)}
          _ -> {:halt, :invalid}
        end
      end
    end)
    |> then(&(&1 == expected))
  end

  defp trusted_dependencies(manifest) do
    # Different locks/toolchain require explicit provisioning and a distinct
    # trust review, not implicit dependency resolution from a web request.
    paths = ~w(mix.lock apps/review_web/mix.lock .tool-versions lean-toolchain)
    if Enum.all?(paths, fn p -> Anchor.read_under(Config.root(), p) |> case do
      {:ok, data} -> Anchor.sha(data) == manifest[p]
      _ -> false
    end end), do: :ok, else: {:error, :untrusted_dependencies}
  end

  @doc """
  The selected parser, protocol, runner and codec source must also match the
  currently trusted Phoenix installation before any new evidence is created.
  Comparing two old snapshots is not license to use an unrelated live validator.
  """
  def trusted_analysis?(snapshot) do
    case Anchor.read_many_under(Config.root(), @evaluator) do
      {:ok, bytes} ->
        Enum.all?(@evaluator, fn path ->
          snapshot["manifest"][path] == Anchor.sha(bytes[path])
        end)
      _ -> false
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
end
