defmodule HoldLedgerReview.ClaimProbe do
  @moduledoc """
  Bounded pointwise counterfactual evaluation against the exact compiled
  `requires` and `expects` expressions. Bindings are taken from the audited
  reducer-call signature and source lookup equality, never a hard-coded law
  predicate or an assumed event amount on a void/timeout.
  """
  alias HoldLedger.{Ledger, Spec}
  alias HoldLedgerReview.{Canonical, Claims, Config, TermCodec}
  alias HoldLedgerReview.Claims.Compiler

  @max_bindings 8
  @test_environment Mix.env() == :test

  def labels do
    %{
      catches: "Catches",
      allows_here: "Allows here",
      doesnt_apply: "Doesn't apply",
      cant_check: "Can't check"
    }
  end

  def probe_all(before, event, candidate, opts \\ []) do
    slugs = Keyword.get(opts, :slugs, Compiler.initial_slugs())
    Map.new(slugs, fn slug -> {slug, probe(slug, before, event, candidate, opts)} end)
  end

  def probe(slug, before, event, candidate, opts \\ []) do
    root = Keyword.get(opts, :root, Config.root())

    with :ok <- Claims.freshness(root),
         {:ok, law} <- Claims.claim(slug),
         {:ok, before_json} <- TermCodec.encode_state(before),
         {:ok, event_json} <- TermCodec.encode_event(event),
         {:ok, candidate_json} <- TermCodec.encode_output(candidate),
         true <- Spec.valid?(before),
         {:ok, bindings} <- bindings(law, before, event, Keyword.get(opts, :binding_limit, @max_bindings)) do
      result =
        evaluate_bindings(law, bindings, before, event, candidate, %{
          before: before_json,
          event: event_json,
          candidate: candidate_json,
          root: root
        })

      # A deterministic test-only boundary can change an isolated checkout
      # between evaluation and publication. Never publish the old green row.
      if @test_environment and is_function(opts[:before_finish], 0),
        do: opts[:before_finish].()

      case Claims.freshness(root) do
        :ok -> result
        _ -> unavailable(slug, :source_or_compiled_code_drift)
      end
    else
      {:not_probed, other} ->
        %{unavailable(slug, {:different_operation, other}) | status: :not_probed,
          uncovered_remainder: []}
      {:error, reason} -> unavailable(slug, reason)
      false -> unavailable(slug, :invalid_before_state)
    end
  rescue
    _ -> unavailable(slug, :source_expression_error)
  end

  def follow_on(actual, candidate, nil),
    do: %{actual: nil, candidate: nil, reason: :no_follow_on_event}

  def follow_on({actual_after, _, _}, {candidate_after, _, _}, event) do
    case TermCodec.encode_event(event) do
      {:ok, _} ->
        %{
          actual: if(Spec.valid?(actual_after), do: {:ok, Ledger.step(actual_after, event)}, else: {:error, :invalid_state}),
          candidate: if(Spec.valid?(candidate_after), do: {:ok, Ledger.step(candidate_after, event)}, else: {:error, :invalid_state}),
          reason: :pure_ledger_calculation
        }

      _ -> %{actual: nil, candidate: nil, reason: :invalid_follow_on_event}
    end
  end

  defp bindings(%{formals: [state | rest], operation: op} = law, before, event, limit)
       when is_integer(limit) and limit > 0 and limit <= @max_bindings do
    with {:ok, input, origins} <- target_binding(state, rest, op, before, event),
         {:ok, lookup} <- source_lookup(law, state) do
      extras = law.formals -- Map.keys(input)

      case {extras, lookup} do
        {[], _} ->
          {:ok, %{rows: [%{values: input, origins: origins}], exhaustive?: true,
                  reason: "Every reducer argument is exactly determined by the event and before-state", truncated?: false}}

        {_, {:lookup, pattern}} ->
          if Enum.all?(extras, &Map.has_key?(entry_pattern_fields(pattern), &1)) do
            lookup_bindings(before, pattern, input, origins, extras, limit)
          else
            {:error, :incomplete_binding_domain}
          end

        _ ->
          {:error, :incomplete_binding_domain}
      end
    end
  end

  defp bindings(_, _, _, _), do: {:error, :invalid_binding_limit}

  defp target_binding(state, [event_param | _], :step, before, event) do
    {:ok, %{state => before, event_param => event},
     %{state => %{kind: :before_state}, event_param => %{kind: :witness_event}}}
  end

  defp target_binding(state, [key_param, amount_param | _], :request, before, {:request, key, amount}) do
    {:ok,
     %{state => before, key_param => key, amount_param => amount},
     %{
       state => %{kind: :before_state},
       key_param => %{kind: :request_field, field: :key},
       amount_param => %{kind: :request_field, field: :amount}
     }}
  end

  defp target_binding(state, [key_param | _], operation, before, {operation, key})
       when operation in [:void, :timeout] do
    {:ok, %{state => before, key_param => key},
     %{state => %{kind: :before_state}, key_param => %{kind: :event_field, field: :key}}}
  end

  defp target_binding(_, _, operation, _, _), do: {:not_probed, operation}

  # Require a source equality of Spec.lookup(elem(before,4),key) to the stated
  # {:ok, {key,amount,status}}. Extract names/literals from that *AST pattern*.
  # An unsupported lookup shape must not silently produce exhaustive silence.
  defp source_lookup(law, state_param) do
    {_, patterns} =
      Macro.prewalk(law.normalized_requires, [], fn
        {cmp, _, [lhs, rhs]} = node, acc when cmp in [:==, :===] ->
          case lookup_pattern(lhs, rhs, state_param) || lookup_pattern(rhs, lhs, state_param) do
            nil -> {node, acc}
            pattern -> {node, [pattern | acc]}
          end

        node, acc ->
          {node, acc}
      end)

    case patterns do
      [] -> {:ok, :no_lookup}
      [pattern] -> {:ok, {:lookup, pattern}}
      _ -> {:error, :ambiguous_lookup_binding}
    end
  end

  defp lookup_pattern(
         {{:., _, [{:__aliases__, _, [:HoldLedger, :Spec]}, :lookup]}, _,
          [{:elem, _, [state_ast, 4]}, key_ast]},
         {:ok, {:{}, _, [entry_key, _, _]}} = pattern,
         state_param
       ) do
    if variable?(state_ast, state_param) and same_variable?(key_ast, entry_key),
      do: pattern,
      else: nil
  end

  defp lookup_pattern(_, _, _), do: nil

  defp same_variable?({left, _, left_context}, {right, _, right_context})
       when is_atom(left) and is_atom(right) and is_atom(left_context) and is_atom(right_context),
       do: left == right

  defp same_variable?(_, _), do: false

  defp lookup_bindings(before, pattern, initial, origins, extras, limit) do
    {_, _, _, _, entries} = before

    eligible =
      Enum.flat_map(entries, fn {key, _amount, _status} = entry ->
        case bind_pattern(pattern, {:ok, entry}, initial) do
          {:ok, values} when map_size(values) >= map_size(initial) ->
            if Enum.all?(extras, &Map.has_key?(values, &1)) do
              fields = entry_pattern_fields(pattern)

              discovered =
                Map.new(extras, fn param ->
                  {param, %{kind: :existing_entry, entry_key: key,
                            field: Map.fetch!(fields, param)}}
                end)

              refined =
                Enum.reduce(fields, origins, fn {param, field}, acc ->
                  if Map.has_key?(acc, param) and field in [:key, :amount] do
                    Map.put(acc, param,
                      %{kind: :event_field_and_existing_entry, field: field, entry_key: key,
                        event_origin: Map.fetch!(acc, param)})
                  else
                    acc
                  end
                end)

              [%{values: values, origins: Map.merge(refined, discovered)}]
            else
              []
            end

          _ -> []
        end
      end)

    if length(eligible) > limit do
      {:error, :truncated_binding_domain}
    else
      {:ok,
       %{
         rows: eligible,
         exhaustive?: true,
         reason: "The source lookup equality pins all remaining formals to the finite pre-state entries",
         truncated?: false
       }}
    end
  end

  defp entry_pattern_fields({:ok, {:{}, _, entry}}) do
    entry
    |> Enum.zip([:key, :amount, :status])
    |> Enum.reduce(%{}, fn
      {{name, _, ctx}, field}, acc when is_atom(name) and (is_nil(ctx) or is_atom(ctx)) ->
        Map.put(acc, name, field)

      _, acc ->
        acc
    end)
  end

  defp bind_pattern({:{}, _, elems}, value, existing) when is_tuple(value) do
    if tuple_size(value) == length(elems) do
      Enum.zip(elems, Tuple.to_list(value))
      |> Enum.reduce_while({:ok, existing}, fn {part, actual}, {:ok, acc} ->
        case bind_pattern(part, actual, acc) do
          {:ok, updated} -> {:cont, {:ok, updated}}
          error -> {:halt, error}
        end
      end)
    else
      {:error, :pattern_mismatch}
    end
  end

  defp bind_pattern(pattern, value, existing) when is_tuple(pattern) and tuple_size(pattern) == 2 and is_tuple(value) and tuple_size(value) == 2 do
    Enum.zip(Tuple.to_list(pattern), Tuple.to_list(value))
    |> Enum.reduce_while({:ok, existing}, fn {part, actual}, {:ok, acc} ->
      case bind_pattern(part, actual, acc) do
        {:ok, updated} -> {:cont, {:ok, updated}}
        error -> {:halt, error}
      end
    end)
  end

  defp bind_pattern({name, _, ctx}, value, existing) when is_atom(name) and (is_nil(ctx) or is_atom(ctx)) do
    case Map.fetch(existing, name) do
      :error -> {:ok, Map.put(existing, name, value)}
      {:ok, ^value} -> {:ok, existing}
      _ -> {:error, :pattern_mismatch}
    end
  end

  defp bind_pattern(value, value, existing), do: {:ok, existing}
  defp bind_pattern(_, _, _), do: {:error, :pattern_mismatch}
  defp variable?({name, _, ctx}, name) when is_nil(ctx) or is_atom(ctx), do: true
  defp variable?(_, _), do: false

  defp evaluate_bindings(law, bindings, before, event, candidate, encoded) do
    actual = Ledger.step(before, event)

    with {:ok, actual_json} <- TermCodec.encode_output(actual),
         {:ok, oracle_json} <- TermCodec.encode_output(Spec.expected_step(before, event)) do
      generation = Claims.snapshot()
      candidate_hash = Canonical.digest(encoded.candidate)

      rows =
        Enum.map(bindings.rows, fn binding ->
          values = Enum.map(law.formals, &Map.fetch!(binding.values, &1))
          origins = Map.new(binding.origins, fn {k, v} -> {Atom.to_string(k), v} end)

          outcome =
            case Claims.evaluate(law.slug, values, candidate, encoded.root) do
              {:ok, %{requires: true, actual: source_actual, candidate: substituted,
                      operation_output: operation_output}} ->
                if operation_output == actual and is_boolean(source_actual) and is_boolean(substituted) do
                  %{requires: true, source_actual_expects: source_actual, substituted_expects: substituted}
                else
                  %{requires: :error, source_actual_expects: :error, substituted_expects: :error,
                    reason: :operation_mismatch_or_bad_expression}
                end

              {:ok, %{requires: false}} ->
                %{requires: false, source_actual_expects: nil, substituted_expects: nil}

              _ ->
                %{requires: :error, source_actual_expects: :error, substituted_expects: :error,
                  reason: :source_expression_error}
            end

          Map.merge(outcome, %{
            law_slug: law.slug,
            source_sha256: law.source_sha256,
            evaluator_id: generation.evaluator_id,
            formal_parameters: Enum.map(law.formals, &Atom.to_string/1),
            actual_binding_values: Map.new(binding.values, fn {k, v} -> {Atom.to_string(k), binding_json(v)} end),
            binding_origin: origins,
            call_signature: law.call_signature,
            occurrence_count: law.occurrence_count,
            candidate_hash: candidate_hash,
            truncated?: bindings.truncated?,
            coverage_explanation: bindings.reason,
            evidence_anchor_ids: ["law." <> law.slug]
          })
        end)

      {status, reason} = aggregate(rows, bindings.exhaustive?)

      %{
        law_slug: law.slug,
        status: status,
        reason: reason,
        source_sha256: law.source_sha256,
        evaluator_id: generation.evaluator_id,
        occurrence_count: law.occurrence_count,
        call_signature: law.call_signature,
        candidate_hash: candidate_hash,
        actual: actual_json,
        oracle: oracle_json,
        candidate: encoded.candidate,
        candidate_after_spec_valid?: Spec.valid?(elem(candidate, 0)),
        bindings_tested: length(rows),
        exhaustive_for_source_domain: bindings.exhaustive?,
        coverage_explanation: bindings.reason,
        uncovered_remainder: if(bindings.exhaustive?, do: [], else: [:untested_bindings]),
        rows: rows
      }
    else
      _ -> unavailable(law.slug, :unsupported_reducer_output)
    end
  end

  defp aggregate(rows, exhaustive?) do
    cond do
      Enum.any?(rows, &(&1[:source_actual_expects] == false and &1[:requires] == true)) ->
        {:cant_check, :actual_contract_alarm}

      Enum.any?(rows, &(&1[:requires] == :error)) ->
        {:cant_check, :source_expression_error}

      Enum.any?(rows, &(&1[:requires] == true and &1[:substituted_expects] == false)) ->
        {:catches, :source_expression_rejects_candidate}

      Enum.any?(rows, &(&1[:requires] == true and &1[:substituted_expects] == true)) ->
        {:allows_here, if(exhaustive?, do: :all_source_derived_bindings_tested, else: :tested_only)}

      exhaustive? ->
        {:doesnt_apply, :no_applicable_source_binding}

      true ->
        {:cant_check, :incomplete_binding_domain}
    end
  end

  defp binding_json({_, _, _, _, _} = state) do
    {:ok, obj} = TermCodec.encode_state(state)
    obj
  end

  defp binding_json(event) when is_tuple(event) do
    {:ok, obj} = TermCodec.encode_event(event)
    obj
  end

  defp binding_json(atom) when is_atom(atom), do: Atom.to_string(atom)
  defp binding_json(value), do: value

  defp unavailable(slug, reason) do
    %{
      law_slug: slug,
      status: :cant_check,
      reason: reason,
      bindings_tested: 0,
      exhaustive_for_source_domain: false,
      rows: [],
      uncovered_remainder: [reason]
    }
  end
end
