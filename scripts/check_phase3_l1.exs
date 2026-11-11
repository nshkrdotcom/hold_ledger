# Research comparison only; no extra registered production claim.
ExUnit.start(autorun: false)
Code.require_file("../test/test_helper.exs", __DIR__)
Code.require_file("../test/laws/l1_find_test.exs", __DIR__)
module = HoldLedger.Laws.L1FindTest
[{_name, laws, translation, _options}] = module.__info__(:attributes)[:proof_groups]
postludes = HoldLedger.ProofCase.batch_postludes!([{module, translation}])
files = HoldLedger.ProofCase.assemble_many([{module, laws}], postludes: postludes)
source = File.read!("verification/research/0300_l1_equivalence.lean")

comparison = %{
  "module" => "HoldLedger0300.L1Equivalence",
  "imports" => ["Erlang.postlude"],
  "file" => "verification/research/0300_l1_equivalence.lean",
  "contents" => [],
  "preludes" => [
    %{
      "source" => source,
      "file" => "verification/research/0300_l1_equivalence.lean",
      "span" => [1, 1],
      "indentation" => 0
    }
  ]
}

reports =
  Lynx.Commands.verify!(Path.expand("deps/lynx/Lean"), files ++ [comparison],
    options: [maxHeartbeats: 16_000_000],
    debug_dir: "tmp/verification/0300-l1-equivalence",
    debug: :lean
  )

File.write!("tmp/verification/0300-l1-equivalence.json", JSON.encode!(reports))

unless Enum.all?(reports, &(&1.status == :ok and &1.cached == false and &1.diagnostics == [])),
  do: raise("L1 theorem comparison failed: #{inspect(reports)}")

IO.puts("Original L1 proof and migrated theorem have kernel-checked identical types (cold).")
