# Run from the root project with MIX_ENV=test using scripts/local_run.py.
# Invokes original translation/elaboration. This is focused evidence, never a
# replacement for formal_gate.py or ProofEvidence required-scope acceptance.
ExUnit.start(autorun: false)
Code.require_file("test/support/proof_case.ex")
System.delete_env("HOLD_LEDGER_PROOF_CACHE")

selected = [
  {"po_a2", HoldLedger.Laws.PoA2Test},
  {"po_b1_void", HoldLedger.Laws.PoB1VoidTest},
  {"po_exposure_retain", HoldLedger.Laws.PoExposureRetainTest}
]

dir = Path.join("tmp/verification/claim-reading", "run-#{System.system_time(:microsecond)}")
File.mkdir_p!(dir)

claims =
  Map.new(selected, fn {slug, module} ->
    Code.compile_file("test/laws/#{slug}_test.exs")
    [{_, laws, translation, options}] = module.__info__(:attributes)[:proof_groups]
    files = HoldLedger.ProofCase.assemble(module, laws, translation)
    debug = Path.join(dir, slug)
    started = System.monotonic_time(:millisecond)

    reports =
      Lynx.Commands.verify!(Path.expand("deps/lynx/Lean"), files,
        options: options,
        debug_dir: debug,
        debug: :lean,
        check_source: true
      )

    :ok = HoldLedger.ProofCase.validate_reports!(reports, module, laws)

    unless Enum.all?(reports, fn report ->
             report.status == :ok and report.cached == false and
               Enum.all?(report.diagnostics, &(&1.severity not in [:error, :warning]))
           end),
           do: raise("Focused reading did not produce clean uncached Lean reports")

    artifacts =
      Path.wildcard(Path.join(debug, "**/*.lean"))
      |> Enum.with_index()
      |> Enum.map(fn {path, id} -> %{"path" => path, "id" => Integer.to_string(id)} end)

    if artifacts == [], do: raise("Original producer emitted no Lean source")
    IO.puts("#{slug}: original Lean elaboration OK; #{length(artifacts)} source artifacts")

    {slug,
     %{
       "status" => "elaborated",
       "elapsed_ms" => System.monotonic_time(:millisecond) - started,
       "artifacts" => artifacts,
       "reports" =>
         Enum.map(reports, fn report ->
           %{
             "module" => report.module,
             "status" => Atom.to_string(report.status),
             "cached" => report.cached
           }
         end),
       "full_acceptance" => false
     }}
  end)

index = %{
  "schema_version" => 2,
  "claims" => claims,
  "scope" => "focused_original_lean_elaboration_not_full_acceptance",
  "generated_at" => DateTime.to_iso8601(DateTime.utc_now())
}

File.write!(Path.join(dir, "index.json"), Jason.encode!(index, pretty: true))
published = "tmp/verification/claim-reading/index.json"
staged = published <> ".pending-#{System.unique_integer([:positive])}"
File.cp!(Path.join(dir, "index.json"), staged)
File.rename!(staged, published)
