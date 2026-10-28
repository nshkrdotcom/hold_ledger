defmodule HoldLedgerReview.VisualLab do
  @moduledoc "Bounded candidate variations through the original evaluator; not a general fuzzer."
  alias HoldLedgerReview.{ClaimProbe, Claims, Contrast, TermCodec, Trace}

  def hunt(slug, step, seed, budget) when is_integer(seed) and budget in 0..24 do
    started = System.monotonic_time(:millisecond)
    result = hunt_cases(slug, step, seed, budget, started)
    Map.merge(result, %{seed: seed, elapsed_ms: System.monotonic_time(:millisecond) - started})
  end

  defp hunt_cases(slug, step, seed, budget, started) do
    with {:ok, _} <- Claims.claim(slug),
         {:ok, before} <- TermCodec.decode_state(step["before"]),
         {:ok, event} <- TermCodec.decode_event(step["event"]),
         {:ok, identity} <- Trace.identity() do
      candidates(step, seed)
      |> Enum.take(budget)
      |> Enum.reduce_while(%{status: "budget_exhausted", cases: 0, identity: identity}, fn output,
                                                                                           result ->
        inspect_candidate(output, slug, before, event, result, started)
      end)
    else
      _ -> %{status: "unavailable", cases: 0}
    end
  end

  defp inspect_candidate(output, slug, before, event, result, started) do
    if System.monotonic_time(:millisecond) - started >= 3000 do
      {:halt, result}
    else
      evaluate_candidate(output, slug, before, event, result)
    end
  end

  defp evaluate_candidate(output, slug, before, event, result) do
    result = %{result | cases: result.cases + 1}

    with {:ok, native} <- TermCodec.decode_output(output),
         %{status: :catches} <- ClaimProbe.probe(slug, before, event, native) do
      {:halt, Map.merge(result, %{status: "found", output: output})}
    else
      _ -> {:cont, result}
    end
  end

  defp candidates(step, seed) do
    actual = step["output"]

    options = [
      actual,
      Contrast.early_release(step),
      put_in(actual, ["after", "used_amount"], 0),
      put_in(actual, ["after", "used_holds"], 0),
      Map.put(actual, "effects", []),
      %{"after" => step["before"], "result" => "insufficient_amount", "effects" => []}
    ]

    state = :rand.seed_s(:exsss, {seed + 1, seed + 2, seed + 3})

    options
    |> Enum.map_reduce(state, fn value, rng ->
      {key, next} = :rand.uniform_s(rng)
      {{key, value}, next}
    end)
    |> elem(0)
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.map(&elem(&1, 1))
  end
end
