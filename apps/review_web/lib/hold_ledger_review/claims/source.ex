defmodule HoldLedgerReview.Claims.Source do
  @moduledoc """
  Reads only registered, trusted checkout law declarations. No source from a
  browser or model is parsed. Inventory and exact bytes are digest-bound,
  independently of `HoldLedgerReview.Config`'s Ledger/Spec source guard.
  """
  alias HoldLedgerReview.Anchor

  @compiler_version "source-ast-a-20261027"
  @support_sources ~w(
    lib/hold_ledger/ledger.ex
    lib/hold_ledger/spec.ex
    test/support/proof_case.ex
    apps/review_web/lib/hold_ledger_review/claims.ex
    apps/review_web/lib/hold_ledger_review/claims/source.ex
    apps/review_web/lib/hold_ledger_review/claims/compiler.ex
    apps/review_web/lib/hold_ledger_review/claim_probe.ex
    apps/review_web/lib/hold_ledger_review/term_codec.ex
    apps/review_web/lib/hold_ledger_review/anchor.ex
    apps/review_web/lib/hold_ledger_review/canonical.ex
    apps/review_web/lib/hold_ledger_review/config.ex
    apps/review_web/lib/hold_ledger_review/application.ex
  )

  def version, do: @compiler_version

  def snapshot(root) do
    with {:ok, catalog_bytes} <- Anchor.read_under(root, "verification/laws.json"),
         {:ok, obligation_bytes} <- Anchor.read_under(root, "verification/obligations.json"),
         {:ok, catalog} <- Jason.decode(catalog_bytes),
         {:ok, obligations} <- Jason.decode(obligation_bytes),
         {:ok, laws} <- validate_catalog(root, catalog, obligations),
         {:ok, files} <- law_inventory(root),
         true <- Enum.sort(Enum.map(Enum.filter(laws, &(&1["kind"] != "lean")), & &1["file"])) == files,
         {:ok, pairs} <- source_pairs(root, files ++ Enum.map(Enum.filter(laws, &(&1["kind"] == "lean")), & &1["file"])) do
      digest =
        Anchor.sha(
          :erlang.term_to_binary({@compiler_version, [{"catalog", catalog_bytes}, {"obligations", obligation_bytes} | pairs]})
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

  def extract(root, %{catalog: catalog}) do
    Enum.reduce(catalog, {%{}, %{}}, fn law, {claims, errors} ->
      slug = law["slug"]

      if law["kind"] == "lean" do
        {claims, Map.put(errors, slug, :native_lean_obligation)}
      else
        case declaration(root, law) do
          {:ok, declaration} -> {Map.put(claims, slug, declaration), errors}
          {:error, reason} -> {claims, Map.put(errors, slug, reason)}
        end
      end
    end)
  end

  def declaration(root, law) do
    file = law["file"]

    with {:ok, bytes} <- Anchor.read_under(root, file),
         {:ok, ast} <- Code.string_to_quoted(bytes, file: file, columns: true, token_metadata: true),
         {:ok, aliases} <- aliases(ast),
         [{{name, _meta, args}, opts, law_meta, original}] <- law_nodes(ast),
         true <- is_list(args) and length(args) == law["arity"] and Atom.to_string(name) == law["law"],
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
         source_text: lines |> Enum.slice((line - 1)..max(line - 1, closing - 1)) |> Enum.join("\n"),
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
      "alias HoldLedger.{Attempts, Environment, Ledger, Spec}" => [:Attempts, :Environment, :Ledger, :Spec]
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

    obligations_match? =
      Enum.all?(obligations, fn obligation ->
        case Map.get(by_slug, obligation["slug"]) do
          nil -> false
          law ->
            obligation["id"] == law["id"] and
              (if law["kind"] == "lean",
                 do: obligation["kind"] == "lean" and
                       obligation["module"] == law["module"] and
                       obligation["theorems"] == law["theorems"],
                 else: obligation["law"] == law["law"] and
                       obligation["arity"] == law["arity"])
        end
      end)

    correct =
      laws != [] and length(Enum.uniq(ids)) == length(ids) and
        length(Enum.uniq(slugs)) == length(slugs) and
        Enum.sort(ids) == Enum.sort(o_ids) and Enum.sort(slugs) == Enum.sort(o_slugs) and
        obligations_match? and
        Enum.all?(laws, fn law ->
          kind = if law["kind"] == "lean", do: "lean", else: "dsl"
          file = law["file"]

          law["kind"] in [nil, "lean"] and
            is_binary(law["slug"]) and Regex.match?(~r/\A[a-z0-9_]+\z/, law["slug"]) and
            is_binary(law["id"]) and is_binary(file) and
            (if kind == "lean",
               do: String.starts_with?(file, "test/support/lean/") and String.ends_with?(file, ".lean"),
               else: file == "test/laws/" <> law["slug"] <> "_test.exs" and
                       law["law"] == law["slug"] and is_integer(law["arity"]) and law["arity"] > 0) and
            match?({:ok, _}, Anchor.read_under(root, file))
        end)

    if correct do
      {:ok, Enum.map(laws, &Map.put(&1, "kind", if(&1["kind"] == "lean", do: "lean", else: "dsl")))}
    else
      {:error, :invalid_claim_catalog}
    end
  end

  defp validate_catalog(_, _, _), do: {:error, :invalid_claim_catalog}

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
    Enum.reduce_while(Enum.sort(Enum.uniq(law_files ++ @support_sources)), {:ok, []}, fn path, {:ok, acc} ->
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
