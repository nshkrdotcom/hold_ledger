defmodule HoldLedgerReview.Claims.Source do
  @moduledoc """
  Reads only registered, trusted checkout law declarations. No source from a
  browser or model is parsed. Inventory and exact bytes are digest-bound,
  independently of `HoldLedgerReview.Config`'s Ledger/Spec source guard.
  """
  alias HoldLedgerReview.Anchor

  @compiler_version "source-ast-explain-20261028"
  @support_sources ~w(
    lib/hold_ledger/ledger.ex
    lib/hold_ledger/spec.ex
    lib/hold_ledger/composite.ex
    lib/hold_ledger/outbox.ex
    lib/hold_ledger/environment.ex
    lib/hold_ledger/exposure.ex
    apps/review_web/lib/hold_ledger_review/trace.ex
    apps/review_web/lib/hold_ledger_review/review_store.ex
    test/support/proof_case.ex
    apps/review_web/lib/hold_ledger_review/claims.ex
    apps/review_web/lib/hold_ledger_review/claims/source.ex
    apps/review_web/lib/hold_ledger_review/claims/compiler.ex
    apps/review_web/lib/hold_ledger_review/claims/explanation.ex
    apps/review_web/lib/hold_ledger_review/proof_reading.ex
    apps/review_web/lib/hold_ledger_review/contrast.ex
    apps/review_web/priv/claim_readings.json
    test/support/lean/library.json
    apps/review_web/lib/hold_ledger_review/claim_probe.ex
    apps/review_web/lib/hold_ledger_review/term_codec.ex
    apps/review_web/lib/hold_ledger_review/anchor.ex
    apps/review_web/lib/hold_ledger_review/canonical.ex
    apps/review_web/lib/hold_ledger_review/config.ex
    apps/review_web/lib/hold_ledger_review/application.ex
  )

  @build_root Path.expand("../../../../..", __DIR__)
  @shared_sources Path.wildcard(Path.join(@build_root, "test/support/lean/*.lean"))
                  |> Enum.map(&Path.relative_to(&1, @build_root))
  @support_sources Enum.uniq(@support_sources ++ @shared_sources)

  def version, do: @compiler_version
  def support_sources, do: @support_sources

  def snapshot(root) do
    with {:ok, catalog_bytes} <- Anchor.read_under(root, "verification/laws.json"),
         {:ok, obligation_bytes} <- Anchor.read_under(root, "verification/obligations.json"),
         {:ok, catalog} <- Jason.decode(catalog_bytes),
         {:ok, obligations} <- Jason.decode(obligation_bytes),
         {:ok, laws} <- validate_catalog(root, catalog, obligations),
         {:ok, files} <- law_inventory(root),
         true <-
           Enum.sort(Enum.map(Enum.filter(laws, &(&1["kind"] != "lean")), & &1["file"])) == files,
         {:ok, pairs} <-
           source_pairs(
             root,
             files ++ Enum.map(Enum.filter(laws, &(&1["kind"] == "lean")), & &1["file"])
           ) do
      digest =
        Anchor.sha(
          :erlang.term_to_binary(
            {@compiler_version,
             [{"catalog", catalog_bytes}, {"obligations", obligation_bytes} | pairs]}
          )
        )

      {:ok,
       %{
         sha256: digest,
         law_files: files,
         file_sha256: Map.new(pairs, fn {path, bytes} -> {path, Anchor.sha(bytes)} end),
         catalog: laws,
         catalog_sha256: Anchor.sha(catalog_bytes),
         obligations_sha256: Anchor.sha(obligation_bytes)
       }}
    else
      false -> {:error, :law_inventory_mismatch}
      {:error, _} = error -> error
      _ -> {:error, :invalid_claim_catalog}
    end
  end

  @doc """
  Compare fresh bytes with an already validated generation. Catalog structure is
  parsed at initialization; unchanged catalog bytes need no repeated decoding or
  validation. Every registered file is still read and hashed on each check, and
  the live law inventory must still match exactly. No mtime or cross-call cache.
  """
  def matches?(root, source), do: match?({:ok, _}, current_digests(root, source, []))

  def current_digests(root, source, extra_paths) do
    with {:ok, context} <- current_sources(root, source, extra_paths), do: {:ok, context.digests}
  end

  def current_sources(root, source, extra_paths) do
    expected =
      source.file_sha256
      |> Map.put("verification/laws.json", source.catalog_sha256)
      |> Map.put("verification/obligations.json", source.obligations_sha256)

    files =
      Path.wildcard(Path.join(root, "test/laws/*.exs"))
      |> Enum.map(&Path.relative_to(&1, root))
      |> Enum.sort()

    with true <- files == source.law_files and shared_inventory_matches?(root, source),
         {:ok, bytes} <- Anchor.read_many_under(root, Map.keys(expected) ++ extra_paths),
         digests = Map.new(bytes, fn {path, content} -> {path, Anchor.sha(content)} end),
         true <- Enum.all?(expected, fn {path, digest} -> digests[path] == digest end) do
      {:ok, %{digests: digests, bytes: bytes}}
    else
      _ -> {:error, :source_or_compiled_code_drift}
    end
  end

  defp shared_inventory_matches?(root, source) do
    expected =
      source.file_sha256
      |> Map.keys()
      |> Enum.filter(
        &(String.starts_with?(&1, "test/support/lean/") and String.ends_with?(&1, ".lean"))
      )
      |> Enum.sort()

    actual =
      Path.wildcard(Path.join(root, "test/support/lean/*.lean"))
      |> Enum.map(&Path.relative_to(&1, root))
      |> Enum.sort()

    expected == actual
  end

  def extract(root, %{catalog: catalog}) do
    Enum.reduce(catalog, {%{}, %{}}, fn law, {claims, errors} ->
      slug = law["slug"]

      case extract_declaration(root, law) do
        {:ok, declaration} -> {Map.put(claims, slug, declaration), errors}
        {:error, reason} -> {claims, Map.put(errors, slug, reason)}
      end
    end)
  end

  defp extract_declaration(_root, %{"kind" => "lean"}), do: {:error, :native_lean_obligation}
  defp extract_declaration(root, law), do: declaration(root, law)

  def declaration(root, law) do
    file = law["file"]

    with {:ok, bytes} <- Anchor.read_under(root, file),
         {:ok, ast} <-
           Code.string_to_quoted(bytes, file: file, columns: true, token_metadata: true),
         :ok <- validate_context(ast),
         {:ok, aliases} <- aliases(ast),
         [{{name, _meta, args}, opts, law_meta, original}] <- law_nodes(ast),
         true <-
           is_list(args) and length(args) == law["arity"] and Atom.to_string(name) == law["law"],
         {:ok, formals} <- formal_names(args),
         true <- Keyword.keyword?(opts),
         {:ok, expects} <- Keyword.fetch(opts, :expects) do
      line = Keyword.get(law_meta, :line, 1)
      closing = Keyword.get(Keyword.get(law_meta, :closing, []), :line, line)
      lines = String.split(bytes, "\n")

      {:ok,
       %{
         slug: law["slug"],
         source_file: file,
         source_sha256: Anchor.sha(bytes),
         source_line: line,
         source_end_line: closing,
         source_text:
           lines |> Enum.slice((line - 1)..max(line - 1, closing - 1)) |> Enum.join("\n"),
         full_source_text: bytes,
         formals: formals,
         requires: Keyword.get(opts, :requires, true),
         expects: expects,
         aliases: aliases,
         original_ast: original,
         arity: law["arity"]
       }}
    else
      false -> {:error, :invalid_declaration}
      [_ | _] -> {:error, :duplicate_law_declaration}
      [] -> {:error, :missing_law_declaration}
      {:error, _} = error -> error
      _ -> {:error, :invalid_declaration}
    end
  rescue
    _ -> {:error, :unparseable_law_source}
  end

  # Imported/local macros can change an allowed operator's meaning. Never
  # expand or execute the surrounding module to discover its semantics.
  defp validate_context(ast) do
    {_, directives} =
      Macro.prewalk(ast, [], fn
        {name, _, _} = node, acc
        when name in [:use, :import, :require, :def, :defp, :defmacro, :defmacrop] ->
          {node, [Macro.to_string(node) | acc]}

        node, acc ->
          {node, acc}
      end)

    if Enum.all?(directives, &(&1 in ["use ExUnit.Case", "use HoldLedger.ProofCase"])),
      do: :ok,
      else: {:error, :unsupported_source_context}
  end

  defp formal_names(args) do
    names =
      Enum.map(args, fn
        {name, _, context} when is_atom(name) and (is_atom(context) or is_nil(context)) -> name
        _ -> nil
      end)

    if nil not in names and length(Enum.uniq(names)) == length(names),
      do: {:ok, names},
      else: {:error, :unsupported_formal_arguments}
  end

  # Same narrow law/2 AST shape read by HoldLedger.ProofCase.law_declarations/1.
  defp law_nodes(ast) do
    {_, found} =
      Macro.prewalk(ast, [], fn
        {:law, meta, [call, opts]} = node, acc -> {node, [{call, opts, meta, node} | acc]}
        node, acc -> {node, acc}
      end)

    Enum.reverse(found)
  end

  defp aliases(ast) do
    {_, found} =
      Macro.prewalk(ast, [], fn
        {:alias, _, _} = node, acc -> {node, [Macro.to_string(node) | acc]}
        node, acc -> {node, acc}
      end)

    approved = %{
      "alias HoldLedger.{Ledger, Spec}" => [:Ledger, :Spec],
      "alias HoldLedger.{Spec, Ledger}" => [:Ledger, :Spec],
      "alias HoldLedger.Ledger" => [:Ledger],
      "alias HoldLedger.Spec" => [:Spec],
      "alias HoldLedger.Attempts" => [:Attempts],
      "alias HoldLedger.Environment" => [:Environment],
      "alias HoldLedger.{Ledger, Spec}, warn: false" => [:Ledger, :Spec],
      "alias HoldLedger.{Attempts, Environment, Ledger, Spec}" => [
        :Attempts,
        :Environment,
        :Ledger,
        :Spec
      ]
    }

    if Enum.all?(found, &Map.has_key?(approved, &1)) do
      {:ok, found |> Enum.flat_map(&Map.fetch!(approved, &1)) |> Enum.uniq()}
    else
      {:error, :unresolved_alias}
    end
  end

  defp validate_catalog(root, %{"laws" => laws}, %{"obligations" => obligations})
       when is_list(laws) and is_list(obligations) do
    ids = Enum.map(laws, & &1["id"])
    slugs = Enum.map(laws, & &1["slug"])
    o_ids = Enum.map(obligations, & &1["id"])
    o_slugs = Enum.map(obligations, & &1["slug"])
    by_slug = Map.new(laws, fn law -> {law["slug"], law} end)

    correct =
      laws != [] and unique?(slugs) and
        Enum.sort(ids) == Enum.sort(o_ids) and Enum.sort(slugs) == Enum.sort(o_slugs) and
        Enum.all?(obligations, &obligation_matches?(&1, by_slug)) and
        Enum.all?(laws, &valid_catalog_law?(&1, root))

    if correct do
      {:ok,
       Enum.map(laws, &Map.put(&1, "kind", if(&1["kind"] == "lean", do: "lean", else: "dsl")))}
    else
      {:error, :invalid_claim_catalog}
    end
  end

  defp validate_catalog(_, _, _), do: {:error, :invalid_claim_catalog}

  defp unique?(values), do: length(Enum.uniq(values)) == length(values)

  defp obligation_matches?(obligation, by_slug) do
    case Map.get(by_slug, obligation["slug"]) do
      nil -> false
      law -> obligation["id"] == law["id"] and same_obligation?(law, obligation)
    end
  end

  defp same_obligation?(%{"kind" => "lean"} = law, obligation) do
    obligation["kind"] == "lean" and obligation["module"] == law["module"] and
      obligation["theorems"] == law["theorems"]
  end

  defp same_obligation?(law, obligation) do
    obligation["law"] == law["law"] and obligation["arity"] == law["arity"]
  end

  defp valid_catalog_law?(law, root) do
    law["kind"] in [nil, "lean"] and
      is_binary(law["slug"]) and Regex.match?(~r/\A[a-z0-9_]+\z/, law["slug"]) and
      is_binary(law["id"]) and is_binary(law["file"]) and valid_law_path?(law) and
      match?({:ok, _}, Anchor.read_under(root, law["file"]))
  end

  defp valid_law_path?(%{"kind" => "lean", "file" => file}) do
    String.starts_with?(file, "test/support/lean/") and String.ends_with?(file, ".lean")
  end

  defp valid_law_path?(law) do
    law["file"] == "test/laws/" <> law["slug"] <> "_test.exs" and
      law["law"] == law["slug"] and is_integer(law["arity"]) and law["arity"] > 0
  end

  defp law_inventory(root) do
    # Include *all* .exs paths. A new non-test-named file must not evade
    # the inventory that the registered *_test.exs declarations occupy.
    files =
      Path.wildcard(Path.join(root, "test/laws/*.exs"))
      |> Enum.map(&Path.relative_to(&1, root))
      |> Enum.sort()

    if Enum.all?(files, fn p -> match?({:ok, _}, Anchor.read_under(root, p)) end),
      do: {:ok, files},
      else: {:error, :unsafe_law_source}
  end

  defp source_pairs(root, law_files) do
    Enum.reduce_while(Enum.sort(Enum.uniq(law_files ++ @support_sources)), {:ok, []}, fn path,
                                                                                         {:ok,
                                                                                          acc} ->
      case Anchor.read_under(root, path) do
        {:ok, bytes} -> {:cont, {:ok, [{path, bytes} | acc]}}
        _ -> {:halt, {:error, {:missing_or_unsafe_source, path}}}
      end
    end)
    |> case do
      {:ok, reversed} -> {:ok, Enum.reverse(reversed)}
      other -> other
    end
  end
end
