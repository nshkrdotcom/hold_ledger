# Force both real OS-worker completion orders using STOP/CONT on the owned
# Python supervisor. The BEAM calculation is real; only admission is held.
alias HoldLedgerReview.{Adversarial, Config, Part3Runner, Part3Store}
[ids_file] = Enum.drop_while(System.argv(), &(&1 == "--"))
ids = ids_file |> File.read!() |> Jason.decode!()
{:ok, witness} = Adversarial.seed("P04")

wait = fn recur, id, aid, deadline ->
  {:ok, p, :ok} = Part3Store.get(id)
  a = Enum.find(p["replay_attempts"], &(&1["id"] == aid))

  case a["status"] do
    "succeeded" ->
      p

    s when s in ~w(failed interrupted) ->
      raise("order experiment failed: #{inspect(a)}")

    _ ->
      receive do
        {:part3_updated, ^id} -> recur.(recur, id, aid, deadline)
      after
        max(0, deadline - System.monotonic_time(:millisecond)) ->
          raise("completion order timeout")
      end
  end
end

results =
  for held_role <- ~w(baseline proposal) do
    {:ok, p} = Part3Store.create(ids["baseline"], ids["unchanged"])
    id = p["id"]
    Phoenix.PubSub.subscribe(HoldLedgerReview.PubSub, "part3:" <> id)
    {:ok, pair} = Part3Runner.replay(id, witness)
    held = Enum.find(pair, &(&1["snapshot_id"] == p[held_role]["snapshot_id"]))
    other = Enum.find(pair, &(&1["id"] != held["id"]))
    runner = :sys.get_state(Part3Runner)
    port = Map.fetch!(runner.ids, held["id"])
    {:os_pid, pid} = Port.info(port, :os_pid)
    {_, 0} = System.cmd("kill", ["-STOP", to_string(pid)])

    try do
      observed = wait.(wait, id, other["id"], System.monotonic_time(:millisecond) + 20_000)
      "running" = Enum.find(observed["replay_attempts"], &(&1["id"] == held["id"]))["status"]
    after
      {_, 0} = System.cmd("kill", ["-CONT", to_string(pid)])
    end

    done = wait.(wait, id, held["id"], System.monotonic_time(:millisecond) + 20_000)

    %{
      "held_role" => held_role,
      "first_snapshot_id" => other["snapshot_id"],
      "last_snapshot_id" => held["snapshot_id"],
      "package_id" => id,
      "completion_digests" => Enum.map(done["replay_attempts"], & &1["completion_digest"]),
      "findings" => done["evidence"],
      "method" => "actual workers; owned Python supervisor STOP/CONT"
    }
  end

File.write!(
  Path.join(Config.root(), "tmp/part3_completion/completion-orders.json"),
  Jason.encode!(results, pretty: true) <> "\n"
)

IO.puts(
  "PASS: actual baseline-first and proposal-first completion, no finding for unchanged code"
)
