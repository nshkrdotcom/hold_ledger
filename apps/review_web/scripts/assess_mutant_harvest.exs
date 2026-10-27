# Run from apps/review_web in the UNPATCHED checkout, after the Python harvest.
# Example: mix run scripts/assess_mutant_harvest.exs -- ../../tmp/verification/mutant-harvest.json
alias HoldLedgerReview.{Adversarial, Anchor, Claims, Config, TermCodec}

[path] = System.argv()
root = Config.root()
full = Path.expand(path, File.cwd!())
if not String.starts_with?(Path.relative_to(full, root), "tmp/verification/"), do: raise("unsafe report path")
report = full |> File.read!() |> Jason.decode!()
if report["mode"] != "EXECUTED", do: raise("no executed harvest")
if report["original_ledger_sha256"] != Anchor.sha(File.read!(Path.join(root, "lib/hold_ledger/ledger.ex"))),
  do: raise("original reducer drift")
if report["original_spec_sha256"] != Anchor.sha(File.read!(Path.join(root, "lib/hold_ledger/spec.ex"))),
  do: raise("original specification drift")
:ok = Claims.freshness()

results = for {id, observation} <- Enum.sort(report["mutants"]), into: %{} do
  result = cond do
    observation["provenance"] != "mutant_observed" ->
      %{"status" => "unexecuted", "tested_catchers" => [], "unprobeable" => [],
        "reason" => "The isolated patched output was not successfully observed"}
    true ->
      input = observation["input"]
      event = Map.take(input["event"], ~w(type key amount))
      with {:ok, _} <- TermCodec.decode_event(event),
           {:ok, _} <- TermCodec.decode_output(observation["output"]),
           {:ok, evidence, _details} <- Adversarial.evaluate(%{
             "before" => input["before"], "event" => event,
             "output" => observation["output"], "follow_on" => nil}) do
        catchers = for row <- evidence["law_rows"], row["label"] == "catches", do: row["slug"]
        unprobeable = for row <- evidence["law_rows"], row["label"] == "cant_check",
          do: %{"law" => row["slug"], "reason" => row["reason"]}
        %{"status" => "original_source_pointwise_evaluated", "tested_catchers" => catchers,
          "tested_laws" => Enum.map(evidence["law_rows"], & &1["slug"]),
          "unprobeable" => unprobeable,
          "reason" => if(catchers == [], do: "Candidate gap among examined supported bindings only; rest of catalog unexamined", else: "Named original-source pointwise catchers only")}
      else
        _ -> %{"status" => "unprobeable", "tested_catchers" => [], "unprobeable" => ["unsupported_native_event_or_output"],
               "reason" => "No original source evaluator adapter for this native operation; not an observed escape"}
      end
  end
  {id, result}
end

snapshot = Claims.snapshot()
output = %{"original_claim_manifest_sha256" => snapshot.source.sha256,
  "original_evaluator_id" => snapshot.evaluator_id,
  "original_ledger_sha256" => report["original_ledger_sha256"],
  "harvest_report_sha256" => Anchor.sha(File.read!(full)),
  "mutant_catcher_map" => results,
  "disclaimer" => "Pointwise tested binding only. No catcher is a candidate coverage gap, not proof of total catalog failure. Formal check results are separate."}
dest = Path.join(Path.dirname(full), "mutant-catchers.json")
File.write!(dest, Jason.encode!(output, pretty: true) <> "\n")
IO.puts("Original-source assessment written to #{dest}; never reclassifies synthetic fixtures as observed")
