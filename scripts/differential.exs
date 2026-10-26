# Run with MIX_ENV=test through the local tool wrapper; actual translated code is evaluated.
Code.require_file("../test/support/differential.ex", __DIR__)
Code.require_file("../test/support/fixtures.ex", __DIR__)
Code.require_file("../test/support/generators.ex", __DIR__)
alias HoldLedger.{Attempts, Composite, Differential, Environment, Exposure, Ledger, Spec}

source_paths =
  Path.wildcard("lib/**/*.ex") ++
    [
      "test/support/differential.ex",
      "test/support/fixtures.ex",
      "test/support/generators.ex",
      "scripts/local_run.py",
      "mix.exs",
      ".tool-versions",
      "lean-toolchain",
      "scripts/differential.exs",
      "scripts/run_differential.py",
      "verification/DifferentialCodec.lean",
      "mix.lock"
    ]

source_manifest = fn ->
  Map.new(source_paths, fn path ->
    {path, Base.encode16(:crypto.hash(:sha256, File.read!(path)), case: :lower)}
  end)
end

source_sha256 = source_manifest.()
:rand.seed(:exsss, {41, 73, 109})
base = Ledger.init(100, 2)

edges = [
  {Ledger, :find, [[], 1]},
  {Ledger, :step, [base, :malformed_event]},
  {Spec, :valid?, [:not_a_state]},
  {Ledger, :init, [100, 2]},
  {Ledger, :init, [-1, 2]},
  {Ledger, :step, [base, {:request, 1, 100}]},
  {Ledger, :step, [base, {:request, 1.0, 100}]},
  {Ledger, :step, [base, {:request, 1, 0}]},
  {Spec, :valid?, [base]},
  {Spec, :valid?, [{100, 2, 0.0, 0, []}]}
]

count =
  case System.argv() do
    [] -> 100
    [n] -> String.to_integer(n)
  end

if count < 1 or count > 10_000, do: raise(ArgumentError, "sample count outside 1..10000")

{samples, _state} =
  Enum.map_reduce(1..count, base, fn _, state ->
    key = :rand.uniform(6)

    event =
      Enum.at(
        [
          {:request, key, :rand.uniform(100)},
          {:dispatch, key},
          {:void, key},
          {:processor_result, key, :approved},
          {:processor_result, key, :declined},
          {:timeout, key},
          {:retry, key},
          {:void_confirmed, key},
          :restart
        ],
        :rand.uniform(9) - 1
      )

    {next, _, _} = Ledger.step(state, event)
    {[{Ledger, :step, [state, event]}, {Spec, :expected_step, [state, event]}], next}
  end)

fenced =
  elem(
    Environment.deliver(Environment.issue(Environment.init(), {:authorize, 1, 100}), {:void, 1}),
    0
  )

independent_cases =
  HoldLedger.TestGenerators.independent_state()
  |> StreamData.bind(fn state ->
    StreamData.map(HoldLedger.TestGenerators.event_for_key(1), &{state, &1})
  end)
  |> StreamData.seeded(4_173_109)
  |> Enum.take(count)
  |> Enum.flat_map(fn {state, event} ->
    [{Ledger, :step, [state, event]}, {Spec, :expected_step, [state, event]}]
  end)

cases =
  edges ++
    independent_cases ++
    [
      {Environment, :deliver, [fenced, {:authorize, 1, :approved}]},
      {Environment, :deliver, [Environment.init(), {:void, 1}]},
      {Composite, :step, [Composite.init(100, 2), {:request, 1, 100}]},
      {Attempts, :step, [Attempts.init(), {:start, :void, 1, 32}]}
    ] ++ List.flatten(samples) ++ Differential.model_cases(count)

files =
  Enum.reduce(
    [Ledger, Spec, Environment, Composite, Attempts, Exposure],
    Lynx.Translation.new(),
    fn module, translation ->
      translation
      |> Lynx.Translation.add(elem(:code.get_object_code(module), 1))
      |> Lynx.Translation.translate(module, module.__info__(:functions))
    end
  )
  |> Lynx.Translation.assemble(cache: false)

