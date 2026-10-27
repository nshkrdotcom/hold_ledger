defmodule HoldLedgerReview.ProofEvidence do
  @moduledoc "Conservative parser for current run_laws.py reports; never executes a checker."
  alias HoldLedgerReview.Anchor
  @checkers ["Lean paranoid", "lean4lean", "nanoda", "con-leche", "con-ron", "Lean default"]
  def sources(root) do
    patterns = [
      "lib/**/*.ex",
      "test/**/*.ex",
      "test/**/*.exs",
      "test/support/lean/**/*.lean",
      "scripts/*.py",
      "scripts/*.exs",
      "verification/*.lean",
      "verification/*.json"
    ]

    files =
      Enum.flat_map(patterns, &Path.wildcard(Path.join(root, &1)))
      |> Enum.map(&Path.relative_to(&1, root))
      |> Enum.reject(&(&1 == "verification/baseline.json"))

    Enum.uniq(
      files ++
        [
          "mix.exs",
          "mix.lock",
          "lean-toolchain",
          "verification/laws.json",
          "test/support/lean/library.json",
          ".tool-versions"
        ]
    )
    |> Enum.sort()
  end

  def manifest(root), do: Map.new(sources(root), fn p -> {p, digest_file(root, p)} end)

  def digest_file(root, p) do
    case Anchor.read_under(root, p) do
      {:ok, b} -> Anchor.sha(b)
      _ -> nil
    end
  end

  def load(_root, nil, _slugs),
    do: %{status: :not_supplied, detail: "No report supplied", report: nil}

  def load(root, path, slugs) do
    with full = Path.expand(path, root),
         relative = Path.relative_to(full, root),
         true <- String.starts_with?(relative, "tmp/verification/"),
         {:ok, bytes} <- Anchor.read_under(root, relative),
         true <- byte_size(bytes) <= 10_000_000,
         {:ok, report} <- Jason.decode(bytes) do
      %{
        status: status(root, report, slugs),
        detail: relative,
        report: report,
        report_sha256: Anchor.sha(bytes)
      }
    else
      _ -> %{status: :incomplete, detail: "Invalid or unavailable local report", report: nil}
    end
  end

  def status(root, r, slugs) when is_map(r) do
    cond do
      r["schema_version"] not in [nil, 1] or r["mode"] != "EXECUTED" or
        r["stage"] not in ["proofs", "full"] or not is_map(r["laws"]) ->
        :incomplete

      not is_map(r["source_sha256"]) or r["source_sha256"] != manifest(root) ->
        :stale

      r["source_changes_during_run"] != [] ->
        :stale

      not Enum.all?(slugs, &Map.has_key?(r["laws"], &1)) ->
        :incomplete

      Enum.any?(slugs, &(get_in(r, ["laws", &1, "passed"]) == false)) ->
        :failed

      r["complete"] != true ->
        :incomplete

      r["stage"] == "proofs" or r["cache"] != "LYNX_CACHE=0" ->
        :development_only

      r["checker_claim"] != true ->
        :incomplete

      not Enum.all?(r["laws"], fn {_slug, law} -> checked?(root, law) end) ->
        :incomplete

      r["release_complete"] == true and full_coverage?(root, r) ->
        :full_catalog_checked

      r["release_complete"] == true ->
        :incomplete

      true ->
        :selected_checked
    end
  end

  def status(_, _, _), do: :incomplete

  defp checked?(root, law) do
    law["passed"] == true and is_binary(law["source"]) and
      law["source_sha256"] == digest_file(root, law["source"]) and is_list(law["exports"]) and
      law["exports"] != [] and
      Enum.all?(law["exports"], fn export ->
        checks = export["checker_acceptance"] || %{}

        export["passed"] == true and export["allowed_axioms"] == true and
          Enum.sort(Map.keys(checks)) == Enum.sort(@checkers) and
          Enum.all?(checks, fn {_, v} -> v == true end) and
          is_list(export["axiom_list"]) and export["axiom_list"] != [] and
          Enum.all?(export["axiom_list"], &(&1 in ["propext", "Quot.sound", "Classical.choice"])) and
          is_binary(export["path"]) and
          String.starts_with?(export["path"], "tmp/verification/exports/") and
          is_integer(export["export_bytes"]) and export["export_bytes"] > 0 and
          case Anchor.read_under(root, export["path"]) do
            {:ok, bytes} ->
              byte_size(bytes) == export["export_bytes"] and
                Anchor.sha(bytes) == export["export_sha256"]

            _ ->
              false
          end
      end)
  end

  defp full_coverage?(root, r) do
    with {:ok, b} <- Anchor.read_under(root, "verification/obligations.json"),
         {:ok, inventory} <- Jason.decode(b),
         {:ok, c} <- Anchor.read_under(root, "verification/laws.json"),
         {:ok, catalog} <- Jason.decode(c) do
      required = Enum.map(inventory["obligations"], & &1["slug"]) |> Enum.sort()
      registered = Enum.map(catalog["laws"], & &1["slug"]) |> Enum.sort()
      coverage = r["obligation_coverage"] || %{}

      coverage["complete"] == true and coverage["missing"] == [] and
        coverage["required"] == required and coverage["accepted"] == required and
        required == registered and Enum.sort(Map.keys(r["laws"])) == required
    else
      _ -> false
    end
  end
end
