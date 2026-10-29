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
    # Source ASTs can be large. Check each reviewed source once, not once per
    # condition per keystroke, and only accept explicitly reviewed paths.
    paths = groups |> Enum.map(& &1["source_path"]) |> Enum.uniq()

    available =
      Map.new(paths, fn path ->
        result =
          if is_binary(path) and Map.has_key?(reviewed, path) and
               Map.has_key?(digests, path) and reviewed[path] == digests[path] and
               is_binary(Map.get(bytes, path)) do
            case Code.string_to_quoted(bytes[path]) do
              {:ok, ast} ->
                {_ast, terms} = Macro.prewalk(ast, MapSet.new(), fn node, seen ->
                  {node, MapSet.put(seen, Macro.to_string(node))}
                end)
                terms
              _ -> MapSet.new()
            end
          else
            MapSet.new()
          end

        {path, result}
      end)

    Enum.filter(groups, fn group ->
      expressions = group["expressions"]
      source_terms = available[group["source_path"]] || MapSet.new()

      is_binary(group["id"]) and is_binary(group["title"]) and
        group["phase"] in ~w(requires expects) and is_binary(group["source_path"]) and
        is_list(expressions) and expressions != [] and
        Enum.all?(expressions, fn expression ->
          if is_binary(expression) do
            case Code.string_to_quoted(expression) do
              {:ok, wanted} -> MapSet.member?(source_terms, Macro.to_string(wanted))
              _ -> false
            end
          else
            false
          end
        end)
    end)
  end

  def validate(_, _, _, _), do: []

  @doc "Project one phase and binding without altering the observed tree."
  def project(node, phase, groups, changed_paths \\ [])

  def project(nil, _phase, _groups, _changed_paths), do: []

  def project(node, phase, groups, changed_paths) when is_map(node) do
    observed = paths(node, [])
    source_phase = if phase == "requires", do: "requires", else: "expects"

    curated =
      Enum.flat_map(groups, fn group ->
        if group["phase"] == source_phase do
          rows =
            Enum.filter(observed, fn item ->
              item.node["expression"] in group["expressions"]
            end)

          if rows == [] do
            []
          else
            [outline_group(group["id"], group["title"], rows,
              changed_source: group["source_path"] in changed_paths,
              source_path: group["source_path"],
              collapse_satisfied: group["collapse_satisfied"] == true
            )]
          end
        else
          []
        end
      end)

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
        else: [outline_group("skipped", "Short-circuited branches", skipped_roots,
          collapse_unevaluated: true)]

    if curated == [] do
      [outline_group("generic", generic_title(phase), [%{node: node, path: []}])] ++ skipped
    else
      curated ++ skipped
    end
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
      collapsed?: (collapse and !changed and counts["true"] == length(rows)) or
        Keyword.get(opts, :collapse_unevaluated, false),
      attention?: changed or counts["false"] > 0 or counts["not_evaluated"] > 0 or
        counts["unavailable"] > 0
    }
  end

  defp generic_title("requires"), do: "Observed precondition"
  defp generic_title(_), do: "Observed promised result"

  defp paths(node, path) do
    [%{node: node, path: path}] ++
      Enum.flat_map(Enum.with_index(node["children"] || []), fn {child, i} ->
        paths(child, path ++ [i])
      end)
  end

end
