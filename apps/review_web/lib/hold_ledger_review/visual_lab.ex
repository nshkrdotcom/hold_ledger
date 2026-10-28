defmodule HoldLedgerReview.VisualLab do
  @moduledoc "Presentation experiments; never a proof or policy acceptance authority."
  alias HoldLedger.{Environment, Exposure}
  alias HoldLedgerReview.{ClaimProbe, Claims, Contrast, TermCodec, Trace}

  @events [
    {"Empty account", nil},
    {"Reserve 100¢", {:local, {:request, 1, 100}}},
    {"Send authorization", {:local, {:dispatch, 1}}},
    {"Processor approves", {:authorize, 1, :approved}},
    {"Observe approval", {:observe, 1}},
    {"Request void", {:local, {:void, 1}}},
    {"Processor voids", {:void, 1}},
    {"Observe confirmation", {:confirm, 1}},
    {"Delayed authorization", {:authorize, 1, :approved}}
  ]

  def environment(fencing, durable) when is_boolean(fencing) and is_boolean(durable) do
    @events
    |> Enum.map_reduce(Exposure.init(100, 2), fn {label, event}, state ->
      next = if event, do: Exposure.step(state, event), else: state
      {{label, next}, next}
    end)
    |> elem(0)
    |> Enum.with_index()
    |> Enum.map(&environment_frame(&1, fencing, durable))
  end

  defp environment_frame({{label, {{ledger, _}, {issued, records}}}, index}, fencing, durable) do
    lost = not durable and index >= 4
    resurrected = not fencing and index == 8
    local = if lost, do: {100, 2, 0, 0, []}, else: ledger
    remote = if lost or resurrected, do: [{1, 100, :approved}], else: records
    {:ok, json} = TermCodec.encode_state(local)

    %{
      index: index,
      label: frame_label(label, lost, index),
      local: elem(local, 2),
      remote: remote_total(remote),
      ledger: json,
      covered: Environment.covered?({issued, remote}, local),
      remote_status: remote_status(remote),
      provenance:
        if(lost or resurrected,
          do: "counterfactual illustration",
          else: "original Exposure model"
        )
    }
  end

  defp frame_label(_, true, 4), do: "Lose unsynced local state"
  defp frame_label(_, true, 5), do: "Void work was not durably recorded"
  defp frame_label(_, true, 6), do: "Processor still holds the authorization"
  defp frame_label(_, true, 7), do: "No local identity to reconcile"
  defp frame_label(_, true, 8), do: "Remote exposure remains orphaned"
  defp frame_label(label, _, _), do: label

  defp remote_total(records),
    do:
      Enum.reduce(records, 0, fn
        {_, amount, :approved}, sum -> sum + amount
        _, sum -> sum
      end)

  defp remote_status([{_, _, status} | _]), do: Atom.to_string(status)
  defp remote_status([]), do: "not delivered"

  def proof_frames(reading) do
    reading["proof_steps"]
    |> Enum.with_index()
    |> Enum.map(fn {step, index} ->
      %{
        index: index,
        title: step["title"],
        facts: Enum.take(facts(reading["slug"]), index + 1),
        goal: goal(reading["slug"], index, length(reading["proof_steps"])),
        code: step["code"],
        path: step["path"],
        line: step["line"],
        provenance: "illustrated proof state · source-guided, not Lean Infoview output"
      }
    end)
  end

  defp facts("po_exposure_retain"),
    do: [
      "valid : Spec.valid?(state) = true",
      "found : lookup(entries, key) = {:ok, {key, amount, status}}",
      "protected : status ∈ {sent, unknown, authorized, voiding}",
      "no_release : ¬ release_evidence?(event, key)",
      "retained : lookup(next.entries, key) preserves key and amount"
    ]

  defp facts("po_a2"),
    do: [
      "compatible : Ledger.find and Spec.lookup agree on proper entries",
      "typed : key and amount are integers; amount > 0",
      "eligible : valid(s) ∧ fresh(key) ∧ slots available ∧ amount ≤ remaining",
      "find_eq : Ledger.find(entries, key) = :not_found",
      "request : insert {key, amount, :reserved}; increment both counters",
      "bounds : used_amount + amount ≤ limit; used_holds + 1 ≤ slots"
    ]

  defp facts(_),
    do: [
      "valid : Spec.valid?(state) = true",
      "preserved : transition maintains valid accounting",
      "output : next state satisfies validity"
    ]

  defp goal("po_a2", index, count) when index == count - 1,
    do: "capacity bounds ⇒ exact admitted counters and independent reference agree"

  defp goal("po_a2", _, _),
    do: "eligible(s, key, amount) ⇒ request(s, key, amount) = required admitted output"

  defp goal("po_exposure_retain", index, count) when index == count - 1,
    do: "retained_lookup ⇒ key and amount remain in the holding set"

  defp goal("po_exposure_retain", _, _),
    do: "valid state ∧ protected entry ∧ no release evidence ⇒ exposed_entry?(next, key, amount)"

  defp goal(_, _, _), do: "valid starting state ⇒ valid state after this transition"

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
