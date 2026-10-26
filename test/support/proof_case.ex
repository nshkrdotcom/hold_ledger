defmodule HoldLedger.ProofCase do
  @moduledoc false

  defmacro __using__(_opts) do
    quote do
      use Lynx.Case
      @moduletag timeout: 600_000
      Module.register_attribute(__MODULE__, :proof_groups, accumulate: true, persist: true)
      import Lynx.Case, except: [laws: 2, laws: 3]
      import HoldLedger.ProofCase, only: [laws: 2, laws: 3]
    end
  end

  defmacro laws(description, opts \\ [], do: block) do
    definition =
      quote unquote: false do
        def unquote(name)(_context) do
          HoldLedger.ProofCase.verify(
            __MODULE__,
            unquote(name),
            unquote(group_laws),
            unquote(Macro.escape(suffixes)),
            unquote(Macro.escape(cutoffs)),
            unquote(Macro.escape(preludes)),
            unquote(Macro.escape(options))
          )
        end
      end

    quote do
      {name, group_laws, suffixes, cutoffs, preludes, options} =
        Lynx.Case.__laws__(
          __MODULE__,
          unquote(__CALLER__.file),
          unquote(__CALLER__.line),
          unquote(description),
          unquote(opts),
          fn -> unquote(block) end
        )

      Module.put_attribute(
        __MODULE__,
        :proof_groups,
        {name, group_laws, suffixes, cutoffs, preludes, options}
      )

      unquote(definition)
    end
  end

  def compile_contracts do
    definitions =
      for file <- Path.wildcard("test/laws/*_test.exs"),
          {call, opts} <- law_declarations(file),
          {name, _, args} = call,
          {kind, expression} <- [
            requires: Keyword.get(opts, :requires, true),
            expects: Keyword.fetch!(opts, :expects)
          ] do
        contract_definition(name, args, kind, expression)
      end

    {:module, module, binary, _} =
      Module.create(
        HoldLedger.ProofContracts,
        quote do
          @moduledoc false
          @compile :debug_info
          alias HoldLedger.{Attempts, Environment, Ledger, Spec}
          unquote_splicing(definitions)
        end,
        Macro.Env.location(__ENV__)
      )

    Lynx.Bytecode.put(module, binary)
  end

  defp contract_definition(name, args, kind, expression) do
    suffix = if kind == :requires, do: :requires, else: :ensures
    function = String.to_atom("#{name}:#{suffix}")

    used =
      expression
      |> Macro.prewalker()
      |> Enum.flat_map(fn
        {variable, _, context} when is_atom(variable) and is_atom(context) -> [variable]
        _ -> []
      end)

    args =
      Enum.map(args, fn {variable, _, _} = arg ->
        if variable in used, do: arg, else: Macro.var(:_, nil)
      end)

    quote do
      def unquote(function)(unquote_splicing(args)), do: unquote(expression)
    end
  end

  def law_declarations(file) do
    ast = file |> File.read!() |> Code.string_to_quoted!(file: file)

    {_, declarations} =
      Macro.prewalk(ast, [], fn
        {:law, _, [call, opts]} = node, acc -> {node, [{call, opts} | acc]}
        node, acc -> {node, acc}
      end)

    Enum.reverse(declarations)
  end

  def assemble(module, laws, suffixes, cutoffs, preludes) do
    assemble_many([{module, laws}], suffixes, cutoffs, preludes)
  end

  def assemble_many(
        groups,
        suffixes \\ %{},
        cutoffs \\ MapSet.new(),
        preludes \\ [],
        native \\ []
      ) do
    translation =
      Lynx.Translation.new(termination_suffixes: suffixes, cutoffs: cutoffs, preludes: preludes)
      |> Lynx.Translation.add(Lynx.Bytecode.fetch!(HoldLedger.ProofContracts))
      |> Lynx.Translation.translate(
        HoldLedger.ProofContracts,
        HoldLedger.ProofContracts.__info__(:functions)
      )

    translation =
      Enum.reduce(
        [
          HoldLedger.Attempts,
          HoldLedger.Composite,
          HoldLedger.Environment,
          HoldLedger.Exposure,
          HoldLedger.Ledger,
          HoldLedger.Outbox,
          HoldLedger.Spec
        ],
        translation,
        fn
          module, acc ->
            acc
            |> Lynx.Translation.add(elem(:code.get_object_code(module), 1))
            |> Lynx.Translation.translate(module, module.__info__(:functions))
        end
      )

    translation =
      Enum.reduce(groups, translation, fn {module, laws}, acc ->
        acc
        |> Lynx.Translation.add(Lynx.Bytecode.fetch!(module))
        |> Lynx.Translation.verify(module, laws)
      end)

    files = Lynx.Translation.assemble(translation, cache: false)
    {proofs, definitions} = Enum.split_with(files, &String.ends_with?(&1["module"], ".laws"))
    support = support_files(Enum.flat_map(groups, &elem(&1, 1)))

    {_, support} =
      Enum.reduce(native, {MapSet.new(Enum.map(support, & &1["module"])), support}, fn name,
                                                                                       state ->
        load_support(name, state, [])
      end)

    imports = Enum.map(support, & &1["module"])

    files =
      definitions ++
        support ++ Enum.map(proofs, &Map.update!(&1, "imports", fn deps -> deps ++ imports end))

    if System.get_env("HOLD_LEDGER_PROOF_CACHE") == "1", do: cache_files(files), else: files
  end

  def native_anchors([]), do: []

  def native_anchors(groups) do
    names = Enum.flat_map(groups, &Map.fetch!(&1, "theorems"))

    unless Enum.all?(names, &Regex.match?(~r/^[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)+$/, &1)),
      do: raise(ArgumentError, "invalid qualified theorem name")

    imports = groups |> Enum.map(&Map.fetch!(&1, "module")) |> Enum.uniq()

    source =
      "module\n" <>
        Enum.map_join(imports, "\n", &("public import " <> &1)) <>
        "\npublic section\nnamespace HoldLedgerProof.RequiredObligations\n" <>
        Enum.map_join(Enum.with_index(names), "\n", fn {name, index} ->
          "abbrev checked_#{index} := @#{name}"
        end) <>
        "\nend HoldLedgerProof.RequiredObligations\n"

    [
      %{
        "module" => "HoldLedgerProof.RequiredObligations",
        "file" => "verification/obligations.json",
        "imports" => imports,
        "contents" => [],
        "preludes" => [
          %{
            "source" => source,
            "file" => "verification/obligations.json",
            "span" => [1, 1],
            "indentation" => 0
          }
        ]
      }
    ]
  end

  def cache_files(files) do
    {files, _keys} =
      Enum.map_reduce(files, %{}, fn file, keys ->
        dependencies =
          for name <- file["imports"],
              Map.has_key?(keys, name),
              do: {name, Map.fetch!(keys, name)}

        key =
          {file, dependencies}
          |> :erlang.term_to_binary([:deterministic])
          |> then(&:crypto.hash(:sha256, &1))
          |> Base.encode16(case: :lower)

        {Map.put(file, "cache_key", key), Map.put(keys, file["module"], key)}
      end)

    files
  end

  def support_files(laws) do
    library = "test/support/lean/library.json" |> File.read!() |> JSON.decode!()

    modules =
      Enum.map(laws, fn {name, _arity} ->
        "HoldLedgerProof." <> Map.fetch!(library, Atom.to_string(name))
      end)

    {_visited, files} =
      Enum.reduce(modules, {MapSet.new(), []}, fn name, state -> load_support(name, state, []) end)

    files
  end

  defp load_support(name, {visited, files}, ancestors) do
    if name in ancestors,
      do:
        raise(
          ArgumentError,
          "Cyclic shared proof import: #{Enum.join([name | ancestors], " -> ")}"
        )

    if MapSet.member?(visited, name) do
      {visited, files}
    else
      path = "test/support/lean/#{name |> String.split(".") |> List.last()}.lean"
      source = File.read!(path)

      imports =
        Regex.scan(~r/^public import (\S+)/m, source, capture: :all_but_first) |> List.flatten()

      dependencies = Enum.filter(imports, &String.starts_with?(&1, "HoldLedgerProof."))

      {visited, files} =
        Enum.reduce(dependencies, {MapSet.put(visited, name), files}, fn dependency, state ->
          load_support(dependency, state, [name | ancestors])
        end)

      file = %{
        "module" => name,
        "file" => path,
        "imports" => imports,
        "contents" => [],
        "preludes" => [
          %{"source" => source, "file" => path, "span" => [1, 1], "indentation" => 0}
        ]
      }

      {visited, files ++ [file]}
    end
  end

  def verify(module, name, laws, suffixes, cutoffs, preludes, options) do
    files = assemble(module, laws, suffixes, cutoffs, preludes)
    dir = Path.join(["tmp", inspect(module), String.replace(Atom.to_string(name), " ", "-")])
    opts = [options: options, debug_dir: dir, debug: :lean]

    opts =
      case System.get_env("LYNX_EXPORT") do
        value when value in [nil, ""] ->
          opts

        value ->
          Keyword.put(
            opts,
            :export,
            Path.join([value, inspect(module), Path.basename(dir) <> ".ndjson"])
          )
      end

    reports = Lynx.Commands.verify!(Path.expand("deps/lynx/Lean"), files, opts)

    Enum.each(reports, fn report ->
      IO.puts(
        "#{if report.status == :ok, do: "Checked", else: "Failed to check"} #{report.module} in #{report.time_ms}ms (#{report.status}, cached=#{report.cached})"
      )
    end)

    validate_reports!(reports, module, laws)
    :ok
  end

  def validate_reports!(reports, module, laws) do
    expected = Enum.map(laws, fn {name, arity} -> "#{name}/#{arity}" end) |> Enum.sort()
    law_module = "#{module}.laws"

    checked =
      for report <- reports,
          report.module == law_module,
          theorem <- report.theorems,
          do: theorem.name

    errors = Enum.filter(reports, &(&1.status != :ok))

    if reports == [] or Enum.sort(checked) != expected or errors != [] do
      diagnostics =
        for report <- errors,
            diagnostic <- Map.get(report, :diagnostics, []),
            diagnostic.severity == :error,
            do: diagnostic

      ExUnit.Assertions.flunk(
        "Shared proof verification failed or omitted requested laws: #{inspect(diagnostics, pretty: true, limit: :infinity, printable_limit: :infinity)}"
      )
    end

    :ok
  end
end

HoldLedger.ProofCase.compile_contracts()
