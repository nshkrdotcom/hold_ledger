defmodule HoldLedgerReview.Trace do
  @moduledoc """
  Shared, bounded trace operations for LiveView and local command callers.
  Ledger/Spec, Exposure and the original ClaimProbe own all execution semantics.
  Persistence runs through ReviewStore's single writer and atomic write boundary.
  """
  alias HoldLedger.{Exposure, Ledger, Spec}
  alias HoldLedgerReview.{Canonical, ClaimProbe, Claims, Config, ProofEvidence, TermCodec}

  @max_steps 64
  @context_paths ~w(guides/specification.md guides/processors.md guides/runtime.md mix.lock apps/review_web/mix.lock .tool-versions lean-toolchain uv.lock pyproject.toml .python-version scripts/toolchains.json)

  def create(mode \\ "ledger", amount \\ 100, slots \\ 2),
    do: GenServer.call(HoldLedgerReview.ReviewStore, {:trace_create, mode, amount, slots}, 60_000)

  def create_from(json),
    do: GenServer.call(HoldLedgerReview.ReviewStore, {:trace_create_from, json}, 60_000)

  def get(id), do: GenServer.call(HoldLedgerReview.ReviewStore, {:trace_get, id}, 60_000)

  def command(id, revision, request_id, action),
    do:
      GenServer.call(
        HoldLedgerReview.ReviewStore,
        {:trace_command, id, revision, request_id, action},
        60_000
      )

  def identity do
    with {:ok, context} <- Claims.source_context(Config.root(), @context_paths) do
      {:ok,
       %{
         "source" => context.generation.source.sha256,
         "evaluator" => context.generation.evaluator_id,
         "policy" => context.digests["guides/specification.md"],
         "context" => Map.take(context.digests, @context_paths)
       }}
    end
  end

  def current?(doc), do: identity() == {:ok, doc["identity"]}

  def new(mode, amount, slots) when mode in ~w(ledger exposure) do
    with {:ok, json} <- TermCodec.encode_state({amount, slots, 0, 0, []}),
         {:ok, identity} <- identity() do
      {:ok, state} =
        if mode == "ledger",
          do: {:ok, json},
          else: TermCodec.encode_exposure(Exposure.init(amount, slots))

      {:ok,
       %{
         "schema_version" => 2,
         "id" => "trace-" <> token(),
         "identity" => identity,
         "mode" => mode,
         "revision" => 0,
         "initial" => state,
         "steps" => [],
         "notes" => [],
         "challenges" => [],
         "commands" => [],
         "comparison" => nil,
         "created_at" => DateTime.to_iso8601(DateTime.utc_now())
       }}
    end
  end

  def new(_, _, _), do: {:error, :invalid_mode}

  def apply_command(doc, revision, request_id, action)
      when is_integer(revision) and is_map(action) do
    digest = Canonical.digest(%{"revision" => revision, "action" => action})
    previous = Enum.find(doc["commands"], &(&1["id"] == request_id))

    cond do
      not valid_request?(request_id) ->
        {:error, :invalid_request_id}

      same_command?(previous, digest) ->
        {:ok, doc}

      previous ->
        {:error, :request_id_conflict}

      revision != doc["revision"] ->
        {:error, :revision_conflict}

      not current?(doc) ->
        {:error, :stale_source}

      length(doc["commands"]) >= 256 ->
        {:error, :trace_limit}

      true ->
        with {:ok, updated} <- change(doc, action),
             true <- current?(doc) do
          {:ok,
           updated
           |> Map.put("revision", revision + 1)
           |> Map.update!("commands", &(&1 ++ [%{"id" => request_id, "digest" => digest}]))}
        else
          false -> {:error, :stale_source}
          error -> error
        end
    end
  end

  def apply_command(_, _, _, _), do: {:error, :invalid_trace_command}

  defp same_command?(%{"digest" => digest}, digest), do: true
  defp same_command?(_, _), do: false

  defp valid_request?(id), do: is_binary(id) and byte_size(id) in 8..100

  defp change(doc, %{"kind" => "append", "parent" => parent, "event" => event} = action)
       when map_size(action) == 3 do
    with true <- length(doc["steps"]) < @max_steps,
         {:ok, before} <- state_at(doc, parent),
         {:ok, receipt} <- execute(doc["mode"], before, event) do
      id =
        Canonical.digest(%{
          "parent" => parent,
          "receipt" => receipt,
          "identity" => doc["identity"]
        })

      origin =
        case step(doc, parent) do
          %{"origin" => origin} when origin != "computed" -> "hypothetical_continuation"
          _ -> "computed"
        end

      step = Map.merge(receipt, %{"id" => id, "parent" => parent, "origin" => origin})
      {:ok, Map.update!(doc, "steps", &Enum.uniq_by(&1 ++ [step], fn s -> s["id"] end))}
    else
      false -> {:error, :trace_limit}
      error -> error
    end
  end

  defp change(doc, %{"kind" => "candidate", "parent" => parent, "output" => output} = action)
       when map_size(action) == 3 do
    with true <- doc["mode"] == "ledger" and length(doc["steps"]) < @max_steps,
         step when is_map(step) <- step(doc, parent),
         {:ok, before} <- TermCodec.decode_state(step["before"]),
         {:ok, event} <- TermCodec.decode_event(step["event"]),
         {:ok, candidate} <- TermCodec.decode_output(output),
         true <- Spec.valid?(elem(candidate, 0)) do
      checks = checks(before, event, candidate)

      receipt = %{
        "before" => step["before"],
        "after" => output["after"],
        "event" => step["event"],
        "output" => output,
        "oracle" => step["oracle"],
        "checks" => checks,
        "origin" => "hypothetical",
        "parent" => step["parent"],
        "challenge_of" => parent
      }

      id = Canonical.digest(receipt)

      {:ok,
       Map.update!(
         doc,
         "steps",
         &Enum.uniq_by(&1 ++ [Map.put(receipt, "id", id)], fn s -> s["id"] end)
       )}
    else
      _ -> {:error, :candidate_continuation_requires_valid_state}
    end
  end

  defp change(
         doc,
         %{"kind" => "note", "step" => step_id, "text" => text, "disposition" => disposition} =
           action
       )
       when map_size(action) == 4 and is_binary(text) and byte_size(text) in 1..2000 and
              disposition in ~w(concern considered needs_evidence) do
    if step_id == "start" or step(doc, step_id) do
      note = Map.merge(action, %{"origin" => "human", "revision" => doc["revision"] + 1})
      {:ok, Map.update!(doc, "notes", &(&1 ++ [note]))}
    else
      {:error, :unknown_step}
    end
  end

  defp change(
         doc,
         %{"kind" => "challenge", "step" => id, "slug" => slug, "output" => output} = action
       )
       when map_size(action) == 4 do
    with true <- length(doc["challenges"]) < 32,
         step when is_map(step) <- step(doc, id),
         {:ok, _} <- Claims.claim(slug),
         {:ok, before} <- TermCodec.decode_state(step["before"]),
         {:ok, event} <- TermCodec.decode_event(step["event"]),
         {:ok, native} <- TermCodec.decode_output(output) do
      finding = HoldLedgerReview.ClaimProbe.probe(slug, before, event, native)

      record =
        Map.merge(action, %{
          "source_identity" => doc["identity"],
          "status" => Atom.to_string(finding.status),
          "origin" => "pointwise_challenge",
          "revision" => doc["revision"] + 1
        })

      {:ok, Map.update!(doc, "challenges", &(&1 ++ [record]))}
    else
      _ -> {:error, :invalid_challenge}
    end
  end

  defp change(doc, %{"kind" => "comparison", "id" => id} = action) when map_size(action) == 2 do
    with {:ok, _package, :ok} <- HoldLedgerReview.Part3Store.get(id),
         do: {:ok, Map.put(doc, "comparison", id)}
  end

  defp change(_, _), do: {:error, :invalid_trace_command}

  def state_at(doc, "start"), do: {:ok, doc["initial"]}

  def state_at(doc, id) do
    case step(doc, id) do
      nil -> {:error, :unknown_step}
      step -> {:ok, step["after"]}
    end
  end

  def step(doc, id), do: Enum.find(doc["steps"], &(&1["id"] == id))

  def path(doc, id), do: path(doc, id, [])
  defp path(_doc, "start", acc), do: acc

  defp path(doc, id, acc) when length(acc) <= @max_steps do
    case step(doc, id) do
      nil -> acc
      step -> path(doc, step["parent"], [step | acc])
    end
  end

  def execute("ledger", json, event_json) do
    with :ok <- Claims.freshness(),
         {:ok, before} <- TermCodec.decode_state(json),
         true <- Spec.valid?(before),
         {:ok, event} <- TermCodec.decode_event(event_json),
         actual = Ledger.step(before, event),
         {:ok, output} <- TermCodec.encode_output(actual),
         {:ok, oracle} <- TermCodec.encode_output(Spec.expected_step(before, event)) do
      result = %{
        "before" => json,
        "after" => output["after"],
        "event" => event_json,
        "output" => output,
        "oracle" => oracle,
        "checks" => checks(before, event, actual)
      }

      with :ok <- Claims.freshness(), do: {:ok, result}
    else
      false -> {:error, :invalid_starting_state}
      error -> error
    end
  end

  def execute("exposure", json, event_json) do
    with :ok <- Claims.freshness(),
         {:ok, before} <- TermCodec.decode_exposure(json),
         true <- Spec.exposure_valid?(before),
         {:ok, event} <- TermCodec.decode_exposure_event(event_json),
         {:ok, after_json} <- TermCodec.encode_exposure(Exposure.step(before, event)),
         :ok <- Claims.freshness() do
      {:ok,
       %{
         "before" => json,
         "after" => after_json,
         "event" => event_json,
         "output" => nil,
         "oracle" => nil,
         "checks" => [],
         "scope" => "original_exposure_model_no_pointwise_lean_claim"
       }}
    else
      false -> {:error, :invalid_starting_state}
      error -> error
    end
  end

  def execute(_, _, _), do: {:error, :unsupported_execution_mode}

  def candidate(doc, id, json) do
    with true <- current?(doc),
         step when is_map(step) <- step(doc, id),
         {:ok, before} <- TermCodec.decode_state(step["before"]),
         {:ok, event} <- TermCodec.decode_event(step["event"]),
         {:ok, output} <- TermCodec.decode_output(json) do
      result = %{
        "checks" => checks(before, event, output),
        "valid_after" => Spec.valid?(elem(output, 0)),
        "output" => json,
        "origin" => "hypothetical"
      }

      with true <- current?(doc), do: {:ok, result}
    else
      _ -> {:error, :invalid_candidate}
    end
  end

  defp checks(before, event, output) do
    slugs = HoldLedgerReview.Adversarial.active_slugs(event)
    rows = ClaimProbe.probe_all(before, event, output, slugs: slugs)

    Enum.map(slugs, fn slug ->
      row = rows[slug]

      %{
        "slug" => slug,
        "status" => Atom.to_string(row.status),
        "reason" => inspect(row.reason),
        "bindings" => row.bindings_tested,
        "complete" => row.exhaustive_for_source_domain
      }
    end)
  end

  def formal do
    generation = Claims.snapshot()

    ProofEvidence.load(
      Config.root(),
      Application.get_env(:hold_ledger_review_web, :proof_report),
      Enum.map(generation.source.catalog, & &1["slug"])
    )
  end

  def sources do
    {:ok, catalog} = Claims.catalog()

    Enum.uniq(
      [
        "guides/specification.md",
        "guides/processors.md",
        "guides/runtime.md",
        "lib/hold_ledger/ledger.ex",
        "lib/hold_ledger/spec.ex",
        "lib/hold_ledger/exposure.ex",
        "lib/hold_ledger/environment.ex"
      ] ++ Enum.map(catalog, & &1["file"])
    )
  end

  def source(path) do
    with true <- path in sources(),
         {:ok, context} <- Claims.source_context(Config.root(), [path]),
         bytes = context.bytes[path],
         true <- byte_size(bytes) <= 256_000 do
      {:ok, bytes, context.digests[path]}
    else
      _ -> {:error, :source_unavailable}
    end
  end

  # ReviewStore calls these inside its existing single-writer mailbox.
  def read(dir, id) do
    with true <- is_binary(id) and Regex.match?(~r/\Atrace-[A-Za-z0-9_-]{24}\z/, id),
         path = Path.join(dir, id <> ".json"),
         {:ok, %{type: :regular, size: size}} <- File.lstat(path),
         true <- size <= 4_000_000,
         {:ok, bytes} <- File.read(path),
         {:ok, doc} <- Jason.decode(bytes),
         true <- doc["schema_version"] == 2 and doc["id"] == id,
         true <- doc["document_digest"] == Canonical.digest(Map.delete(doc, "document_digest")) do
      {:ok, doc}
    else
      _ -> {:error, :trace_unavailable}
    end
  rescue
    _ -> {:error, :trace_unavailable}
  end

  def write(state, doc) do
    body = Map.delete(doc, "document_digest")
    record = Map.put(body, "document_digest", Canonical.digest(body))
    bytes = Canonical.json(record)

    if byte_size(bytes) <= 4_000_000 do
      with :ok <- state.writer.(Path.join(state.dir, doc["id"] <> ".json"), bytes),
           do: {:ok, record}
    else
      {:error, :trace_too_large}
    end
  end

  def token, do: Base.url_encode64(:crypto.strong_rand_bytes(18), padding: false)
end
