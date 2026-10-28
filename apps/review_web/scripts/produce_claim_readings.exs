# Run from the root project with MIX_ENV=test using scripts/local_run.py.
# Invokes original translation/elaboration. This is focused evidence, never a
# replacement for formal_gate.py or ProofEvidence required-scope acceptance.
ExUnit.start(autorun: false)
Code.require_file("test/support/proof_case.ex")

selected = [
  {"po_a2", HoldLedger.Laws.PoA2Test},
  {"po_b1_void", HoldLedger.Laws.PoB1VoidTest},
  {"po_exposure_retain", HoldLedger.Laws.PoExposureRetainTest}
]

sha = fn bytes -> :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower) end
paths = Enum.uniq(Path.wildcard("lib/**/*.ex") ++ Path.wildcard("test/laws/*.exs") ++
  Path.wildcard("test/support/**/*.{ex,lean,json}") ++ Path.wildcard("verification/*.json") ++
  Path.wildcard("scripts/*.py") ++ ["mix.exs", "mix.lock", "uv.lock", ".tool-versions", "lean-toolchain",
  "apps/review_web/scripts/produce_claim_readings.exs"])
sources = Map.new(Enum.filter(paths, &File.regular?/1), &{&1, sha.(File.read!(&1))})
identity = sha.(:erlang.term_to_binary(Enum.sort(sources)))
dir = Path.join("tmp/verification/claim-reading", identity)
File.mkdir_p!(dir)
claims = Map.new(selected, fn {slug, module} ->
  Code.compile_file("test/laws/#{slug}_test.exs")
  [{_, laws, suffixes, cutoffs, preludes, options}] = module.__info__(:attributes)[:proof_groups]
  files = HoldLedger.ProofCase.assemble(module, laws, suffixes, cutoffs, preludes)
  debug = Path.join(dir, slug)
  started = System.monotonic_time(:millisecond)
  reports = Lynx.Commands.verify!(Path.expand("deps/lynx/Lean"), files,
    options: options, debug_dir: debug, debug: :lean, check_source: true)
  :ok = HoldLedger.ProofCase.validate_reports!(reports, module, laws)
  artifacts = Path.wildcard(Path.join(debug, "**/*.lean")) |> Enum.map(fn path ->
    %{"path" => path, "sha256" => sha.(File.read!(path)), "bytes" => File.stat!(path).size}
  end)
  if artifacts == [], do: raise("Original producer emitted no Lean source")
  IO.puts("#{slug}: original Lean elaboration OK; #{length(artifacts)} source artifacts")
  {slug, %{"status" => "elaborated", "elapsed_ms" => System.monotonic_time(:millisecond) - started,
    "artifacts" => artifacts, "reports" => Enum.map(reports, fn report ->
      %{"module" => report.module, "status" => Atom.to_string(report.status), "cached" => report.cached}
    end), "full_acceptance" => false}}
end)
if not Enum.all?(sources, fn {path, digest} -> sha.(File.read!(path)) == digest end),
  do: raise("Source drift during production; refusing index")
index = %{"schema_version" => 1, "sources" => sources, "claims" => claims,
  "scope" => "focused_original_lean_elaboration_not_full_acceptance", "generated_at" => DateTime.to_iso8601(DateTime.utc_now())}
File.write!(Path.join(dir, "index.json"), Jason.encode!(index, pretty: true))
File.cp!(Path.join(dir, "index.json"), "tmp/verification/claim-reading/index.json")
