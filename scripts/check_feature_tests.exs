# Inspect effective ExUnit metadata, including inherited skip tags, without running tests.
ExUnit.start(autorun: false)

[feature, source, name] =
  case System.argv() do
    [] ->
      ["lib/hold_ledger/outbox.ex", "test/hold_ledger_hardening_test.exs", "forged_completion"]

    args ->
      args
  end

if File.exists?(feature) do
  tests =
    source
    |> Code.compile_file()
    |> Enum.flat_map(fn {module, _} ->
      if function_exported?(module, :__ex_unit__, 0), do: module.__ex_unit__().tests, else: []
    end)

  selected = Enum.filter(tests, &String.contains?(Atom.to_string(&1.name), name))

  if selected == [] or Enum.any?(selected, &Map.get(&1.tags, :skip, false)) do
    raise "feature #{feature} requires an enabled #{name} regression"
  end
end
