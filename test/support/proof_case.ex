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
            unquote(Macro.escape(translation)),
            unquote(Macro.escape(options))
          )
        end
      end

    quote do
      {name, group_laws, translation, options} =
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
        {name, group_laws, translation, options}
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

  def assemble(module, laws, translation) do
    assemble_many([{module, laws}], translation)
  end

  def assemble_many(groups, translation_opts \\ [], native \\ []) do
    translation =
      Lynx.Translation.new(translation_opts)
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
    support = support_files(Enum.flat_map(groups, &elem(&1, 1)))

    {_, support} =
      Enum.reduce(native, {MapSet.new(Enum.map(support, & &1["module"])), support}, fn name,
                                                                                       state ->
        load_support(name, state, [])
      end)

    library = "test/support/lean/library.json" |> File.read!() |> JSON.decode!()

    scopes =
      Map.new(groups, fn {module, laws} ->
        roots =
          Enum.map(laws, fn {name, _} ->
            "HoldLedgerProof." <> Map.fetch!(library, Atom.to_string(name))
          end)

        {Atom.to_string(module) <> ".laws", roots}
      end)

    postlude_roots =
      Enum.flat_map(groups, fn {module, _laws} ->
        [{_name, _declared, translation, _options}] = module.__info__(:attributes)[:proof_groups]

        if Keyword.get(translation, :postludes, []) == [],
          do: [],
          else: Map.fetch!(scopes, Atom.to_string(module) <> ".laws")
      end)

    scopes = Map.put(scopes, "Erlang.postlude", Enum.uniq(postlude_roots))
    files = attach_support(files, support, scopes)

    if System.get_env("HOLD_LEDGER_PROOF_CACHE") == "1", do: cache_files(files), else: files
  end

  @doc "Collect well-formed local postludes for the cold batch; fail on all other overrides."
  def batch_postludes!(group_translations) do
    Enum.flat_map(group_translations, fn {_module, translation} ->
      if not Keyword.keyword?(translation),
        do: raise(ArgumentError, "invalid translation options")

      keys = Keyword.keys(translation)

      if length(keys) != length(Enum.uniq(keys)),
        do: raise(ArgumentError, "duplicate translation options")

      Enum.each(translation, &validate_batch_option!/1)

      Keyword.get(translation, :postludes, [])
    end)
  end

  defp validate_batch_option!({:termination_suffixes, value})
       when is_map(value) and map_size(value) == 0, do: :ok

  defp validate_batch_option!({kind, %MapSet{} = value}) when kind in [:cutoffs, :dynamic] do
    if MapSet.size(value) != 0, do: raise(ArgumentError, "nonempty batch #{kind}")
  end

  defp validate_batch_option!({:preludes, []}), do: :ok

  defp validate_batch_option!({:postludes, sources}) when is_list(sources) do
    if not Enum.all?(sources, &valid_postlude?/1),
      do: raise(ArgumentError, "invalid batch postludes")
  end

  defp validate_batch_option!(other),
    do: raise(ArgumentError, "unsupported batch translation option: #{inspect(other)}")

  defp valid_postlude?(%Lynx.Lean{source: source, file: file, span: span, indentation: indent})
       when is_binary(source) and is_binary(file) and file != "" and
              is_integer(indent) and indent >= 0 do
    valid_span?(span) and String.trim(source) != "" and
      not Regex.match?(~r/^\s*(?:module|public import|public section)\b/m, source)
  end

  defp valid_postlude?(_), do: false

  defp valid_span?(line) when is_integer(line) and line > 0, do: true

  defp valid_span?({line, col})
       when is_integer(line) and line > 0 and is_integer(col) and col > 0, do: true

  defp valid_span?(_), do: false

  @doc "Place shared Lean support before postludes, while retaining generated law imports."
  def attach_support(files, support, scopes) do
    {proofs, nonproofs} = Enum.split_with(files, &String.ends_with?(&1["module"], ".laws"))

    {postludes, definitions} =
      Enum.split_with(nonproofs, &(&1["module"] == "Erlang.postlude"))

    if Enum.any?(support, &("Erlang.postlude" in &1["imports"])),
      do: raise(ArgumentError, "shared support cannot import Erlang.postlude")

    names = Enum.map(files ++ support, &Map.fetch!(&1, "module"))

    if length(names) != length(Enum.uniq(names)),
      do: raise(ArgumentError, "duplicate generated or shared Lean module")

    if length(postludes) > 1,
      do: raise(ArgumentError, "multiple Erlang.postlude modules")

    link = fn file ->
      imports = Map.fetch!(scopes, file["module"])
      Map.update!(file, "imports", &Enum.uniq(&1 ++ imports))
    end

    definitions ++ support ++ Enum.map(postludes, link) ++ Enum.map(proofs, link)
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

  def verify(module, name, laws, translation, options) do
    files = assemble(module, laws, translation)
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
