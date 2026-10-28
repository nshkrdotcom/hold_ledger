# Actual bounded isolated search over the selected helper experiment. A result
# is a finite set of executions, never solver evidence or universal acceptance.
alias HoldLedgerReview.{Adversarial, Config, Part3BoundarySearch, Part3Runner, Part3Store}
[ids_file] = Enum.drop_while(System.argv(), &(&1 == "--"))
ids = ids_file |> File.read!() |> Jason.decode!()
{:ok, witness} = Adversarial.seed("P04")
{:ok, p} = Part3Store.create(ids["baseline"], ids["helper"])
cases = Part3BoundarySearch.cases(p, witness)
started = System.monotonic_time(:millisecond)
{:ok, pid} = Part3Runner.search(p["id"], witness)
ref = Process.monitor(pid)

receive do
  {:DOWN, ^ref, :process, ^pid, :normal} -> :ok
  {:DOWN, ^ref, :process, ^pid, reason} -> raise("search crashed: #{inspect(reason)}")
after
  600_000 -> raise("bounded search did not finish")
end

{:ok, done, :ok} = Part3Store.get(p["id"])
attempts = done["replay_attempts"]

unless length(attempts) == 2 * length(cases) and
         Enum.all?(attempts, &(&1["status"] == "succeeded")),
       do:
         raise(
           "search incomplete: #{inspect(Enum.map(attempts, &Map.take(&1, ~w(status diagnostics input_digest))))}"
         )

result = %{
  "package_id" => p["id"],
  "baseline_id" => ids["baseline"],
  "proposal_id" => ids["helper"],
  "cases" => length(cases),
  "attempts" => length(attempts),
  "all_succeeded" => true,
  "elapsed_ms" => System.monotonic_time(:millisecond) - started,
  "limits" => Part3BoundarySearch.limits(),
  "findings" => Enum.frequencies_by(done["evidence"], & &1["kind"])
}

File.write!(
  Path.join(Config.root(), "tmp/part3_completion/bounded-search.json"),
  Jason.encode!(result, pretty: true) <> "\n"
)

IO.puts(
  "PASS: #{length(cases)} cases through actual isolated pairs; general relations unresolved"
)
