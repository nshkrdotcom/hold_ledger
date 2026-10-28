# Operator-run integration check. IDs point to independently selected, trusted,
# staged experiments, not uploaded source. No provider or formal check is sent.
alias HoldLedgerReview.{
  Adversarial,
  Canonical,
  Part3Diagnostics,
  Part3Result,
  Part3Runner,
  Part3Snapshots,
  Part3Store
}

[ids_file] = Enum.drop_while(System.argv(), &(&1 == "--"))
ids = ids_file |> File.read!() |> Jason.decode!()
{:ok, witness} = Adversarial.seed("P04")

wait = fn recur, id, attempt_ids, deadline ->
  {:ok, p, :ok} = Part3Store.get(id)
  attempts = Enum.filter(p["replay_attempts"], &(&1["id"] in attempt_ids))

  if Enum.all?(attempts, &(&1["status"] not in ~w(queued running))) do
    p
  else
    receive do
      {:part3_updated, ^id} -> recur.(recur, id, attempt_ids, deadline)
    after
      max(0, deadline - System.monotonic_time(:millisecond)) -> raise "replay did not complete"
    end
  end
end

results =
  for name <- ~w(unchanged observed exact_fit helper permitted) do
    {:ok, package} = Part3Store.create(ids["baseline"], ids[name])
    id = package["id"]
    Phoenix.PubSub.subscribe(HoldLedgerReview.PubSub, "part3:" <> id)
    started = System.monotonic_time(:millisecond)
    {:ok, attempts} = Part3Runner.replay(id, witness)
    done = wait.(wait, id, Enum.map(attempts, & &1["id"]), started + 130_000)
    pair = done["replay_attempts"]

    unless Enum.all?(pair, &(&1["status"] == "succeeded")),
      do: raise("actual worker failure: #{inspect(pair)}")

    [a, b] = pair
    :ok = Part3Result.validate(a["result"], done, a, witness)
    :ok = Part3Result.validate(b["result"], done, b, witness)
    found = Part3Diagnostics.compare(done, witness, a["result"], b["result"])
    kinds = Enum.map(found, & &1["kind"])

    expected =
      case name do
        "unchanged" -> nil
        "observed" -> "observed_behavioral_difference"
        "permitted" -> "permitted_alternative_output"
        _ -> "lost_domain_input"
      end

    unless (is_nil(expected) and kinds == []) or expected in kinds,
      do: raise("missing #{name} distinction: #{inspect(found)}")

    if name == "permitted" and
         a["result"]["evaluation"]["actual"] != b["result"]["evaluation"]["actual"],
       do: raise("contract-only fixture unexpectedly changed implementation output")

    {:ok, []} = Part3Runner.replay(id, witness)
    # Validate actual results in reverse completion order in a fresh package.
    {:ok, reverse} = Part3Store.create(ids["baseline"], ids[name])
    {:ok, _queued, reverse_attempts} = Part3Store.queue_replay(reverse["id"], witness)

    Enum.zip(reverse_attempts, pair)
    |> Enum.reverse()
    |> Enum.each(fn {attempt, observed} ->
      {:ok, _} = Part3Store.running(reverse["id"], attempt["id"])

      body =
        observed["result"]
        |> Map.delete("completion_digest")
        |> Map.put("request_id", attempt["id"])

      # Same source/input/context; only the new internal attempt identity changes.
      rebound = Map.put(body, "completion_digest", Canonical.digest(body))
      {:ok, _} = Part3Store.complete_replay(reverse["id"], attempt["id"], rebound)
    end)

    {:ok, reversed, :ok} = Part3Store.get(reverse["id"])

    unless Enum.map(reversed["evidence"], & &1["kind"]) == kinds,
      do: raise("order-dependent findings")

    # Forgery, source identity, loaded-code and malformed-result refusal, using
    # an actually executed result rather than a handwritten synthetic response.
    for changed <- [
          Map.put(a["result"], "loaded_evaluator_id", String.duplicate("0", 64)),
          Map.put(a["result"], "context_digest", String.duplicate("0", 64)),
          Map.put(a["result"], "claims", nil)
        ] do
      body = Map.delete(changed, "completion_digest")
      forged = Map.put(body, "completion_digest", Canonical.digest(body))
      {:error, :invalid_or_forged_replay_result} = Part3Result.validate(forged, done, a, witness)
    end

    {:ok, terminal} = Part3Store.create(ids["baseline"], ids[name])
    {:ok, _, [late, other]} = Part3Store.queue_replay(terminal["id"], witness)
    {:ok, _} = Part3Store.running(terminal["id"], late["id"])
    {:ok, _} = Part3Store.fail_attempt(terminal["id"], late["id"], :timeout)

    {:error, :late_or_terminal_completion} =
      Part3Store.complete_replay(terminal["id"], late["id"], a["result"])

    {:ok, _} = Part3Store.fail_attempt(terminal["id"], other["id"], :cancelled)
    {:ok, _, retry} = Part3Store.queue_replay(terminal["id"], witness)
    unless length(retry) == 2, do: raise("failed pair cached")
    Enum.each(retry, &Part3Store.fail_attempt(terminal["id"], &1["id"], :cancelled))
    {:ok, snapshot} = Part3Snapshots.load(ids[name])

    %{
      "experiment" => name,
      "package_id" => id,
      "baseline_id" => ids["baseline"],
      "proposal_id" => ids[name],
      "input_digest" => Canonical.digest(witness),
      "completion_digests" => Enum.map(pair, & &1["completion_digest"]),
      "loaded_evaluator_ids" => Enum.map(pair, & &1["result"]["loaded_evaluator_id"]),
      "source_generation" => b["result"]["source_generation"],
      "evaluator_id" => snapshot["evaluator_id"],
      "findings" => kinds,
      "elapsed_ms" => System.monotonic_time(:millisecond) - started,
      "reverse_order" => "actual responses, admission replay only",
      "cache" => "exact pair reused; failed pair refused"
    }
  end

output = Path.join(HoldLedgerReview.Config.root(), "tmp/part3_completion/real-replay.json")

File.write!(
  output,
  Jason.encode!(
    %{
      "experiments" => results,
      "scope" => "controlled pointwise executions; no proof or policy change"
    }, pretty: true) <> "\n"
)

IO.puts(
  "PASS: five actual isolated replay pairs, provenance/forgery/cache/terminal checks: #{output}"
)
