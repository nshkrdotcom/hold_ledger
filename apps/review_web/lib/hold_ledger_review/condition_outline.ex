defmodule HoldLedgerReview.ConditionOutline do
  @moduledoc """
  Source-reviewed presentation of *observed* predicate nodes, not another
  evaluator. Groups are admitted only when their source digest is the reviewed
  digest and their expressions occur in that source. Every displayed address is
  taken from the original observation tree; the complete tree remains intact.
  """

  @states ~w(true false not_evaluated unavailable)

  @doc "Check optional grouping descriptions against the exact reviewed source."
  def validate(groups, bytes, digests, reviewed)
      when is_list(groups) and is_map(reviewed) do
    available =
      groups
      |> Enum.map(& &1["source_path"])
      |> Enum.uniq()
      |> Map.new(&{&1, reviewed_terms(&1, bytes, digests, reviewed)})

    Enum.filter(groups, &valid_group?(&1, available))
  end

  def validate(_, _, _, _), do: []

  defp reviewed_terms(path, bytes, digests, reviewed) do
    if reviewed_source?(path, bytes, digests, reviewed),
      do: source_terms(bytes[path]),
      else: MapSet.new()
  end

  defp source_terms(bytes) do
    case Code.string_to_quoted(bytes) do
      {:ok, ast} ->
        {_ast, terms} =
          Macro.prewalk(ast, MapSet.new(), fn node, seen ->
            {node, MapSet.put(seen, expression_key(node, false))}
          end)

        terms

      _ ->
        MapSet.new()
    end
  end

  defp reviewed_source?(path, bytes, digests, reviewed) do
    is_binary(path) and Map.has_key?(reviewed, path) and
      Map.has_key?(digests, path) and reviewed[path] == digests[path] and
      is_binary(Map.get(bytes, path))
  end

  defp valid_group?(group, available) do
    valid =
      is_binary(group["id"]) and is_binary(group["title"]) and
        group["phase"] in ~w(requires expects) and is_binary(group["source_path"])

    valid and
      valid_expressions?(group["expressions"], available[group["source_path"]] || MapSet.new())
  end

  defp valid_expressions?(expressions, terms) when is_list(expressions) and expressions != [],
    do: Enum.all?(expressions, &source_expression?(&1, terms))

  defp valid_expressions?(_, _), do: false

  defp source_expression?(expression, terms) when is_binary(expression) do
    case Code.string_to_quoted(expression) do
      {:ok, ast} -> MapSet.member?(terms, expression_key(ast, false))
      _ -> false
    end
  end

  defp source_expression?(_, _), do: false

  @doc "Project one phase and binding without altering the observed tree."
  def project(node, phase, groups, changed_paths \\ [])

  def project(nil, _phase, _groups, _changed_paths), do: []

  def project(node, phase, groups, changed_paths) when is_map(node) do
    observed = paths(node, [])
    source_phase = if phase == "requires", do: "requires", else: "expects"

    curated =
      Enum.flat_map(groups, &curated_group(&1, source_phase, phase, observed, changed_paths))

    curated =
      if curated == [],
        do: [outline_group("generic", generic_title(phase), conjuncts(node, []))],
        else: curated

    unseen =
      Enum.filter(observed, fn item ->
        item.node["status"] == "not_evaluated" and
          not Enum.any?(curated, fn group ->
            Enum.any?(group.observations, &(&1.path == item.path))
          end)
      end)

    # A non-evaluated ancestor already represents all of its descendants.
    # Count and display only the outermost skipped branches, with full paths
    # still accessible in the complete observed tree.
    skipped_roots =
      Enum.reject(unseen, fn row ->
        Enum.any?(unseen, fn ancestor ->
          length(ancestor.path) < length(row.path) and
            Enum.take(row.path, length(ancestor.path)) == ancestor.path
        end)
      end)

    skipped =
      if skipped_roots == [],
        do: [],
        else: [
          outline_group("skipped", "Short-circuited branches", skipped_roots,
            collapse_unevaluated: true
          )
        ]

    curated ++ skipped
  end

  defp curated_group(group, source_phase, phase, observed, changed_paths) do
    if group["phase"] == source_phase do
      keys = MapSet.new(Enum.map(group["expressions"], &parsed_key(&1, phase == "candidate")))

      rows =
        Enum.filter(observed, &MapSet.member?(keys, parsed_key(&1.node["expression"], false)))

      group_rows(group, rows, changed_paths)
    else
      []
    end
  end

  defp group_rows(_, [], _), do: []

  defp group_rows(group, rows, changed_paths),
    do: [
      outline_group(group["id"], group["title"], rows,
        changed_source: group["source_path"] in changed_paths,
        source_path: group["source_path"],
        collapse_satisfied: group["collapse_satisfied"] == true
      )
    ]

  defp parsed_key(expression, candidate?) do
    case Code.string_to_quoted(expression) do
      {:ok, ast} -> expression_key(ast, candidate?)
      _ -> nil
    end
  end

  # Match the original compiler's known source aliases and output substitution.
  # No expression is evaluated here; all values and addresses remain observed.
  defp expression_key(ast, candidate?) do
    ast
    |> Macro.prewalk(fn
      {:__aliases__, meta, [:Spec]} -> {:__aliases__, meta, [:HoldLedger, :Spec]}
      {:__aliases__, meta, [:Ledger]} -> {:__aliases__, meta, [:HoldLedger, :Ledger]}
      node -> node
    end)
    |> Macro.postwalk(&candidate_call(&1, candidate?))
    |> Macro.to_string()
  end

  defp candidate_call(
         {{:., _, [{:__aliases__, _, [:HoldLedger, :Ledger]}, operation]}, _, _},
         true
       )
       when operation in [:step, :request, :timeout, :void], do: {:candidate_output, [], nil}

  defp candidate_call(node, _), do: node

  @doc "Encode presentation records for the strict, shared JSON command interface."
  def encode(groups) do
    Enum.map(groups, fn group ->
      %{
        "id" => group.id,
        "title" => group.title,
        "observations" => Enum.map(group.observations, &encode_observation/1),
        "counts" => group.counts,
        "changed_source" => group.changed_source?,
        "source_path" => group.source_path,
        "collapsed" => group.collapsed?,
        "attention" => group.attention?
      }
    end)
  end

  defp encode_observation(row) do
    %{
      "node" => row.node,
      "path" => row.path,
      "state" => row.state,
      "context" => Enum.map(row.context, &encode_context/1)
    }
  end

  defp encode_context(context) do
    %{
      "operator" => Atom.to_string(context.operator),
      "expression" => context.expression,
      "path" => context.path,
      "branch" => context.branch
    }
  end

  @doc "A count is over the listed observed nodes only, never inferred AST leaves."
  def state(node) do
    cond do
      node["status"] == "not_evaluated" -> "not_evaluated"
      node["status"] in ["error", "unavailable"] -> "unavailable"
      node["value"] === true -> "true"
      node["value"] === false -> "false"
      true -> "unavailable"
    end
  end

  defp outline_group(id, title, rows, opts \\ []) do
    observations = Enum.map(rows, &Map.put(&1, :state, state(&1.node)))
    counts = Map.new(@states, &{&1, Enum.count(observations, fn row -> row.state == &1 end)})
    changed = Keyword.get(opts, :changed_source, false)
    collapse = Keyword.get(opts, :collapse_satisfied, false)

    %{
      id: id,
      title: title,
      observations: observations,
      counts: counts,
      changed_source?: changed,
      source_path: Keyword.get(opts, :source_path),
      collapsed?:
        (collapse and !changed and counts["true"] == length(rows)) or
          Keyword.get(opts, :collapse_unevaluated, false),
      attention?:
        changed or counts["false"] > 0 or counts["not_evaluated"] > 0 or
          counts["unavailable"] > 0
    }
  end

  defp generic_title("requires"), do: "Observed precondition"
  defp generic_title(_), do: "Observed promised result"

  defp conjuncts(node, path) do
    if logical_operator(node) == :and and node["status"] != "not_evaluated" do
      Enum.flat_map(Enum.with_index(node["children"] || []), fn {child, i} ->
        conjuncts(child, path ++ [i])
      end)
    else
      [%{node: node, path: path, context: []}]
    end
  end

  defp logical_operator(node) do
    case Code.string_to_quoted(node["expression"]) do
      {:ok, {op, _, _}} when op in [:and, :or, :not, :if, :case] -> op
      _ -> nil
    end
  end

  defp paths(node, path), do: paths(node, path, [])

  defp paths(node, path, context) do
    [%{node: node, path: path, context: context}] ++
      Enum.flat_map(Enum.with_index(node["children"] || []), fn {child, i} ->
        paths(child, path ++ [i], child_context(node, path, context, i))
      end)
  end

  defp child_context(node, path, context, index) do
    case logical_operator(node) do
      op when op in [:or, :not, :if, :case] ->
        context ++ [%{operator: op, expression: node["expression"], path: path, branch: index}]

      _ ->
        context
    end
  end
end
