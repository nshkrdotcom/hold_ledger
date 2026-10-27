defmodule HoldLedgerReview.Claims.Compiler do
  @moduledoc """
  Audited, compile-once Elixir AST subset. Only source read through `Claims.Source`
  reaches this module. Candidate replacement targets *every* equivalent Ledger
  call in the original `expects`, never an independently handwritten predicate.
  """

  alias HoldLedgerReview.Claims.Source

  @generated HoldLedgerReview.Claims.Generated
  # This module is created only after the trusted source has been audited.
  @compile {:no_warn_undefined, {@generated, :claim_manifest_sha256, 0}}
  @initial ~w(po_b1_void po_b1_timeout po_b2 po_b3 po_a2 po_a4_conflict po_a4_duplicate po_exposure_retain po_s)
  @ops %{step: 2, request: 3, void: 2, timeout: 2}
  @spec_calls %{
    valid?: 1,
    lookup: 2,
    request_eligible?: 3,
    effects_valid?: 5,
    exposed_entry?: 3,
    release_evidence?: 2,
    identity_preserved?: 2,
    expected_step: 2
  }
  @local_operators %{
    :| => 2,
    and: 2,
    or: 2,
    not: 1,
    in: 2,
    ==: 2,
    ===: 2,
    !=: 2,
    !==: 2,
    <: 2,
    >: 2,
    <=: 2,
    >=: 2,
    +: 2,
    -: 2,
    *: 2,
    elem: 2,
    is_integer: 1
  }
  @literal_atoms ~w(
    ok reserved sent unknown authorized voiding declined voided
    request processor_result approved admitted duplicate conflict
  )a

  def initial_slugs, do: @initial

  def prepare(%{slug: slug} = law) when slug in @initial do
    with true <- Enum.all?(law.formals, &is_atom/1),
         {:ok, requires} <- expand(law.requires, law.aliases),
         {:ok, expects} <- expand(law.expects, law.aliases),
         :ok <- validate(requires, law.formals, false),
         :ok <- validate(expects, law.formals, true),
         {:ok, target, call_count} <- single_target(expects, law.formals),
         {substituted, replaced} <- replace_all(expects, target),
         true <- replaced == call_count and target_calls(substituted) == [] do
      {:ok,
       Map.merge(law, %{
         normalized_requires: requires,
         normalized_expects: expects,
         substituted_expects: substituted,
         operation: target_operation(target),
         target_ast: target,
         call_signature: Macro.to_string(target),
         occurrence_count: call_count,
         residual_target_count: 0
       })}
    else
      false -> {:error, :incomplete_target_replacement}
      {:error, _} = error -> error
    end
  end

  def prepare(_), do: {:error, :outside_initial_probe_scope}

  def compile(manifest_sha, claims) when is_binary(manifest_sha) and is_map(claims) do
    if Code.ensure_loaded?(@generated) do
      module = @generated

      if module.claim_manifest_sha256() == manifest_sha do
        {:ok, @generated}
      else
        {:error, :source_or_compiled_code_drift}
      end
    else
      definitions =
        claims
        |> Enum.sort_by(&elem(&1, 0))
        |> Enum.flat_map(fn {_slug, law} -> definitions(law) end)

      ast =
        quote do
          @moduledoc false
          @compile :debug_info
          def claim_manifest_sha256, do: unquote(manifest_sha)
          def compiler_version, do: unquote(Source.version())
          unquote_splicing(definitions)
        end

      case Module.create(@generated, ast, Macro.Env.location(__ENV__)) do
        {:module, @generated, _binary, _result} -> {:ok, @generated}
        _ -> {:error, :evaluator_compile_failed}
      end
    end
  rescue
    _ -> {:error, :evaluator_compile_failed}
  end

  defp definitions(%{slug: slug, formals: names} = law) do
    [
      definition(:requires, slug, names, law.normalized_requires),
      definition(:actual, slug, names, law.normalized_expects),
      definition(:candidate, slug, names, law.substituted_expects),
      definition(:target, slug, names, law.target_ast)
    ]
  end

  defp definition(function, slug, names, expression) do
    {_, used} =
      Macro.prewalk(expression, MapSet.new(), fn
        {name, _, nil} = node, acc when is_atom(name) -> {node, MapSet.put(acc, name)}
        node, acc -> {node, acc}
      end)

    vars =
      Enum.map(names, fn name ->
        Macro.var(if(MapSet.member?(used, name), do: name, else: :_), nil)
      end)

    args = [slug, vars]
    args = if function == :candidate, do: args ++ [candidate_variable()], else: args

    quote do
      def unquote(function)(unquote_splicing(args)), do: unquote(expression)
    end
  end

  # A separate AST context prevents capture by any source formal name.
  defp candidate_variable, do: Macro.var(:candidate_output, __MODULE__)

  defp expand(ast, aliases) do
    {expanded, unresolved} =
      Macro.postwalk(ast, [], fn
        {{:., dot_meta, [{:__aliases__, _, [name]}, fun]}, meta, args}, problems
        when name in [:Ledger, :Spec] ->
          if name in aliases do
            qualified = {:__aliases__, [], [:HoldLedger, name]}
            {{{:., dot_meta, [qualified, fun]}, meta, args}, problems}
          else
            {{{:., dot_meta, [{:__aliases__, [], [name]}, fun]}, meta, args},
             [:unresolved_alias | problems]}
          end

        node, problems ->
          {node, problems}
      end)

    if unresolved == [], do: {:ok, expanded}, else: {:error, :unresolved_alias}
  rescue
    _ -> {:error, :unresolved_alias}
  end

  defp validate(ast, formals, reducer_allowed?) do
    if valid_ast?(ast, MapSet.new(formals), reducer_allowed?),
      do: :ok,
      else: {:error, :unsupported_ast}
  end

  defp valid_ast?(term, _formals, _reducer?)
       when is_integer(term) and term >= 0 and term <= 1_000_000,
       do: true

  defp valid_ast?(term, _formals, _reducer?)
       when term in [true, false, nil] or term in @literal_atoms,
       do: true

  defp valid_ast?({:{}, _, args}, formals, reducer?) when is_list(args) and length(args) <= 16,
    do: Enum.all?(args, &valid_ast?(&1, formals, reducer?))

  defp valid_ast?(
         {{:., _, [{:__aliases__, _, [:HoldLedger, :Spec]}, fun]}, _, args},
         formals,
         reducer?
       )
       when is_list(args) do
    Map.get(@spec_calls, fun) == length(args) and
      Enum.all?(args, &valid_ast?(&1, formals, reducer?))
  end

  defp valid_ast?(
         {{:., _, [{:__aliases__, _, [:HoldLedger, :Ledger]}, fun]}, _, args},
         formals,
         true
       )
       when is_list(args) do
    Map.get(@ops, fun) == length(args) and Enum.all?(args, &valid_ast?(&1, formals, true))
  end

  defp valid_ast?({op, _, args}, formals, reducer?) when is_atom(op) and is_list(args) do
    Map.get(@local_operators, op) == length(args) and
      Enum.all?(args, &valid_ast?(&1, formals, reducer?))
  end

  defp valid_ast?({name, _, context}, formals, _reducer?)
       when is_atom(name) and (is_nil(context) or is_atom(context)) do
    MapSet.member?(formals, name)
  end

  defp valid_ast?(list, formals, reducer?) when is_list(list) and length(list) <= 32,
    do: Enum.all?(list, &valid_ast?(&1, formals, reducer?))

  defp valid_ast?(tuple, formals, reducer?) when is_tuple(tuple) and tuple_size(tuple) == 2,
    do: tuple |> Tuple.to_list() |> Enum.all?(&valid_ast?(&1, formals, reducer?))

  defp valid_ast?(_, _, _), do: false

  defp single_target(expects, formals) do
    calls = target_calls(expects)

    case calls do
      [] ->
        {:error, :no_target_reducer_call}

      [first | rest] ->
        signature = semantic_ast(first)

        cond do
          not Enum.all?(rest, &(semantic_ast(&1) == signature)) ->
            {:error, :non_equivalent_reducer_calls}

          not exact_formal_call?(first, formals) ->
            {:error, :unsupported_call_signature}

          true ->
            {:ok, first, length(calls)}
        end
    end
  end

  defp exact_formal_call?({{:., _, [_, :step]}, _, [s, event]}, [state, event_name | _]) do
    variable?(s, state) and variable?(event, event_name)
  end

  defp exact_formal_call?({{:., _, [_, :request]}, _, [s, key, amount]}, [
         state,
         key_name,
         amount_name | _
       ]) do
    variable?(s, state) and variable?(key, key_name) and variable?(amount, amount_name)
  end

  defp exact_formal_call?({{:., _, [_, op]}, _, [s, key]}, [state, key_name | _])
       when op in [:void, :timeout] do
    variable?(s, state) and variable?(key, key_name)
  end

  defp exact_formal_call?(_, _), do: false
  defp variable?({name, _, ctx}, name) when is_atom(ctx) or is_nil(ctx), do: true
  defp variable?(_, _), do: false

  def target_operation({{:., _, [_, fun]}, _, _}), do: fun

  defp target_calls(ast) do
    {_, calls} =
      Macro.prewalk(ast, [], fn
        {{:., _, [{:__aliases__, _, [:HoldLedger, :Ledger]}, _fun]}, _, _} = call, acc ->
          {call, [call | acc]}

        node, acc ->
          {node, acc}
      end)

    Enum.reverse(calls)
  end

  defp semantic_ast(ast) do
    Macro.prewalk(ast, fn
      {name, meta, args} when is_list(meta) -> {name, [], args}
      node -> node
    end)
  end

  defp replace_all(ast, target) do
    signature = semantic_ast(target)

    Macro.postwalk(ast, 0, fn node, replaced ->
      if semantic_ast(node) == signature do
        {candidate_variable(), replaced + 1}
      else
        {node, replaced}
      end
    end)
  end
end
