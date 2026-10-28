defmodule HoldLedgerReview.ProofReading.Links do
  @moduledoc """
  Optional, reviewed *source-reading* correspondences. These are neither Lean
  goal states nor dependencies or acceptance evidence. Both the Elixir AST and
  the exact Lean declaration/anchor must still match the reviewed sources.
  """

  @doc "Validate both source ends; retain invalid links as explicit unavailability."
  def validate(definitions, files, digests, declaration, steps, reviewed)
      when is_list(definitions) do
    Enum.map(definitions, fn link ->
      reason = validate_one(link, files, digests, declaration, steps, reviewed)
      Map.put(link, "availability", if(reason == :ok, do: "available", else: reason))
    end)
  end

  def validate(_, _, _, _, _, _), do: []

  defp validate_one(link, files, digests, declaration, steps, reviewed) do
    with :ok <- definition(link),
         :ok <- reviewed_source(link["source_path"], files, digests, reviewed),
         :ok <- lean_source(declaration, digests, reviewed),
         :ok <- anchors(link["steps"], steps),
         {:ok, ast} <- Code.string_to_quoted(files[link["source_path"]]),
         {:ok, target} <- Code.string_to_quoted(link["expression"]),
         1 <- count_ast(ast, target) do
      :ok
    else
      reason when is_binary(reason) -> reason
      _ -> "Elixir clause missing or ambiguous in reviewed AST"
    end
  end

  defp definition(link) do
    valid =
      is_binary(link["relation"]) and is_binary(link["source_path"]) and
        is_binary(link["expression"]) and link["phase"] in ~w(requires expects)

    if valid and valid_id?(link["id"]) and valid_indices?(link["steps"]),
      do: :ok,
      else: "Invalid reading-link definition"
  end

  defp valid_id?(id) when is_binary(id), do: byte_size(id) in 1..80
  defp valid_id?(_), do: false

  defp valid_indices?(indices) when is_list(indices),
    do: length(indices) in 1..6 and Enum.uniq(indices) == indices

  defp valid_indices?(_), do: false

  defp reviewed_source(path, files, digests, reviewed) do
    if Map.has_key?(reviewed, path) and reviewed[path] == digests[path] and is_binary(files[path]),
      do: :ok,
      else: "Reviewed Elixir source missing or changed"
  end

  defp lean_source(declaration, digests, reviewed) do
    path = declaration["path"]

    if declaration["status"] == "source_declaration_not_elaborated_evidence" and
         Map.has_key?(reviewed, path) and reviewed[path] == digests[path] and
         declaration["sha256"] == digests[path],
       do: :ok,
       else: "Lean declaration missing or ambiguous"
  end

  defp anchors(indices, steps) do
    if Enum.all?(indices, &valid_anchor?(&1, steps)),
      do: :ok,
      else: "Lean anchor missing or ambiguous"
  end

  defp valid_anchor?(index, steps) when is_integer(index) and index >= 0 do
    case Enum.at(steps, index) do
      %{"line" => line} when is_integer(line) -> true
      _ -> false
    end
  end

  defp valid_anchor?(_, _), do: false

  defp count_ast(ast, target) do
    needle = ast_key(target)

    {_ast, count} =
      Macro.prewalk(ast, 0, fn node, acc ->
        {node, if(ast_key(node) == needle, do: acc + 1, else: acc)}
      end)

    count
  end

  @doc "Resolve an observation's structural path, never by prefix or guessed line."
  def project(reading, case_data, binding_index, basis) do
    bindings = get_in(case_data || %{}, ["explanation", "bindings"]) || []
    binding = Enum.at(bindings, binding_index)

    {links, unavailable} =
      Enum.reduce(reading["connections"] || [], {[], []}, fn link, {good, bad} ->
        case resolve(link, binding, binding_index, basis, reading["source_generation"]) do
          {:ok, resolved} -> {[resolved | good], bad}
          {:error, reason} -> {good, ["#{link["id"]}: #{reason}" | bad]}
        end
      end)

    %{links: Enum.reverse(links), unavailable: Enum.reverse(unavailable)}
  end

  defp resolve(%{"availability" => "available"} = link, binding, index, basis, generation) do
    phase = if(link["phase"] == "expects", do: basis, else: "requires")
    node = if(is_map(binding), do: binding[phase])

    with true <- is_map(node),
         {:ok, target} <- Code.string_to_quoted(link["expression"]),
         [path] <-
           matching_paths(node, target, link["phase"] == "expects" and basis == "candidate") do
      {:ok,
       Map.merge(link, %{
         "phase" => phase,
         "path" => Enum.join(path, "."),
         "binding" => index,
         "basis" => basis,
         "generation" => generation
       })}
    else
      false -> {:error, "no observed clause for this input"}
      _ -> {:error, "observed AST missing or ambiguous"}
    end
  end

  defp resolve(link, _, _, _, _), do: {:error, link["availability"]}

  defp matching_paths(node, target, candidate?) do
    needle = ast_key(if(candidate?, do: candidate_ast(target), else: target))

    paths(node, [])
    |> Enum.filter(fn {_path, current} ->
      case Code.string_to_quoted(current["expression"] || "") do
        {:ok, ast} -> ast_key(ast) == needle
        _ -> false
      end
    end)
    |> Enum.map(&elem(&1, 0))
  end

  # Only normalise the two statically inspected aliases. For the alternative,
  # show the source expression where the original compiler substitutes its
  # output variable. Actual observations still have to match uniquely.
  defp candidate_ast(ast) do
    Macro.postwalk(ast, fn
      {{:., _, [{:__aliases__, _, [:Ledger]}, operation]}, _, _}
      when operation in [:step, :request, :timeout, :void] ->
        {:candidate_output, [], nil}

      {{:., _, [{:__aliases__, _, [:HoldLedger, :Ledger]}, operation]}, _, _}
      when operation in [:step, :request, :timeout, :void] ->
        {:candidate_output, [], nil}

      node ->
        node
    end)
  end

  defp ast_key(ast) do
    ast
    |> Macro.prewalk(fn
      {:__aliases__, meta, [:Spec]} -> {:__aliases__, meta, [:HoldLedger, :Spec]}
      {:__aliases__, meta, [:Ledger]} -> {:__aliases__, meta, [:HoldLedger, :Ledger]}
      node -> node
    end)
    |> Macro.to_string()
  end

  defp paths(node, path) do
    [
      {path, node}
      | Enum.flat_map(Enum.with_index(node["children"] || []), fn {child, i} ->
          paths(child, path ++ [i])
        end)
    ]
  end
end
