defmodule HoldLedgerReview.Part3ContractDelta do
  @moduledoc """
  Read-only structural inspection. AST nodes are parsed from identified source,
  never treated as independent authority. No operator edit proves weakening.
  Pointwise lost-domain and permitted-output findings are produced separately
  from *two identified runner results*, not inferred from this diff.
  """
  alias HoldLedgerReview.{Anchor, Canonical, Part3Snapshots}
  alias HoldLedgerReview.Claims.{Compiler, Source}

  @max_changes 300
  @max_preview 1800

  def compare(a, b) do
    if Part3Snapshots.compatible?(a, b) do
      changes =
        (Map.keys(a["manifest"]) ++ Map.keys(b["manifest"]))
        |> Enum.uniq()
        |> Enum.sort()
        |> Enum.filter(&(a["manifest"][&1] != b["manifest"][&1]))

      if length(changes) > @max_changes do
        {:error, :too_many_changes_for_inspection}
      else
        {:ok, Enum.map(changes, &entry(&1, a, b))}
      end
    else
      {:error, :unsupported_representation_or_evaluator_mapping}
    end
  end

  defp entry(path, a, b) do
    old = bytes(a, path)
    proposed = bytes(b, path)
    kind = category(path)
    ast = if kind == "claim", do: claim_delta(path, old, proposed, a, b), else: %{"analysis" => "not_supported", "reason" => "No audited semantic comparison for this source kind"}
    %{
      "id" => "change." <> String.slice(Canonical.digest(%{"path" => path, "a" => a["snapshot_id"], "b" => b["snapshot_id"]}), 0, 24),
      "path" => path, "kind" => kind, "evidence_level" => "structural_edit",
      "baseline_sha256" => a["manifest"][path], "proposal_sha256" => b["manifest"][path],
      "baseline_excerpt" => String.slice(old || "(not present)", 0, @max_preview),
      "proposal_excerpt" => String.slice(proposed || "(not present)", 0, @max_preview),
      "claim" => ast, "semantic_relation" => "unresolved"
    }
  end

  defp bytes(snapshot, path) do
    case Map.has_key?(snapshot["manifest"], path) && Anchor.read_under(Part3Snapshots.root(snapshot["snapshot_id"]), path) do
      {:ok, data} -> data
      _ -> nil
    end
  end

  defp claim_delta(path, old, proposed, a, b) when is_binary(old) and is_binary(proposed) do
    with {:ok, left} <- declaration(a, path), {:ok, right} <- declaration(b, path),
         {:ok, left} <- Compiler.prepare(left), {:ok, right} <- Compiler.prepare(right) do
      %{"analysis" => "supported_structural_ast", "parser_id" => Source.version(),
        "baseline" => %{"requires" => Macro.to_string(left.normalized_requires), "expects" => Macro.to_string(left.normalized_expects), "formals" => Enum.map(left.formals, &Atom.to_string/1)},
        "proposal" => %{"requires" => Macro.to_string(right.normalized_requires), "expects" => Macro.to_string(right.normalized_expects), "formals" => Enum.map(right.formals, &Atom.to_string/1)},
        "changed" => %{"conditions" => Macro.to_string(left.normalized_requires) != Macro.to_string(right.normalized_requires), "promises" => Macro.to_string(left.normalized_expects) != Macro.to_string(right.normalized_expects)},
        "called_helpers" => "source-context inspection required; see helper/source changes"}
    else
      _ -> %{"analysis" => "not_supported", "reason" => "No common audited declaration or supported AST subset"}
    end
  end

  defp claim_delta(_, _, _, _, _), do: %{"analysis" => "not_supported", "reason" => "Claim added or removed; manual inventory review required"}

  defp declaration(snapshot, path) do
    with {:ok, raw} <- Anchor.read_under(Part3Snapshots.root(snapshot["snapshot_id"]), "verification/laws.json"),
         {:ok, %{"laws" => laws}} <- Jason.decode(raw),
         law when is_map(law) <- Enum.find(laws, &(&1["file"] == path)),
         {:ok, declaration} <- Source.declaration(Part3Snapshots.root(snapshot["snapshot_id"]), law) do
      {:ok, declaration}
    else
      _ -> {:error, :unsupported_declaration}
    end
  end

  defp category("test/laws/" <> _), do: "claim"
  defp category("lib/hold_ledger/" <> _), do: "called_definition_or_behavior"
  defp category("test/support/lean/" <> _), do: "lean_declaration_or_dependency"
  defp category("verification/" <> _), do: "obligation_or_inventory"
  defp category("guides/specification.md"), do: "governing_policy"
  defp category("test/support/proof_case.ex"), do: "translation_or_elaboration"
  defp category("apps/review_web/" <> _), do: "review_infrastructure"
  defp category(_), do: "source_or_toolchain"
end
