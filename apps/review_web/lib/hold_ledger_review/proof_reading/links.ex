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
    path = link["source_path"]
    phase = link["phase"]
    indices = link["steps"]

    cond do
      not (is_binary(link["id"]) and byte_size(link["id"]) in 1..80 and
               phase in ~w(requires expects) and is_binary(link["expression"]) and
               is_binary(link["relation"]) and is_binary(path) and is_list(indices) and
               indices != [] and length(indices) <= 6 and Enum.uniq(indices) == indices) ->
        "Invalid reading-link definition"

      not (Map.has_key?(reviewed, path) and reviewed[path] == digests[path] and
               is_binary(files[path])) ->
        "Reviewed Elixir source missing or changed"

      declaration["status"] != "source_declaration_not_elaborated_evidence" or
          declaration["sha256"] != digests[declaration["path"]] ->
        "Lean declaration missing or ambiguous"

      not Enum.all?(indices, fn n ->
             is_integer(n) and n >= 0 and n < length(steps) and
               is_integer(Enum.at(steps, n)["line"])
           end) ->
        "Lean anchor missing or ambiguous"

      true ->
        with {:ok, ast} <- Code.string_to_quoted(files[path]),
             {:ok, target} <- Code.string_to_quoted(link["expression"]),
             1 <- count_ast(ast, target) do
          :ok
        else
          _ -> "Elixir clause missing or ambiguous in reviewed AST"
        end
    end
  end

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
        phase = if(link["phase"] == "expects", do: basis, else: "requires")
        node = if(is_map(binding), do: binding[phase])

        cond do
          link["availability"] != "available" ->
            {good, ["#{link["id"]}: #{link["availability"]}" | bad]}

          not is_map(node) ->
            {good, ["#{link["id"]}: no observed clause for this input" | bad]}

          true ->
            with {:ok, target} <- Code.string_to_quoted(link["expression"]),
                 [path] <- matching_paths(node, target, link["phase"] == "expects" and basis == "candidate") do
              resolved =
                Map.merge(link, %{
                  "phase" => phase,
                  "path" => Enum.join(path, "."),
                  "binding" => binding_index,
                  "basis" => basis,
                  "generation" => reading["source_generation"]
                })

              {[resolved | good], bad}
            else
              _ ->
                {good, ["#{link["id"]}: observed AST missing or ambiguous" | bad]}
            end
        end
      end)

    %{links: Enum.reverse(links), unavailable: Enum.reverse(unavailable)}
  end

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

      node -> node
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
    [{path, node} | Enum.flat_map(Enum.with_index(node["children"] || []), fn {child, i} ->
       paths(child, path ++ [i])
     end)]
  end
end
