defmodule HoldLedgerReview.Claims.Compiler do
  @moduledoc """
  Audited, compile-once Elixir AST subset. Only source read through `Claims.Source`
  reaches this module. Candidate replacement targets *every* equivalent Ledger
  call in the original `expects`, never an independently handwritten predicate.
  """

  @generated HoldLedgerReview.Claims.Generated
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
    :"|" => 2,
    and: 2, or: 2, not: 1, in: 2, ==: 2, ===: 2,
    !=: 2, !==: 2, <: 2, >: 2, <=: 2, >=: 2,
    +: 2, -: 2, *: 2, elem: 2, is_integer: 1
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
      if @generated.claim_manifest_sha256() == manifest_sha do
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
          def compiler_version, do: unquote(HoldLedgerReview.Claims.Source.version())
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
    vars = Enum.map(names, &Macro.var(&1, nil))
    candidate_var = Macro.var(:__candidate_output__, nil)
    requires = law.normalized_requires
    expects = law.normalized_expects
    candidate = law.substituted_expects
    target = law.target_ast

    [
      quote do
        def requires(unquote(slug), [unquote_splicing(vars)]), do: unquote(requires)
      end,
      quote do
        def actual(unquote(slug), [unquote_splicing(vars)]), do: unquote(expects)
      end,
      quote do
        def candidate(unquote(slug), [unquote_splicing(vars)], unquote(candidate_var)),
          do: unquote(candidate)
      end,
      quote do
        def target(unquote(slug), [unquote_splicing(vars)]), do: unquote(target)
      end
    ]
  end

  defp expand(ast, aliases) do
    try do
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
  end

  defp validate(ast, formals, reducer_allowed?) do
    if valid_ast?(ast, MapSet.new(formals), reducer_allowed?),
      do: :ok,
      else: {:error, :unsupported_ast}
  end

  defp valid_ast?(term, _formals, _reducer?)
       when is_integer(term) and term >= 0 and term <= 1_000_000,
       do: true

  defp valid_ast?(term, _formals, _reducer?) when term in [true, false, nil] or term in @literal_atoms,
    do: true

  defp valid_ast?({:{}, _, args}, formals, reducer?) when is_list(args) and length(args) <= 16,
    do: Enum.all?(args, &valid_ast?(&1, formals, reducer?))

  defp valid_ast?({{:., _, [{:__aliases__, _, [:HoldLedger, :Spec]}, fun]}, _, args}, formals, reducer?)
       when is_list(args) do
    Map.get(@spec_calls, fun) == length(args) and
      Enum.all?(args, &valid_ast?(&1, formals, reducer?))
  end

  defp valid_ast?({{:., _, [{:__aliases__, _, [:HoldLedger, :Ledger]}, fun]}, _, args}, formals, true)
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
      [] -> {:error, :no_target_reducer_call}
      [first | rest] ->
        signature = Macro.to_string(first)

        cond do
          not Enum.all?(rest, &(Macro.to_string(&1) == signature)) ->
            {:error, :non_equivalent_reducer_calls}

          not exact_formal_call?(first, formals) ->
            {:error, :unsupported_call_signature}

          true ->
            {:ok, first, length(calls)}
        end
    end
  end

  defp exact_formal_call?({{:., _, [_, fun]}, _, args}, [state | other_formals]) do
    case {fun, args} do
      {:step, [s, event]} ->
        variable?(s, state) and length(other_formals) >= 1 and variable?(event, hd(other_formals))

      {op, [s, key, amount]} when op == :request ->
        variable?(s, state) and length(other_formals) >= 2 and
          variable?(key, hd(other_formals)) and variable?(amount, Enum.at(other_formals, 1))

      {op, [s, key]} when op in [:void, :timeout] ->
        variable?(s, state) and length(other_formals) >= 1 and variable?(key, hd(other_formals))

      _ -> false
    end
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

  defp replace_all(ast, target) do
    signature = Macro.to_string(target)

    Macro.postwalk(ast, 0, fn node, replaced ->
      if Macro.to_string(node) == signature do
        {Macro.var(:__candidate_output__, nil), replaced + 1}
      else
        {node, replaced}
      end
    end)
  end
end
