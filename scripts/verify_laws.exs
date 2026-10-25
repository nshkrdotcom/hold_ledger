# Run one dependency-ordered cold verification request so shared proofs elaborate once.
ExUnit.start(autorun: false)
Code.require_file("../test/test_helper.exs", __DIR__)

[selection_path, output_path, export_path] = System.argv()
selection = selection_path |> File.read!() |> JSON.decode!()

groups =
  for entry <- selection do
    compiled = Code.require_file(entry["file"])

    {module, _} =
      Enum.find(compiled, fn {module, _} -> function_exported?(module, :__ex_unit__, 0) end)

    [{_name, laws, suffixes, cutoffs, preludes, _options}] =
      module.__info__(:attributes)[:proof_groups]

    if map_size(suffixes) != 0 or MapSet.size(cutoffs) != 0 or preludes != [] do
      raise "Batch verification does not accept per-group translation overrides"
    end

    {module, laws}
  end

mode =
  if System.get_env("HOLD_LEDGER_PROOF_CACHE") == "1",
    do: "development cache; not acceptance",
    else: "cold, no proof cache"

IO.puts("Assembling #{length(groups)} law groups with shared theory (#{mode})")
files = HoldLedger.ProofCase.assemble_many(groups)
opts = [options: [maxHeartbeats: 16_000_000], debug_dir: "tmp/verification/shared", debug: :lean]
opts = if export_path == "none", do: opts, else: Keyword.put(opts, :export, export_path)
IO.puts("Checking #{length(files)} dependency-ordered translated and shared modules")
reports = Lynx.Commands.verify!(Path.expand("deps/lynx/Lean"), files, opts)

Enum.each(reports, fn report ->
  for diagnostic <- report.diagnostics, diagnostic.severity == :error do
    IO.puts(:stderr, "#{diagnostic.file}:#{diagnostic[:line]}: #{diagnostic.message}")
  end

  IO.puts(
    "#{if report.status == :ok, do: "Checked", else: "Failed to check"} #{report.module} in #{report.time_ms}ms (#{report.status}, cached=#{report.cached})"
  )
end)

results =
  Enum.zip_with(selection, groups, fn entry, {module, laws} ->
    passed =
      try do
        HoldLedger.ProofCase.validate_reports!(reports, module, laws)
        true
      rescue
        ExUnit.AssertionError -> false
      end

    {entry["slug"],
     %{
       passed: passed,
       module: Atom.to_string(module),
       laws: Enum.map(laws, fn {name, arity} -> "#{name}/#{arity}" end)
     }}
  end)
  |> Map.new()

File.write!(output_path, JSON.encode!(%{laws: results, reports: reports}))

if Enum.all?(results, fn {_, result} -> result.passed end) do
  IO.puts("Result: #{length(selection)} passed")
else
  System.halt(2)
end