codec_path = Path.expand("tmp/differential/HoldLedgerDifferentialCodec.olean")
File.mkdir_p!(Path.dirname(codec_path))

{codec_output, codec_status} =
  System.cmd(
    "lake",
    [
      "env",
      "lean",
      "-R",
      Path.expand("verification"),
      "-o",
      codec_path,
      Path.expand("verification/DifferentialCodec.lean")
    ],
    cd: "deps/lynx/Lean",
    stderr_to_stdout: true
  )

if codec_status != 0 or String.contains?(codec_output, "warning:"),
  do: raise("codec compilation failed: #{codec_output}")

source =
  "module\nimport all Init.Data.String.Search\nimport all Init.Data.String.Slice\nimport all HoldLedgerDifferentialCodec\npublic meta import HoldLedgerDifferentialCodec\nimport all Elixir.HoldLedger.Environment\nimport all Elixir.HoldLedger.Composite\nimport all Elixir.HoldLedger.Attempts\npublic meta import Elixir.HoldLedger.Environment\npublic meta import Elixir.HoldLedger.Composite\npublic meta import Elixir.HoldLedger.Attempts\nimport all Elixir.HoldLedger.Exposure\npublic meta import Elixir.HoldLedger.Exposure\nimport all Elixir.HoldLedger.Ledger\nimport all Elixir.HoldLedger.Spec\npublic meta import Elixir.HoldLedger.Ledger\npublic meta import Elixir.HoldLedger.Spec\npublic meta import Lynx.Term.DataTypes\nimport all Lynx.Term.Compare\nimport all Lynx.Modules.Erlang.erlang.Guards\nset_option maxRecDepth 100000\nset_option maxHeartbeats 16000000\n" <>
    Enum.map_join(Enum.with_index(cases), "\n", fn {entry, i} ->
      Differential.assertion(entry, i, i < 3)
    end)

reports =
  Lynx.Commands.verify!(Path.expand("deps/lynx/Lean"), files,
    debug_dir: "tmp/differential",
    debug: :olean
  )

unless length(reports) == length(files) and Enum.all?(reports, &(&1.status == :ok)),
  do: raise("translation failed: #{inspect(reports)}")

goldens =
  "\ntheorem golden_integer : " <>
    Differential.literal(1) <>
    " = Lynx.Term.integer 1 := by rfl\n" <>
    "theorem golden_atom : " <>
    Differential.literal(:approved) <>
    " = Lynx.Term.atom \"approved\" := by rfl\n" <>
    "theorem golden_float : " <>
    Differential.literal(1.0) <>
    " = Lynx.Term.float ⟨false, ⟨1023, by decide⟩, ⟨0, by decide⟩⟩ := by rfl\n"

codec_vectors = [1, -1, 1.0, -0.0, :approved, {1, [:voiding, 1.0]}]

codec_checks =
  Enum.map_join(Enum.with_index(codec_vectors), "\n", fn {value, i} ->
    term = Differential.literal(value)
    wire = Differential.wire_source(Differential.encode(value))

    "#eval (if reprStr (HoldLedgerDifferentialCodec.encode 64 #{term}) == reprStr (some #{wire}) && reprStr (HoldLedgerDifferentialCodec.decode 64 #{wire}) == reprStr (some #{term}) then pure () else throw (IO.userError \"codec vector #{i}\") : IO Unit)"
  end)

source =
  source <>
    "\n" <>
    codec_checks <>
    "\ntheorem kernel_decode_atom : HoldLedgerDifferentialCodec.decode 64 (.atom \"approved\") = some (Lynx.Term.atom \"approved\") := by rfl\n" <>
    "theorem kernel_encode_atom : HoldLedgerDifferentialCodec.encode 64 (Lynx.Term.atom \"approved\") = some (.atom \"approved\") := by rfl\n"

