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
    relative = path |> Path.expand(root) |> Path.relative_to(root)

    with true <- String.starts_with?(relative, "tmp/verification/"),
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

  def status(root, report, slugs) when is_map(report) do
    with :ok <- validate_schema(report),
         :ok <- validate_sources(root, report),
         :ok <- validate_results(report, slugs) do
      checker_status(root, report)
    else
      {:error, status} -> status
    end
  rescue
    _ -> :incomplete
  end

  def status(_, _, _), do: :incomplete

  defp validate_schema(r) do
    valid =
      r["schema_version"] in [nil, 1] and r["mode"] == "EXECUTED" and
        r["stage"] in ["proofs", "full"] and is_map(r["laws"])

    if valid, do: :ok, else: {:error, :incomplete}
  end

  defp validate_sources(root, r) do
    current =
      valid_manifest?(r["source_sha256"]) and r["source_sha256"] == manifest(root) and
        r["source_changes_during_run"] == []

    if current, do: :ok, else: {:error, :stale}
  end

  defp validate_results(r, slugs) do
    cond do
      not Enum.all?(slugs, &Map.has_key?(r["laws"], &1)) -> {:error, :incomplete}
      Enum.any?(slugs, &(get_in(r, ["laws", &1, "passed"]) == false)) -> {:error, :failed}
      r["complete"] != true -> {:error, :incomplete}
      true -> :ok
    end
  end

  defp checker_status(root, r) do
    cond do
      r["stage"] == "proofs" or r["cache"] != "LYNX_CACHE=0" -> :development_only
      r["checker_claim"] != true -> :incomplete
      not checked_run?(root, r) -> :incomplete
      r["release_complete"] == true -> catalog_status(root, r)
      true -> :selected_checked
    end
  end

  defp checked_run?(root, r) do
    Enum.all?(r["laws"], fn {slug, law} -> checked?(root, slug, law) end) and
      (r["batch"] != true or r["correct_export"] == true)
  end

  defp catalog_status(root, r) do
    if full_coverage?(root, r), do: :full_catalog_checked, else: :incomplete
  end

  defp valid_manifest?(m) when is_map(m) and map_size(m) > 0 do
    Enum.all?(m, fn {path, hash} ->
      is_binary(path) and is_binary(hash) and Regex.match?(~r/\A[0-9a-f]{64}\z/, hash)
    end)
  end

  defp valid_manifest?(_), do: false

  defp registered_source?(root, slug, law) do
    with {:ok, bytes} <- Anchor.read_under(root, "verification/laws.json"),
         {:ok, catalog} <- Jason.decode(bytes),
         item when is_map(item) <- Enum.find(catalog["laws"], &(&1["slug"] == slug)) do
      item["file"] == law["source"]
    else
      _ -> false
    end
  end

  defp checked?(root, slug, law) do
    registered_source?(root, slug, law) and native_passed?(law) and
      source_matches?(root, law) and exports_checked?(root, law["exports"])
  end

  defp native_passed?(law) do
    law["passed"] == true and
      (law["native_passed"] == true or
         (law["one_law_test"] == true and law["correct_export"] == true))
  end

  defp source_matches?(root, law) do
    is_binary(law["source"]) and law["source_sha256"] == digest_file(root, law["source"])
  end

  defp exports_checked?(root, exports) when is_list(exports) and exports != [] do
    Enum.all?(exports, &export_checked?(root, &1))
  end

  defp exports_checked?(_, _), do: false

  defp export_checked?(root, export) do
    export["passed"] == true and export["allowed_axioms"] == true and
      checkers_passed?(export["checker_acceptance"]) and axioms_allowed?(export["axiom_list"]) and
      export_matches?(root, export)
  end

  defp checkers_passed?(checks) when is_map(checks) do
    Enum.sort(Map.keys(checks)) == Enum.sort(@checkers) and
      Enum.all?(checks, fn {_, v} -> v == true end)
  end

  defp checkers_passed?(_), do: false

  defp axioms_allowed?(axioms) when is_list(axioms) and axioms != [] do
    Enum.all?(axioms, &(&1 in ["propext", "Quot.sound", "Classical.choice"]))
  end

  defp axioms_allowed?(_), do: false

  defp export_matches?(root, export) do
    with path when is_binary(path) <- export["path"],
         true <- String.starts_with?(path, "tmp/verification/exports/"),
         size when is_integer(size) and size > 0 <- export["export_bytes"],
         {:ok, bytes} <- Anchor.read_under(root, path) do
      byte_size(bytes) == size and Anchor.sha(bytes) == export["export_sha256"]
    else
      _ -> false
    end
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
