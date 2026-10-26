# Finite syntax-aware arithmetic/comparison operator universe; no live source edits.
[output] = System.argv()
source = File.read!("lib/hold_ledger/ledger.ex")
ast = Code.string_to_quoted!(source, columns: true, token_metadata: true)
operators = %{>: :>=, >=: :>, +: :-, -: :+, ==: :!=}

{_, sites} =
  Macro.prewalk(ast, [], fn
    {operator, meta, [_, _]} = node, sites when is_map_key(operators, operator) ->
      {node,
       [
         %{
           operator: operator,
           replacement: operators[operator],
           line: meta[:line],
           column: meta[:column]
         }
         | sites
       ]}

    node, sites ->
      {node, sites}
  end)

File.mkdir_p!(output)

manifest =
  sites
  |> Enum.reverse()
  |> Enum.with_index(1)
  |> Enum.map(fn {site, index} ->
    mutated =
      Macro.prewalk(ast, fn
        {operator, meta, [a, b]} = node ->
          if operator == site.operator and meta[:line] == site.line and
               meta[:column] == site.column, do: {site.replacement, meta, [a, b]}, else: node

        node ->
          node
      end)

    path = Path.join(output, "operator-#{index}.ex")
    text = mutated |> Macro.to_string() |> Code.format_string!() |> IO.iodata_to_binary()
    File.write!(path, text <> "\n")

    Map.merge(site, %{
      id: "operator-#{index}",
      file: Path.expand(path),
      sha256: Base.encode16(:crypto.hash(:sha256, text <> "\n"), case: :lower)
    })
  end)

File.write!(Path.join(output, "manifest.json"), JSON.encode!(manifest))
IO.puts("Generated #{length(manifest)} syntax-aware operator mutations")

# Mutate executable clauses only: types, docs and attributes are excluded.
{:defmodule, module_meta, [name, [do: {:__block__, block_meta, forms}]]} = ast

status_swaps = %{
  reserved: :sent,
  sent: :unknown,
  unknown: :authorized,
  authorized: :voiding,
  voiding: :voided,
  voided: :authorized,
  declined: :authorized
}

function_identity = fn form ->
  case form do
    {kind, _, [head | _]} when kind in [:def, :defp] ->
      head =
        case head do
          {:when, _, [call | _]} -> call
          call -> call
        end

      {function, _, args} = head
      {kind, function, length(args || [])}

    _ ->
      nil
  end
end

identities = Enum.map(forms, function_identity)

extra =
  forms
  |> Enum.with_index()
  |> Enum.flat_map(fn {form, index} ->
    case form do
      {kind, meta, _} when kind in [:def, :defp] ->
        {_, occurrences} =
          Macro.prewalk(form, [], fn
            atom, hits when is_atom(atom) and is_map_key(status_swaps, atom) ->
              {atom, [atom | hits]}

            node, hits ->
              {node, hits}
          end)

        statuses =
          occurrences
          |> Enum.reverse()
          |> Enum.with_index()
          |> Enum.map(fn {atom, selected} ->
            {changed, _} =
              Macro.prewalk(form, 0, fn
                value, n when is_atom(value) and is_map_key(status_swaps, value) ->
                  {if(n == selected, do: status_swaps[value], else: value), n + 1}

                node, n ->
                  {node, n}
              end)

            {%{
               operator: "status",
               original: atom,
               replacement: status_swaps[atom],
               line: meta[:line],
               occurrence: selected
             }, List.replace_at(forms, index, changed)}
          end)

        deletion =
          if Enum.count(identities, &(&1 == Enum.at(identities, index))) > 1,
            do: [
              {%{
                 operator: "clause",
                 line: meta[:line],
                 function: inspect(Enum.at(identities, index))
               }, List.delete_at(forms, index)}
            ],
            else: []

        statuses ++ deletion

      _ ->
        []
    end
  end)

extra_manifest =
  extra
  |> Enum.with_index(1)
  |> Enum.map(fn {{site, changed_forms}, index} ->
    changed_ast = {:defmodule, module_meta, [name, [do: {:__block__, block_meta, changed_forms}]]}
    text = changed_ast |> Macro.to_string() |> Code.format_string!() |> IO.iodata_to_binary()
    path = Path.join(output, "transition-#{index}.ex")
    File.write!(path, text <> "\n")

    Map.merge(site, %{
      id: "transition-#{index}",
      file: Path.expand(path),
      sha256: Base.encode16(:crypto.hash(:sha256, text <> "\n"), case: :lower)
    })
  end)

File.write!(Path.join(output, "manifest.json"), JSON.encode!(manifest ++ extra_manifest))

IO.puts(
  "Generated #{length(extra_manifest)} status/clause mutations; total #{length(manifest) + length(extra_manifest)}"
)