File.write!("tmp/differential/HoldLedgerDifferential.lean", source <> goldens)

File.write!(
  "tmp/differential/cases.json",
  JSON.encode!(
    Enum.map(cases, fn {module, function, args} ->
      %{
        module: Atom.to_string(module),
        function: Atom.to_string(function),
        args: Enum.map(args, &Differential.encode/1)
      }
    end)
  )
)

{output, status} =
  System.cmd("lake", ["env", "lean", Path.expand("tmp/differential/HoldLedgerDifferential.lean")],
    cd: "deps/lynx/Lean",
    env: [{"LEAN_PATH", Path.expand("tmp/differential")}],
    stderr_to_stdout: true
  )

IO.write(output)

# A semantic mismatch is separately recognizable from a Lean/compiler failure.
# Preserve the original witness and accept a shrink only if the same evaluator
# still reports the semantic mismatch marker. Never shrink toward a tool error.
if status != 0 do
  case Regex.run(~r/differential case (\d+)/, output) do
    [_, index] ->
      {module, function, args} = Enum.fetch!(cases, String.to_integer(index))
      header = source |> String.split("#eval", parts: 2) |> hd()

      mismatch? = fn candidate ->
        probe = header <> Differential.assertion({module, function, candidate}, 0, false)
        File.write!("tmp/differential/Shrink.lean", probe)

        {diagnostics, exit} =
          System.cmd("lake", ["env", "lean", Path.expand("tmp/differential/Shrink.lean")],
            cd: "deps/lynx/Lean",
            env: [{"LEAN_PATH", Path.expand("tmp/differential")}],
            stderr_to_stdout: true
          )

        cond do
          exit == 0 -> false
          String.contains?(diagnostics, "differential case 0") -> true
          true -> raise("differential shrink evaluator failure: #{diagnostics}")
        end
      end

      {minimal, attempts} = Differential.minimize(args, mismatch?, 32)

      File.write!(
        "tmp/differential/mismatch.json",
        JSON.encode!(%{
          index: String.to_integer(index),
          module: Atom.to_string(module),
          function: Atom.to_string(function),
          original_args: Enum.map(args, &Differential.encode/1),
          minimized_args: Enum.map(minimal, &Differential.encode/1),
          shrink_attempts: attempts,
          accepted: false,
          seed: [41, 73, 109],
          source_sha256:
            Map.new(Path.wildcard("lib/**/*.ex"), fn path ->
              {path, Base.encode16(:crypto.hash(:sha256, File.read!(path)), case: :lower)}
            end)
        })
      )

    _ ->
      :ok
  end
end

accepted =
  status == 0 and not String.contains?(output, "warning:") and
    source_manifest.() == source_sha256

File.write!(
  "tmp/differential/report.json",
  JSON.encode!(%{
    accepted: accepted,
    seed: [41, 73, 109],
    attempted: length(cases),
    targets:
      Enum.frequencies_by(cases, fn {module, function, args} ->
        "#{module}.#{function}/#{length(args)}"
      end),
    comparisons: if(accepted, do: length(cases), else: nil),
    mismatches:
      output |> then(&Regex.scan(~r/differential case (\d+)/, &1)) |> Enum.uniq() |> length(),
    unsupported: 0,
    kernel_cases: if(accepted, do: 8, else: nil),
    kernel_scope: [
      "empty lookup",
      "malformed dispatch",
      "invalid state",
      "integer literal",
      "atom literal",
      "float literal",
      "atom decode",
      "atom encode"
    ],
    kernel_pilot_limitations: [
      "Decimal String.toInt? reduction was unestablished under decide +kernel; numeric codec vectors are compiled comparisons, not kernel claims"
    ],
    reports: reports,
    evaluator_exit: status,
    source_sha256: source_sha256,
    source_unchanged: source_manifest.() == source_sha256
  })
)

unless accepted, do: raise("compiled/kernel differential evaluation failed")

IO.puts("Differential: #{length(cases)} comparisons and #{8} kernel cases passed")
