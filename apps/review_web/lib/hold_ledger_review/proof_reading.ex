defmodule HoldLedgerReview.ProofReading do
  @moduledoc """
  Source-bound law/theorem navigation and reviewed proof-reading notes.
  Source references are not kernel dependency footprints. Acceptance remains ProofEvidence's job.
  """
  alias HoldLedgerReview.{
    Anchor,
    Canonical,
    ClaimProbe,
    Claims,
    Config,
    ProofEvidence,
    TermCodec,
    Trace
  }

  alias HoldLedgerReview.Claims.Source
  alias HoldLedgerReview.ProofReading.Links

  def catalog do
    with {:ok, laws} <- Claims.catalog(),
         do: {:ok, Enum.map(laws, &Map.put(&1, "title", title(&1)))}
  end

  def document(slug) do
    with {:ok, result} <- Claims.with_generation(Config.root(), fn _ -> read_document(slug) end),
         do: result
  end

  defp read_document(slug) do
    with {:ok, laws} <- Claims.catalog(),
         law when is_map(law) <- Enum.find(laws, &(&1["slug"] == slug)),
         {:ok, context} <- Claims.source_context(Config.root(), paths(law)),
         {:ok, reading_bytes} <-
           Map.fetch(context.bytes, "apps/review_web/priv/claim_readings.json"),
         {:ok, readings} <- Jason.decode(reading_bytes) do
      guide = readings[slug]

      guide_current =
        guide &&
          Enum.all?(guide["reviewed_source_sha256"], fn {path, sha} ->
            context.digests[path] == sha
          end)

      lean_path = lean_path(law, context.bytes["test/support/lean/library.json"])
      theorems = theorem_targets(law)
      declarations = Enum.map(theorems, &declaration(context.bytes, lean_path, &1))
      inline = inline_proof(law)
      sources = Enum.map(paths(law), fn path -> source_record(path, context.bytes[path]) end)

      steps = if(guide_current, do: proof_steps(hd(declarations), guide["steps"]), else: [])
      connections = reading_connections(guide_current, guide, context, hd(declarations), steps)

      {:ok,
       %{
         "slug" => slug,
         "title" => if(guide_current, do: guide["title"], else: title(law)),
         "law" => law,
         "kind" => if(law["kind"] == "lean", do: "native_lean", else: "elixir_law"),
         "contract" => contract(law),
         "declarations" => declarations,
         "inline_proof" => inline,
         "proof_steps" => steps,
         "connections" => connections,
         "reading_current" => guide_current == true,
         "reading_status" => reading_status(guide, guide_current),
         "policy" =>
           policy(
             context.bytes["guides/specification.md"],
             if(guide_current, do: guide["policy_quote"])
           ),
         "omits" => if(guide_current, do: guide["omits"], else: nil),
         "sources" => sources,
         "source_digest" => Canonical.digest(Map.take(context.digests, paths(law))),
         "source_generation" => context.generation.source.sha256,
         "references" => references(declarations, context.bytes),
         "library_imports" => imports(context.bytes[lean_path] || ""),
         "formal" => formal_summary(),
         "focused" => focused(slug)
       }}
    else
      _ -> {:error, :claim_source_unavailable}
    end
  end

  defp reading_status(nil, _), do: "not_supplied"
  defp reading_status(_, true), do: "current"
  defp reading_status(_, _), do: "stale"

  defp reading_connections(current, guide, context, declaration, steps) do
    if current,
      do:
        Links.validate(
          guide["connections"] || [],
          context.bytes,
          context.digests,
          declaration,
          steps,
          guide["reviewed_source_sha256"]
        ),
      else: []
  end

  def explain(slug, %{"before" => before, "event" => event, "output" => output}) do
    with {:ok, before} <- TermCodec.decode_state(before),
         {:ok, event} <- TermCodec.decode_event(event),
         {:ok, output} <- TermCodec.decode_output(output),
         do: ClaimProbe.explain(slug, before, event, output)
  end

  def source(slug, id, sha) do
    with {:ok, doc} <- document(slug),
         record when is_map(record) <- Enum.find(doc["sources"], &(&1["id"] == id)),
         true <- record["sha256"] == sha,
         {:ok, bytes} <- Anchor.read_under(Config.root(), record["path"]),
         true <- Anchor.sha(bytes) == sha and byte_size(bytes) <= 256_000 do
      {:ok, bytes}
    else
      _ -> {:error, :source_missing_or_stale}
    end
  end

  def artifact(slug, sha) do
    with {:ok, doc} <- document(slug),
         artifacts when is_list(artifacts) <- doc["focused"]["artifacts"],
         item when is_map(item) <- Enum.find(artifacts, &(&1["sha256"] == sha)),
         true <-
           String.starts_with?(item["path"], "tmp/verification/claim-reading/") and
             String.ends_with?(item["path"], ".lean"),
         {:ok, bytes} <- Anchor.read_under(Config.root(), item["path"]),
         true <- byte_size(bytes) <= 256_000 and Anchor.sha(bytes) == sha do
      {:ok, bytes}
    else
      _ -> {:error, :missing_or_stale_artifact}
    end
  end

  defp inline_proof(%{"kind" => "lean"}), do: nil

  defp inline_proof(law) do
    with {:ok, d} <- Source.declaration(Config.root(), law),
         {:law, _, [_, opts]} <- d.original_ast,
         {:sigil_LEAN, _, [{:<<>>, _, [bytes]}, _]} <- opts[:proof],
         true <- is_binary(bytes) do
      %{"text" => bytes, "path" => law["file"], "line" => d.source_line}
    else
      _ -> nil
    end
  end

  defp title(law), do: law["slug"] <> " · " <> law["purpose"]

  defp paths(law) do
    root = Config.root()

    shared =
      Path.wildcard(Path.join(root, "test/support/lean/*.lean"))
      |> Enum.map(&Path.relative_to(&1, root))

    Enum.uniq(
      shared ++
        [
          law["file"],
          "guides/specification.md",
          "guides/processors.md",
          "guides/runtime.md",
          "lib/hold_ledger/spec.ex",
          "lib/hold_ledger/ledger.ex",
          "lib/hold_ledger/environment.ex",
          "lib/hold_ledger/exposure.ex",
          "test/support/proof_case.ex",
          "test/support/lean/library.json",
          "apps/review_web/priv/claim_readings.json"
        ]
    )
  end

  defp lean_path(%{"kind" => "lean", "file" => path}, _), do: path

  defp lean_path(law, library),
    do: "test/support/lean/" <> Jason.decode!(library)[law["law"]] <> ".lean"

  defp theorem_targets(%{"kind" => "lean", "theorems" => theorems}), do: theorems
  defp theorem_targets(law), do: ["«#{law["law"]}/#{law["arity"]}»"]

  defp contract(%{"kind" => "lean"}), do: %{"status" => "native_statement_only"}

  defp contract(law) do
    case Source.declaration(Config.root(), law) do
      {:ok, d} ->
        %{
          "status" => "source_read",
          "requires" => Macro.to_string(d.requires),
          "expects" => Macro.to_string(d.expects),
          "parameters" => Enum.map(d.formals, &Atom.to_string/1),
          "source" => d.source_text,
          "line" => d.source_line,
          "end_line" => d.source_end_line
        }

      {:error, reason} ->
        %{"status" => "unsupported_source_context", "reason" => inspect(reason)}
    end
  end

  def declaration(files, path, target) do
    bytes = files[path] || ""
    short = target |> String.split(".") |> List.last()
    lines = String.split(bytes, "\n")

    candidates =
      Enum.with_index(lines, 1)
      |> Enum.filter(fn {line, _} ->
        Regex.match?(
          ~r/^\s*(?:theorem|lemma|def|abbrev)\s+#{Regex.escape(target)}(?:\s|\()/u,
          line
        ) or
          Regex.match?(
            ~r/^\s*(?:theorem|lemma|def|abbrev)\s+#{Regex.escape(short)}(?:\s|\()/u,
            line
          )
      end)

    case candidates do
      [{_, start}] ->
        tail = Enum.drop(lines, start - 1)

        body =
          [
            hd(tail)
            | Enum.take_while(
                tl(tail),
                &(not Regex.match?(~r/^(?:theorem|lemma|def|abbrev|end\b)/u, &1))
              )
          ]
          |> Enum.join("\n")
          |> String.trim_trailing()

        header = String.split(body, ":=", parts: 2) |> hd() |> String.trim()

        %{
          "name" => target,
          "path" => path,
          "line" => start,
          "text" => body,
          "header" => header,
          "sha256" => Anchor.sha(bytes),
          "status" => "source_declaration_not_elaborated_evidence"
        }

      _ ->
        %{
          "name" => target,
          "path" => path,
          "status" => "missing_or_ambiguous_declaration",
          "text" => "",
          "header" => ""
        }
    end
  end

  defp proof_steps(declaration, steps) do
    Enum.map(steps, fn step ->
      case :binary.matches(declaration["text"], step["anchor"]) do
        [{offset, _}] ->
          line =
            declaration["line"] +
              length(String.split(binary_part(declaration["text"], 0, offset), "\n")) - 1

          code =
            declaration["text"]
            |> String.split("\n")
            |> Enum.drop(line - declaration["line"])
            |> Enum.take(7)
            |> Enum.join("\n")

          Map.merge(step, %{"line" => line, "code" => code, "path" => declaration["path"]})

        _ ->
          Map.merge(step, %{
            "line" => nil,
            "code" => "Anchor missing or ambiguous; reading unavailable"
          })
      end
    end)
  end

  defp references(declarations, files) do
    names =
      declarations
      |> Enum.flat_map(fn d ->
        Regex.scan(~r/HoldLedgerProof\.[A-Za-z_][\w.]*/u, d["text"]) |> List.flatten()
      end)
      |> Enum.uniq()

    Enum.map(names, fn name ->
      candidates =
        for {path, _} <- files,
            String.starts_with?(path, "test/support/lean/"),
            d = declaration(files, path, name),
            d["text"] != "",
            do: d

      %{
        "name" => name,
        "declarations" => candidates,
        "scope" => "textual_source_reference_not_kernel_footprint"
      }
    end)
  end

  defp imports(source),
    do:
      Regex.scan(~r/^\s*(?:public )?import (?:all )?([^\s]+).*$/mu, source)
      |> Enum.map(&Enum.at(&1, 1))

  defp policy(bytes, nil), do: %{"quote" => nil, "line" => nil, "sha256" => Anchor.sha(bytes)}

  defp policy(bytes, quote) do
    line = bytes |> String.split("\n") |> Enum.find_index(&String.contains?(&1, quote))

    %{
      "quote" => if(is_integer(line), do: quote),
      "line" => if(is_integer(line), do: line + 1),
      "sha256" => Anchor.sha(bytes)
    }
  end

  defp source_record(path, bytes),
    do: %{
      "id" => String.slice(Anchor.sha(path), 0, 24),
      "path" => path,
      "sha256" => Anchor.sha(bytes)
    }

  defp formal_summary do
    result = Trace.formal()

    %{
      "status" => Atom.to_string(result.status),
      "detail" => result.detail,
      "scope" => "original_required_scope_validator",
      "report_sha256" => Map.get(result, :report_sha256)
    }
  end

  defp focused(slug) do
    path = "tmp/verification/claim-reading/index.json"

    with {:ok, bytes} <- Anchor.read_under(Config.root(), path),
         true <- byte_size(bytes) < 2_000_000,
         {:ok, index} <- Jason.decode(bytes),
         true <- index["schema_version"] == 1,
         true <- is_map(index["sources"]) and map_size(index["sources"]) > 0,
         true <-
           Enum.all?(
             ~w(mix.lock uv.lock .tool-versions verification/laws.json verification/obligations.json test/support/proof_case.ex lib/hold_ledger/ledger.ex lib/hold_ledger/spec.ex),
             &Map.has_key?(index["sources"], &1)
           ),
         true <-
           Enum.all?(index["sources"], fn {path, sha} ->
             ProofEvidence.digest_file(Config.root(), path) == sha
           end),
         row when is_map(row) <- index["claims"][slug],
         true <- row["status"] == "elaborated" and row["full_acceptance"] == false,
         true <- is_list(row["artifacts"]) and row["artifacts"] != [],
         true <-
           Enum.all?(row["artifacts"], fn item ->
             ProofEvidence.digest_file(Config.root(), item["path"]) == item["sha256"]
           end) do
      Map.put(row, "scope", "focused_original_lean_elaboration_not_full_acceptance")
    else
      _ -> %{"status" => "missing_or_stale", "scope" => "no_fresh_producer_artifact"}
    end
  rescue
    _ -> %{"status" => "missing_or_stale", "scope" => "no_fresh_producer_artifact"}
  end
end
