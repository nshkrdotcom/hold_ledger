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

    ast =
      if kind == "claim",
        do: claim_delta(path, old, proposed, a, b),
        else: %{
          "analysis" => "not_supported",
          "reason" => "No audited semantic comparison for this source kind"
        }

    %{
      "id" =>
        "change." <>
          String.slice(
            Canonical.digest(%{"path" => path, "a" => a["snapshot_id"], "b" => b["snapshot_id"]}),
            0,
            24
          ),
      "path" => path,
      "kind" => kind,
      "evidence_level" => "structural_edit",
      "baseline_sha256" => a["manifest"][path],
      "proposal_sha256" => b["manifest"][path],
      "baseline_excerpt" => excerpt(old, proposed),
      "proposal_excerpt" => excerpt(proposed, old),
      "claim" => ast,
      "semantic_relation" => "unresolved"
    }
  end

  defp excerpt(nil, _), do: "(not present)"

  defp excerpt(bytes, other) do
    lines = String.split(bytes, "\n")
    peer = String.split(other || "", "\n")
    first = Enum.zip(lines, peer) |> Enum.take_while(fn {a, b} -> a == b end) |> length()
    start = max(0, first - 3)
    body = lines |> Enum.drop(start) |> Enum.join("\n") |> String.slice(0, @max_preview)
    "From line #{start + 1} (bounded excerpt):\n" <> body
  end

  defp bytes(snapshot, path) do
    case Map.has_key?(snapshot["manifest"], path) &&
           Anchor.read_under(Part3Snapshots.root(snapshot["snapshot_id"]), path) do
      {:ok, data} -> data
      _ -> nil
    end
  end

  defp claim_delta(path, old, proposed, a, b) when is_binary(old) and is_binary(proposed) do
    with {:ok, left} <- declaration(a, path),
         {:ok, right} <- declaration(b, path),
         {:ok, left} <- Compiler.prepare(left),
         {:ok, right} <- Compiler.prepare(right),
         true <-
           left.slug == right.slug and left.arity == right.arity and
             left.formals == right.formals do
      %{
        "analysis" => "supported_structural_ast",
        "parser_id" => Source.version(),
        "baseline" => %{
          "requires" => Macro.to_string(left.normalized_requires),
          "expects" => Macro.to_string(left.normalized_expects),
          "formals" => Enum.map(left.formals, &Atom.to_string/1)
        },
        "proposal" => %{
          "requires" => Macro.to_string(right.normalized_requires),
          "expects" => Macro.to_string(right.normalized_expects),
          "formals" => Enum.map(right.formals, &Atom.to_string/1)
        },
        "changed" => %{
          "conditions" =>
            Macro.to_string(left.normalized_requires) !=
              Macro.to_string(right.normalized_requires),
          "promises" =>
            Macro.to_string(left.normalized_expects) != Macro.to_string(right.normalized_expects)
        },
        "called_helpers" => "source-context inspection required; see helper/source changes"
      }
    else
      _ ->
        %{
          "analysis" => "not_supported",
          "reason" => "No common audited declaration or supported AST subset"
        }
    end
  end

  defp claim_delta(_, _, _, _, _),
    do: %{
      "analysis" => "not_supported",
      "reason" => "Claim added or removed; manual inventory review required"
    }

  defp declaration(snapshot, path) do
    with {:ok, raw} <-
           Anchor.read_under(
             Part3Snapshots.root(snapshot["snapshot_id"]),
             "verification/laws.json"
           ),
         {:ok, %{"laws" => laws}} <- Jason.decode(raw),
         law when is_map(law) <- Enum.find(laws, &(&1["file"] == path)),
         {:ok, declaration} <-
           Source.declaration(Part3Snapshots.root(snapshot["snapshot_id"]), law) do
      {:ok, declaration}
    else
      _ -> {:error, :unsupported_declaration}
    end
  end

  @doc """
  Source-verified *presentation*, not persisted comparison or interpretation.
  Normalized AST text is explicitly separate from byte-faithful source context.
  A missing, renamed or unsupported declaration remains unresolved.
  """
  def presentation(package) do
    with {:ok, a} <- Part3Snapshots.load(package["baseline"]["snapshot_id"]),
         {:ok, b} <- Part3Snapshots.load(package["proposal"]["snapshot_id"]),
         true <- a == package["baseline"] and b == package["proposal"] do
      {:ok,
       Map.new(package["source_changes"], fn change ->
         {change["id"], present_change(change, a, b)}
       end)}
    else
      _ -> {:error, :unavailable_or_stale_source}
    end
  end

  defp present_change(change, a, b) do
    path = change["path"]
    left = bytes(a, path)
    right = bytes(b, path)

    if (is_binary(left) or is_nil(a["manifest"][path])) and
         (is_binary(right) or is_nil(b["manifest"][path])) and
         (is_nil(left) or Anchor.sha(left) == change["baseline_sha256"]) and
         (is_nil(right) or Anchor.sha(right) == change["proposal_sha256"]) do
      %{
        "status" => "source_hash_matched_structural_only",
        "baseline" => source_window(left, right),
        "proposal" => source_window(right, left),
        "declarations" => declaration_spans(change, a, b),
        "expressions" => expression_diffs(change["claim"])
      }
    else
      %{"status" => "unavailable_or_stale_source", "expressions" => []}
    end
  end

  defp source_window(nil, _), do: %{"start_line" => nil, "text" => "(not present)"}

  defp source_window(contents, other) do
    lines = String.split(contents, "\n")
    peers = String.split(other || "", "\n")
    first = Enum.zip(lines, peers) |> Enum.take_while(fn {l, r} -> l == r end) |> length()
    start = max(0, first - 3)
    fragment = lines |> Enum.drop(start) |> Enum.take(18) |> Enum.join("\n")

    %{
      "start_line" => start + 1,
      "end_line" => min(length(lines), start + 18),
      "text" => String.slice(fragment, 0, 2500),
      "bounded" => start > 0 or start + 18 < length(lines) or String.length(fragment) > 2500
    }
  end

  defp declaration_spans(
         %{"kind" => "claim", "claim" => %{"analysis" => "supported_structural_ast"}} = change,
         a,
         b
       ) do
    Enum.map([{"baseline", a}, {"proposal", b}], fn {side, snapshot} ->
      span =
        case declaration(snapshot, change["path"]) do
          {:ok, d} ->
            %{
              "path" => d.source_file,
              "sha256" => d.source_sha256,
              "start_line" => d.source_line,
              "end_line" => d.source_end_line,
              "kind" => "parser_located_law_declaration"
            }

          _ ->
            %{"kind" => "declaration_span_unavailable"}
        end

      Map.put(span, "side", side)
    end)
  end

  defp declaration_spans(_, _, _), do: []

  defp expression_diffs(%{"analysis" => "supported_structural_ast"} = claim) do
    Enum.map([{"requires", "condition"}, {"expects", "promise"}], fn {field, label} ->
      old = claim["baseline"][field]
      new = claim["proposal"][field]

      if is_binary(old) and is_binary(new) and String.length(old) <= 4000 and
           String.length(new) <= 4000 do
        %{
          "field" => field,
          "label" => label,
          "status" => if(old == new, do: "normalized_unchanged", else: "normalized_changed"),
          "baseline" => normalized_chunks(old, new, :baseline),
          "proposal" => normalized_chunks(old, new, :proposal)
        }
      else
        %{
          "field" => field,
          "label" => label,
          "status" => "normalized_highlight_unavailable_or_oversized",
          "baseline" => [],
          "proposal" => []
        }
      end
    end)
  end

  defp expression_diffs(_), do: []

  defp normalized_chunks(left, right, side) do
    String.myers_difference(left, right)
    |> Enum.filter(fn {tag, _} ->
      tag == :eq or (tag == :del and side == :baseline) or (tag == :ins and side == :proposal)
    end)
    |> Enum.map(fn {tag, text} ->
      %{"kind" => Atom.to_string(tag), "text" => text}
    end)
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
