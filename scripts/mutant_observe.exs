# Executed only in an isolated disposable checkout by harvest_mutants.py.
# The registered input is checked against the exact counterexample source SHA.
# This offline tool uses the same strict output/state codec as the application,
# without loading the Phoenix app or opening a server.
Code.require_file("apps/review_web/lib/hold_ledger_review/term_codec.ex")

alias HoldLedger.{Ledger, Spec}
alias HoldLedgerReview.TermCodec

[id] = System.argv()
inputs = File.read!("scripts/mutant_inputs.json") |> :json.decode()
entry = Map.fetch!(inputs, id)
source = File.read!(entry["counterexample_path"])
sha = :crypto.hash(:sha256, source) |> Base.encode16(case: :lower)
if sha != entry["counterexample_sha256"], do: raise("counterexample source changed")

{:ok, before} = TermCodec.decode_state(entry["before"])
event = case entry["event"] do
  %{"type" => "restart", "key" => nil} -> :restart
  %{"type" => "retry", "key" => key} -> {:retry, key}
  %{"type" => "transport_ack", "key" => key} -> {:transport_ack, key}
  %{"type" => "processor_result", "key" => key, "outcome" => "declined"} ->
    {:processor_result, key, :declined}
  %{"type" => type} = object
  when type in ["request", "timeout", "void", "dispatch"] ->
    {:ok, decoded} = TermCodec.decode_event(Map.take(object, ["type", "key", "amount"]))
    decoded
end

if not Spec.valid?(before), do: raise("untrusted invalid original input")
actual = Ledger.step(before, event)
oracle = Spec.expected_step(before, event)
{:ok, output} = TermCodec.encode_output(actual)
{:ok, oracle_json} = TermCodec.encode_output(oracle)
payload = %{
  "input_id" => id,
  "before" => entry["before"], "event" => entry["event"],
  "output" => output, "oracle" => oracle_json,
  "input_matches_original_spec" => actual == oracle,
  "counterexample_sha256" => sha
}
IO.puts("MUTANT_OBSERVATION_JSON:" <> IO.iodata_to_binary(:json.encode(payload)))
