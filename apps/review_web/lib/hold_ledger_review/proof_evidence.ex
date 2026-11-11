defmodule HoldLedgerReview.ProofEvidence do
  @moduledoc "Conservative parser for current run_laws.py reports; never executes a checker."
  alias HoldLedgerReview.Anchor
  @checkers ["Lean paranoid", "lean4lean", "nanoda", "con-leche", "con-ron", "Lean default"]
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
        report: report
      }
    else
      _ -> %{status: :incomplete, detail: "Invalid or unavailable local report", report: nil}
    end
  end

  def status(root, report, slugs) when is_map(report) do
    with :ok <- validate_schema(report),
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

  defp checked?(root, _slug, law) do
    native_passed?(law) and exports_checked?(root, law["exports"])
  end

  defp native_passed?(law) do
    law["passed"] == true and
      (law["native_passed"] == true or
         (law["one_law_test"] == true and law["correct_export"] == true))
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
         relative = path |> Path.expand(root) |> Path.relative_to(root),
         true <- String.starts_with?(relative, "tmp/verification/exports/"),
         {:ok, stat} <- File.stat(Path.join(root, relative)) do
      stat.type == :regular and stat.size > 0
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

      full_batch?(root, r) and coverage["complete"] == true and coverage["missing"] == [] and
        coverage["required"] == required and coverage["accepted"] == required and
        required == registered and Enum.sort(Map.keys(r["laws"])) == required
    else
      _ -> false
    end
  end

  # Selected or synthetic checked laws cannot replace a cold full-suite export.
  defp full_batch?(root, report) do
    report["batch"] == true and report["correct_export"] == true and
      get_in(report, ["execution", "exit"]) == 0 and
      get_in(report, ["execution", "timeout"]) == false and
      full_suite_export?(root, report["exports"]) and
      Enum.all?(report["laws"], fn {_slug, law} ->
        law["native_passed"] == true and law["exports"] == report["exports"]
      end)
  end

  defp full_suite_export?(root, [export] = exports) do
    export["path"] == "tmp/verification/exports/full-suite/suite.ndjson" and
      exports_checked?(root, exports)
  end

  defp full_suite_export?(_, _), do: false
end
