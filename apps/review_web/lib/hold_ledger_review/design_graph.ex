defmodule HoldLedgerReview.DesignGraph do
  @moduledoc """
  Checkout-anchored policy → reducer/oracle → law → predicate/Lean map.
  Edges distinguish exact source relationships from navigational suggestions.
  Nothing inferred here is a proof of coverage or policy adequacy.
  """
  alias HoldLedgerReview.{Anchor, Claims, Config}

  @policy_path "guides/specification.md"
  @operations ~w(request dispatch timeout restart retry processor_result transport_ack void void_confirmed)
  @boundaries [
    {"processor", "Processor deduplication, truthful terminal response and permanent fencing",
     "guides/processors.md"},
    {"journal", "Synced journal input and replay fidelity", "guides/runtime.md"},
    {"environment", "Delivery, remote capacity and adapter assumptions",
     "guides/specification_assurance.md"}
  ]

  def build(root \\ Config.root()) do
    with :ok <- Claims.freshness(root),
         {:ok, catalog} <- Claims.catalog(),
         {:ok, spec} <- Anchor.read_under(root, @policy_path) do
      generation = Claims.snapshot()
      rows = policy_rows(spec)

      lean_paths =
        Path.wildcard(Path.join(root, "test/support/lean/*.lean"))
        |> Enum.map(&Path.relative_to(&1, root))

      sources =
        Enum.uniq(
          lean_paths ++
            [@policy_path, "lib/hold_ledger/ledger.ex", "lib/hold_ledger/spec.ex"] ++
            Enum.map(catalog, & &1["file"]) ++
            ["verification/laws.json", "verification/obligations.json"] ++
            Enum.map(@boundaries, &elem(&1, 2))
        )

      with {:ok, excerpts} <- excerpts(root, sources) do
        assemble(root, generation, rows, catalog, excerpts)
      end
    end
  end

  defp assemble(root, generation, rows, catalog, excerpts) do
    source_ids = Map.new(excerpts, &{&1["path"], &1["id"]})

    policies =
      Enum.map(rows, &policy_node(&1, source_ids))

    extras =
      for {id, title} <- [
            {"policy.replay", "Replay and restart are separate guarantees"},
            {"policy.terminal_fencing", "Terminal fencing is an external premise"},
            {"policy.composite_recovery", "Composite pending-void recovery"}
          ],
          do: node(id, "policy_row", title, [@policy_path], source_ids)

    reducers =
      Enum.map(
        Enum.uniq(@operations ++ reducer_operations(generation)),
        &node(
          "reducer." <> &1,
          "reducer",
          "Ledger." <> &1,
          ["lib/hold_ledger/ledger.ex"],
          source_ids
        )
      )

    specs =
      (spec_predicates(generation) ++ ["expected_step", "valid?"])
      |> Enum.uniq()
      |> Enum.sort()

    spec_nodes =
      Enum.map(
        specs,
        &node("spec." <> &1, "spec", "Spec." <> &1, ["lib/hold_ledger/spec.ex"], source_ids)
      )

    laws = Enum.map(catalog, &law_node(&1, source_ids, excerpts, root))

    boundaries =
      Enum.map(@boundaries, &boundary_node(&1, source_ids))

    edges =
      policy_edges(rows, catalog, generation) ++
        law_edges(generation, catalog) ++
        [
          edge(
            "policy.replay",
            "reducer.restart",
            "documented_operation",
            "source_explicit",
            "Replay section names restart"
          ),
          edge(
            "policy.composite_recovery",
            "boundary.journal",
            "operational_dependency",
            "source_explicit",
            "Recovery section requires a synced journal"
          ),
          edge(
            "policy.terminal_fencing",
            "boundary.processor",
            "operational_dependency",
            "source_explicit",
            "Specification names remote permanent fencing"
          ),
          edge(
            "policy.terminal_fencing",
            "boundary.environment",
            "operational_dependency",
            "inferred",
            "Deployment-specific premise; review externally"
          )
        ]

    {:ok,
     %{
       "nodes" => policies ++ extras ++ reducers ++ spec_nodes ++ laws ++ boundaries,
       "edges" => Enum.uniq(edges),
       "excerpts" => excerpts
     }}
  end

  defp policy_node(%{id: id, title: title}, source_ids),
    do: node(id, "policy_row", title, [@policy_path], source_ids)

  defp boundary_node({id, label, path}, source_ids),
    do: node("boundary." <> id, "boundary", label, [path], source_ids)

  defp law_node(entry, source_ids, excerpts, root) do
    kind = if entry["kind"] == "lean", do: "lean", else: "law"
    title = entry["slug"] <> " · " <> (entry["purpose"] || "registered native obligation")

    node(
      "law." <> entry["slug"],
      kind,
      String.slice(title, 0, 600),
      Enum.uniq(
        [entry["file"], "verification/laws.json", "verification/obligations.json"] ++
          proof_sources(entry, excerpts, root)
      ),
      source_ids
    )
  end

  def policy_rows(text) do
    text
    |> String.split("\n")
    |> Enum.filter(&String.starts_with?(&1, "|"))
    |> Enum.reject(&(String.contains?(&1, "---") or String.starts_with?(&1, "| Event")))
    |> Enum.filter(&(length(String.split(&1, "|")) == 6))
    |> Enum.with_index(1)
    |> Enum.map(fn {line, index} ->
      [event, condition, result, _effects] =
        line |> String.split("|") |> Enum.slice(1, 4) |> Enum.map(&String.trim/1)

      operation = operation_for(event, index)

      %{
        id: "policy.events." <> String.pad_leading(Integer.to_string(index), 2, "0"),
        title: String.slice("#{event} · #{condition} → #{result}", 0, 600),
        operation: operation,
        description: line
      }
    end)
  end

  def operation_for(event, index) do
    operations = Enum.sort_by(@operations, &(-String.length(&1)))
    Enum.find(operations, &String.contains?(event, &1)) || request_row(event, index)
  end

  defp request_row(event, index) do
    if String.starts_with?(event, "Same key") or String.starts_with?(event, "Fresh request") or
         index in 2..5, do: "request", else: nil
  end

  defp excerpts(root, paths) do
    Enum.reduce_while(paths, {:ok, []}, fn path, {:ok, acc} ->
      case Anchor.read_under(root, path) do
        {:ok, bytes} ->
          # The source hash always describes the entire file, even when the readable excerpt is capped.
          item = %{
            "id" => "source." <> String.slice(Anchor.sha(path), 0, 20),
            "path" => path,
            "sha256" => Anchor.sha(bytes),
            "text" => excerpt(bytes)
          }

          {:cont, {:ok, [item | acc]}}

        {:error, _} = error ->
          {:halt, error}
      end
    end)
    |> case do
      {:ok, list} -> {:ok, Enum.reverse(list)}
      error -> error
    end
  end

  defp excerpt(bytes) when byte_size(bytes) <= 19_500, do: bytes
  defp excerpt(bytes), do: valid_prefix(binary_part(bytes, 0, 19_500))

  defp valid_prefix(bytes) do
    if String.valid?(bytes),
      do: bytes,
      else: valid_prefix(binary_part(bytes, 0, byte_size(bytes) - 1))
  end

  defp node(id, kind, title, paths, source_ids),
    do: %{
      "id" => id,
      "kind" => kind,
      "title" => title,
      "source_ids" => Enum.map(paths, &Map.fetch!(source_ids, &1))
    }

  defp edge(a, b, kind, provenance, reason),
    do: %{
      "from_id" => a,
      "to_id" => b,
      "kind" => kind,
      "provenance" => provenance,
      "reason" => reason
    }

  defp policy_edges(rows, catalog, generation) do
    Enum.flat_map(rows, fn row ->
      base =
        if row.operation do
          [
            edge(
              row.id,
              "reducer." <> row.operation,
              "documented_operation",
              "source_explicit",
              "Event table explicitly names this operation"
            )
          ]
        else
          []
        end

      spec = [
        edge(
          row.id,
          "spec.expected_step",
          "reference_model",
          "inferred",
          "Specification describes the same behavior; this is not an entailment"
        )
      ]

      matches =
        Enum.filter(catalog, fn law ->
          operations = ledger_calls(Map.get(generation.law_details, law["slug"]))
          row.operation in operations or "step" in operations
        end)

      suggestions =
        Enum.map(matches, fn law ->
          edge(
            row.id,
            "law." <> law["slug"],
            "candidate_relevance",
            "inferred",
            "Parsed reducer calls suggest relevance to #{row.operation}; pointwise applicability must be checked"
          )
        end)

      base ++ spec ++ suggestions
    end)
  end

  defp law_edges(generation, catalog) do
    Enum.flat_map(catalog, fn law ->
      slug = law["slug"]

      op_edges =
        Enum.map(ledger_calls(Map.get(generation.law_details, slug)), fn operation ->
          edge(
            "law." <> slug,
            "reducer." <> operation,
            "parsed_expression",
            "source_explicit",
            "Reducer call appears in original expects AST"
          )
        end)

      predicate_edges =
        case Map.get(generation.law_details, slug) do
          %{requires: req, expects: exp} ->
            (Macro.to_string(req) <> " " <> Macro.to_string(exp))
            |> then(&Regex.scan(~r/\bSpec\.([a-z_]+[!?]?)/, &1, capture: :all_but_first))
            |> List.flatten()
            |> Enum.uniq()
            |> Enum.map(
              &edge(
                "law." <> slug,
                "spec." <> &1,
                "parsed_expression",
                "source_explicit",
                "Predicate call appears in original law AST"
              )
            )

          _ ->
            []
        end

      op_edges ++ predicate_edges
    end)
  end

  defp reducer_operations(generation),
    do: generation.law_details |> Map.values() |> Enum.flat_map(&ledger_calls/1) |> Enum.uniq()

  defp ledger_calls(%{expects: expects}) do
    {_, calls} =
      Macro.prewalk(expects, [], fn
        {{:., _, [{:__aliases__, _, module}, operation]}, _, _} = ast, acc
        when module in [[:Ledger], [:HoldLedger, :Ledger]] ->
          {ast, [Atom.to_string(operation) | acc]}

        ast, acc ->
          {ast, acc}
      end)

    Enum.uniq(calls)
  end

  defp ledger_calls(_), do: []

  defp proof_sources(%{"kind" => "lean"}, _excerpts, _root), do: []

  defp proof_sources(entry, excerpts, root) do
    declaration = "theorem «#{entry["slug"]}/#{entry["arity"]}»"

    excerpts
    |> Enum.filter(
      &(String.ends_with?(&1["path"], ".lean") and source_declares?(root, &1["path"], declaration))
    )
    |> Enum.map(& &1["path"])
  end

  defp source_declares?(root, path, declaration) do
    with {:ok, bytes} <- Anchor.read_under(root, path), do: String.contains?(bytes, declaration)
  end

  defp spec_predicates(generation) do
    generation.law_details
    |> Map.values()
    |> Enum.flat_map(fn
      %{requires: req, expects: exp} ->
        Regex.scan(
          ~r/\bSpec\.([a-z_]+[!?]?)/,
          Macro.to_string(req) <> " " <> Macro.to_string(exp),
          capture: :all_but_first
        )
        |> List.flatten()

      _ ->
        []
    end)
  end
end
