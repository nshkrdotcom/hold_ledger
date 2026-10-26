defmodule HoldLedger.Differential do
  @moduledoc false

  alias HoldLedger.{Attempts, Composite, Environment, Exposure, Spec}

  def model_cases(count) when is_integer(count) and count > 0 do
    attempts = [
      {:start, :void, 1, 2},
      {:start, :void, 1, 2},
      {:deadline, 1},
      {:result, 1},
      {:shutdown_result, 1},
      {:committed, 1},
      {:result, 1},
      {:start, :lookup, 2, 2},
      {:down, 2},
      {:committed, 2},
      :poison,
      {:start, :authorize, 3, 2},
      :malformed
    ]

    composite = [
      {:request, 1, 100},
      {:dispatch, 1},
      {:processor_result, 1, :approved},
      {:void, 1},
      {:void_attempt, 1},
      {:processor_void_result, 1, {:error, :timeout}},
      :restart,
      {:void_confirmed, 1},
      {:void_confirmed, 1},
      {:request, 2, 100},
      {:dispatch, 2},
      {:processor_result, 2, :declined},
      :malformed
    ]

    environment = [
      {:deliver, {:void, 1}},
      {:issue, {:authorize, 1, 100}},
      {:deliver, {:authorize, 1, :approved}},
      {:issue, {:authorize, 1, 50}},
      {:issue, {:authorize, 2, 25}},
      {:deliver, {:authorize, 2, :approved}},
      {:deliver, {:authorize, 2, :declined}},
      {:deliver, {:void, 2}},
      {:deliver, {:authorize, 2, :approved}},
      {:deliver, :malformed}
    ]

    exposure = [
      {:local, {:request, 1, 100}},
      {:local, {:dispatch, 1}},
      {:authorize, 1, :approved},
      {:observe, 1},
      {:local, {:void, 1}},
      {:local, {:request, 2, 100}},
      {:void, 1},
      {:confirm, 1},
      {:local, {:request, 2, 100}},
      {:local, {:dispatch, 2}},
      {:authorize, 2, :approved},
      {:observe, 2},
      {:authorize, 1, :approved},
      {:confirm, 1},
      {:local, :restart},
      :malformed
    ]

    trace_cases(Attempts, Attempts.init(), steps(attempts), count) ++
      trace_cases(Composite, Composite.init(100, 2), steps(composite), count) ++
      trace_cases(Environment, Environment.init(), environment, count) ++
      trace_cases(Exposure, Exposure.init(100, 2), steps(exposure), count) ++
      [
        {Attempts, :step, [{40, false, [{7, :void, 1, :stopping}]}, {:shutdown_result, 7}]},
        {Attempts, :step, [{40, false, [{7, :void, 1, :committing}]}, {:result, 7}]},
        {Attempts, :step, [{40, false, [{7, :void, 1, :running}]}, {:result, 7.0}]},
        {Environment, :deliver,
         [{[{1, 100, :issued}], [{1, 0, :voided}]}, {:authorize, 1, :approved}]}
      ]
  end

  defp steps(events), do: Enum.map(events, &{:step, &1})

  defp trace_cases(module, initial, calls, count) do
    {cases, _} =
      Enum.map_reduce(1..count, initial, fn index, state ->
        offset = rem(index - 1, length(calls))
        state = if offset == 0, do: initial, else: state
        {function, event} = Enum.at(calls, offset)
        observation = {module, function, [state, event]}
        next = next_model_state(module, function, apply(module, function, [state, event]))
        {[observation | model_observations(module, state, event)], next}
      end)

    List.flatten(cases)
  end

  defp next_model_state(Composite, :step, {next, _, _}), do: next
  defp next_model_state(Attempts, :step, {next, _}), do: next
  defp next_model_state(Environment, :deliver, {next, _}), do: next
  defp next_model_state(_, _, next), do: next

  defp model_observations(Composite, state, event),
    do: [{Spec, :expected_composite_step, [state, event]}, {Spec, :composite_valid?, [state]}]

  defp model_observations(Exposure, state, _), do: [{Spec, :exposure_valid?, [state]}]
  defp model_observations(_, _, _), do: []

  # The wire representation is tagged, bounded, and never creates atoms.
  def encode(value), do: encode(value, 0)
  defp encode(_, depth) when depth > 64, do: raise(ArgumentError, "term too deep")
  defp encode(value, _) when is_integer(value), do: ["integer", Integer.to_string(value)]

  defp encode(value, _) when is_float(value) do
    <<bits::unsigned-64>> = <<value::float-64>>
    ["float", Integer.to_string(bits)]
  end

  defp encode(value, _) when is_atom(value), do: ["atom", Atom.to_string(value)]

  defp encode(value, depth) when is_tuple(value),
    do: ["tuple", value |> Tuple.to_list() |> Enum.map(&encode(&1, depth + 1))]

  defp encode(value, depth) when is_list(value),
    do: ["list", Enum.map(value, &encode(&1, depth + 1))]

  defp encode(_, _), do: raise(ArgumentError, "unsupported term")

  def decode(wire), do: decode(wire, 0)
  defp decode(_, depth) when depth > 64, do: raise(ArgumentError, "wire too deep")
  defp decode(["integer", value], _) when is_binary(value), do: String.to_integer(value)

  defp decode(["float", value], _) when is_binary(value) do
    bits = String.to_integer(value)

    if bits < 0 or bits >= Bitwise.bsl(1, 64) or Bitwise.band(Bitwise.bsr(bits, 52), 2047) == 2047,
      do: raise(ArgumentError, "invalid finite float bits")

    <<number::float-64>> = <<bits::unsigned-64>>
    number
  end

  defp decode(["atom", value], _) when is_binary(value), do: String.to_existing_atom(value)

  defp decode(["tuple", values], depth) when is_list(values),
    do: values |> Enum.map(&decode(&1, depth + 1)) |> List.to_tuple()

  defp decode(["list", values], depth) when is_list(values),
    do: Enum.map(values, &decode(&1, depth + 1))

  defp decode(_, _), do: raise(ArgumentError, "invalid wire")

  def literal(value), do: value |> encode() |> wire_literal()
  defp wire_literal(["integer", n]), do: "(Lynx.Term.integer (#{n}))"
  defp wire_literal(["atom", name]), do: "(Lynx.Term.atom #{JSON.encode!(name)})"

  defp wire_literal(["float", bits]) do
    bits = String.to_integer(bits)
    sign = if Bitwise.bsr(bits, 63) == 1, do: "true", else: "false"
    exponent = Bitwise.band(Bitwise.bsr(bits, 52), 2047)
    fraction = Bitwise.band(bits, Bitwise.bsl(1, 52) - 1)
    if exponent == 2047, do: raise(ArgumentError, "nonfinite float")
    "(Lynx.Term.float ⟨#{sign}, ⟨#{exponent}, by decide⟩, ⟨#{fraction}, by decide⟩⟩)"
  end

  defp wire_literal(["tuple", values]),
    do: "(Lynx.Term.tuple #[#{Enum.map_join(values, ", ", &wire_literal/1)}])"

  defp wire_literal(["list", values]),
    do: "(Lynx.Term.list [#{Enum.map_join(values, ", ", &wire_literal/1)}])"

  def wire_source([tag, value]) when tag in ["integer", "float", "atom"],
    do: "(HoldLedgerDifferentialCodec.Wire.#{tag} #{JSON.encode!(value)})"

  def wire_source([tag, values]) when tag in ["tuple", "list"],
    do:
      "(HoldLedgerDifferentialCodec.Wire.#{tag} [#{Enum.map_join(values, ", ", &wire_source/1)}])"

  def result(module, function, args) do
    {:ok, apply(module, function, args)}
  rescue
    FunctionClauseError -> {:error, :function_clause}
    ArgumentError -> {:error, :badarg}
  end

  # Every accepted shrink must reproduce the evaluator mismatch. The evaluator
  # must distinguish a semantic mismatch from translation/process failures.
  def minimize(args, mismatch?, budget) when is_list(args) and budget >= 0 do
    {minimal, remaining} = minimize_args(args, mismatch?, budget)
    {minimal, budget - remaining}
  end

  defp minimize_args(args, _, 0), do: {args, 0}

  defp minimize_args(args, mismatch?, budget) do
    candidates =
      for {value, index} <- Enum.with_index(args),
          candidate <- shrinks(value),
          do: List.replace_at(args, index, candidate)

    Enum.reduce_while(candidates, {args, budget}, fn candidate, {_, remaining} ->
      cond do
        remaining == 0 -> {:halt, {args, 0}}
        mismatch?.(candidate) -> {:halt, minimize_args(candidate, mismatch?, remaining - 1)}
        true -> {:cont, {args, remaining - 1}}
      end
    end)
  end

  defp shrinks(n) when is_integer(n) and n != 0,
    do: Enum.uniq([0, div(n, abs(n)), div(n, 2)]) -- [n]

  defp shrinks(n) when is_float(n) and n != 0.0, do: [0.0]

  defp shrinks(value) when is_tuple(value) do
    value
    |> Tuple.to_list()
    |> component_shrinks()
    |> Enum.map(&List.to_tuple/1)
  end

  defp shrinks([]), do: []
  defp shrinks([_ | rest] = value), do: Enum.uniq([[], rest | component_shrinks(value)])
  defp shrinks(_), do: []

  defp component_shrinks(values) do
    for {value, index} <- Enum.with_index(values),
        candidate <- shrinks(value),
        do: List.replace_at(values, index, candidate)
  end

  def assertion({module, function, args}, index, kernel?) do
    name = "#{module}.«#{function}/#{length(args)}»"
    expression = "#{name} #{Enum.map_join(args, " ", &literal/1)}"

    expected =
      case result(module, function, args) do
        {:ok, value} ->
          "(Except.ok #{literal(value)} : Except Lynx.Exception Lynx.Term)"

        {:error, reason} ->
          "(Except.error (Lynx.Exception.error #{literal(reason)}) : Except Lynx.Exception Lynx.Term)"
      end

    compiled =
      "#eval (if reprStr (#{expression}) == reprStr #{expected} then pure () else throw (IO.userError \"differential case #{index}\") : IO Unit)"

    kernel =
      if kernel?,
        do: "\ntheorem kernel_#{index} : (#{expression}) = #{expected} := by rfl",
        else: ""

    compiled <> kernel
  end
end
