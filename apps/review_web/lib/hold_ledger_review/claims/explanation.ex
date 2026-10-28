defmodule HoldLedgerReview.Claims.Explanation do
  @moduledoc "Builds source-expression observations inside the one original generated evaluator."
  alias HoldLedgerReview.Config

  @helpers ~w(request_eligible? valid? nonnegative_state_valid? exposed_entry? release_evidence? has_key?)a
  @comparisons [:==, :===, :!=, :!==, :<, :>, :<=, :>=, :in]

  def definitions do
    path = Path.join(Config.root(), "lib/hold_ledger/spec.ex")
    {:ok, ast} = path |> File.read!() |> Code.string_to_quoted()
    public = HoldLedger.Spec.__info__(:functions)

    {_ast, definitions} =
      Macro.prewalk(ast, [], fn
        {kind, meta, [head, [do: body]]} = node, acc when kind in [:def, :defp] ->
          {call, guard} = head_parts(head)
          {name, _, args} = call

          if name in @helpers do
            clause = helper_definition(name, args, guard, body, meta, public)
            {node, [clause | acc]}
          else
            {node, acc}
          end

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(definitions) ++
      [
        quote do
          def inspect_helper(_name, _args), do: nil
        end
      ]
  end

  defp head_parts({:when, _, [call, guard]}), do: {call, guard}
  defp head_parts(call), do: {call, nil}

  defp helper_definition(name, args, guard, body, meta, public) do
    signature = Atom.to_string(name) <> "/" <> to_string(length(args))
    head = quote do: inspect_helper(unquote(signature), unquote(args))
    head = if guard, do: {:when, [], [head, guard]}, else: head

    instrumented =
      if guard do
        quote do
          guard_node = unquote(trace(guard, public))
          body_node = unquote(trace(body, public))

          %{
            expression: unquote(Macro.to_string(head)),
            value: body_node.value,
            children: [guard_node, body_node]
          }
        end
      else
        trace(body, public)
      end

    quote do
      def unquote(head) do
        node = unquote(instrumented)

        Map.merge(node, %{
          helper: unquote(signature),
          source_path: "lib/hold_ledger/spec.ex",
          source_line: unquote(meta[:line] || 1)
        })
      end
    end
  end

  def trace(expression), do: trace(expression, HoldLedger.Spec.__info__(:functions))

  defp trace({op, _, [left, right]} = ast, public) when op in [:and, :or] do
    l = Macro.unique_var(:left, __MODULE__)
    r = Macro.unique_var(:right, __MODULE__)
    short = op == :or

    quote do
      unquote(l) = unquote(trace(left, public))

      case unquote(l).value do
        unquote(short) ->
          %{
            expression: unquote(Macro.to_string(ast)),
            value: unquote(short),
            children: [
              unquote(l),
              %{
                expression: unquote(Macro.to_string(right)),
                value: nil,
                status: "not_evaluated",
                children: []
              }
            ]
          }

        unquote(not short) ->
          unquote(r) = unquote(trace(right, public))

          %{
            expression: unquote(Macro.to_string(ast)),
            value: unquote(r).value,
            children: [unquote(l), unquote(r)]
          }

        _ ->
          raise ArgumentError, "non-boolean source condition"
      end
    end
  end

  defp trace({:not, _, [child]} = ast, public) do
    var = Macro.unique_var(:negated, __MODULE__)

    quote do
      unquote(var) = unquote(trace(child, public))

      %{
        expression: unquote(Macro.to_string(ast)),
        value: not unquote(var).value,
        children: [unquote(var)]
      }
    end
  end

  defp trace({op, _, [left, right]} = ast, public) when op in @comparisons do
    l = Macro.unique_var(:lhs, __MODULE__)
    r = Macro.unique_var(:rhs, __MODULE__)
    operation = {op, [], [quote(do: unquote(l).value), quote(do: unquote(r).value)]}

    quote do
      unquote(l) = unquote(trace(left, public))
      unquote(r) = unquote(trace(right, public))

      %{
        expression: unquote(Macro.to_string(ast)),
        value: unquote(operation),
        children: [unquote(l), unquote(r)]
      }
    end
  end

  defp trace({:__block__, _, expressions}, public) do
    {last, preceding} = List.pop_at(expressions, -1)

    quote do
      unquote_splicing(Enum.map(preceding, &qualify(&1, public)))
      unquote(trace(last, public))
    end
  end

  defp trace({:if, _, [condition, branches]} = ast, public) do
    c = Macro.unique_var(:condition, __MODULE__)
    b = Macro.unique_var(:branch, __MODULE__)

    quote do
      unquote(c) = unquote(trace(condition, public))

      unquote(b) =
        if unquote(c).value do
          unquote(trace(branches[:do], public))
        else
          unquote(trace(branches[:else], public))
        end

      %{
        expression: unquote(Macro.to_string(ast)),
        value: unquote(b).value,
        children: [unquote(c), unquote(b)]
      }
    end
  end

  defp trace({:case, meta, [subject, [do: clauses]]} = ast, public) do
    subject_var = Macro.unique_var(:subject, __MODULE__)
    branch_var = Macro.unique_var(:branch, __MODULE__)

    rewritten =
      Enum.map(clauses, fn {:->, m, [patterns, body]} ->
        {:->, m, [patterns, trace(body, public)]}
      end)

    selection = {:case, meta, [subject_var, [do: rewritten]]}

    quote do
      unquote(subject_var) = unquote(qualify(subject, public))
      unquote(branch_var) = unquote(selection)

      %{
        expression: unquote(Macro.to_string(ast)),
        value: unquote(branch_var).value,
        children: [
          %{
            expression: unquote(Macro.to_string(subject)),
            value: unquote(subject_var),
            children: []
          },
          unquote(branch_var)
        ]
      }
    end
  end

  defp trace({name, _, args} = ast, public) when name in @helpers and is_list(args) do
    signature = Atom.to_string(name) <> "/" <> to_string(length(args))

    if {name, length(args)} in public do
      call_node(ast, signature, args, public)
    else
      quote do: inspect_helper(unquote(signature), unquote(Enum.map(args, &qualify(&1, public))))
    end
  end

  defp trace({{:., _, [{:__aliases__, _, [:HoldLedger, :Spec]}, name]}, _, args} = ast, public)
       when name in @helpers do
    call_node(ast, Atom.to_string(name) <> "/" <> to_string(length(args)), args, public)
  end

  defp trace({:is_integer, _, [argument]} = ast, public) do
    arg = Macro.unique_var(:argument, __MODULE__)

    quote do
      unquote(arg) = unquote(trace(argument, public))

      %{
        expression: unquote(Macro.to_string(ast)),
        value: is_integer(unquote(arg).value),
        children: [unquote(arg)]
      }
    end
  end

  defp trace(ast, public) do
    quote do
      %{
        expression: unquote(Macro.to_string(ast)),
        value: unquote(qualify(ast, public)),
        children: []
      }
    end
  end

  defp call_node(ast, signature, args, public) do
    v = Macro.unique_var(:actual, __MODULE__)
    h = Macro.unique_var(:helper, __MODULE__)

    quote do
      unquote(v) = unquote(qualify(ast, public))

      unquote(h) =
        inspect_helper(unquote(signature), unquote(Enum.map(args, &qualify(&1, public))))

      if unquote(h) && unquote(h).value != unquote(v),
        do: raise(ArgumentError, "helper observation disagrees with source")

      %{
        expression: unquote(Macro.to_string(ast)),
        value: unquote(v),
        children: if(unquote(h), do: [unquote(h)], else: [])
      }
    end
  end

  defp qualify(ast, public) do
    Macro.postwalk(ast, fn
      {name, meta, args} = node when is_atom(name) and is_list(args) ->
        if {name, length(args)} in public do
          {{:., meta, [{:__aliases__, meta, [:HoldLedger, :Spec]}, name]}, meta, args}
        else
          node
        end

      node ->
        node
    end)
  end
end
