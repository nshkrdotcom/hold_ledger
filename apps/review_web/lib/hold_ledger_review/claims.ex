defmodule HoldLedgerReview.Claims do
  @moduledoc """
  A single immutable, source-derived evaluator generation. It is compiled from
  registered law AST once at application start; never compiled by a request.
  Source, inventory, compiler code and loaded BEAM fingerprints are checked for
  *every* new probe. Drift requires a controlled rebuild/restart (no hot purge).
  """
  use GenServer
  alias HoldLedgerReview.{Anchor, Config, TermCodec}
  alias HoldLedgerReview.Claims.{Compiler, Source}

  @fingerprinted [
    HoldLedger.Ledger,
    HoldLedger.Spec,
    HoldLedger.Composite,
    HoldLedger.Outbox,
    HoldLedger.Environment,
    HoldLedger.Exposure,
    HoldLedgerReview.Trace,
    HoldLedgerReview.Claims,
    HoldLedgerReview.Claims.Source,
    HoldLedgerReview.Claims.Compiler,
    HoldLedgerReview.Claims.Explanation,
    HoldLedgerReview.ProofReading,
    HoldLedgerReview.ProofReading.Links,
    HoldLedgerReview.Contrast,
    HoldLedgerReview.ClaimProbe,
    HoldLedgerReview.TermCodec,
    HoldLedgerReview.Canonical,
    HoldLedgerReview.Anchor,
    HoldLedgerReview.Config
  ]

  @memo_table :hold_ledger_review_generation_cache
  @memo_limit 64

  def start_link(_opts), do: GenServer.start_link(__MODULE__, :startup, name: __MODULE__)

  @impl true
  def init(:startup) do
    :ets.new(@memo_table, [:named_table, :set, :public, read_concurrency: true])
    {:ok, initialize(Config.root())}
  end

  @doc """
  Bounded memoization of immutable derived data, owned by this evaluator process.
  Callers retain their freshness checks. Keys bind the generation, checkout,
  calling module's loaded identity and complete inputs; no time-based validity.
  """
  def memoize(module, inputs, compute) do
    case Process.whereis(__MODULE__) do
      nil -> compute.()
      _pid -> memoize_generation(snapshot(), module, inputs, compute)
    end
  end

  defp memoize_generation(%{status: :ready} = generation, module, inputs, compute) do
    key =
      :crypto.hash(
        :sha256,
        :erlang.term_to_binary(
          {generation.evaluator_id, Config.root(), module, module.module_info(:md5), inputs}
        )
      )

    case :ets.lookup(@memo_table, key) do
      [{^key, value}] ->
        value

      [] ->
        value = compute.()
        # Only successful pure results belong in the cache. Failures are retried
        # against current source; eviction affects cost, never evidence validity.
        maybe_memoize(key, value)
        value
    end
  end

  defp memoize_generation(_generation, _module, _inputs, compute), do: compute.()

  defp maybe_memoize(key, {:ok, _} = value), do: put_memoized(key, value)
  defp maybe_memoize(key, {:ok, _, _} = value), do: put_memoized(key, value)
  defp maybe_memoize(_key, _value), do: :ok

  defp put_memoized(key, value) do
    if :ets.info(@memo_table, :size) >= @memo_limit, do: :ets.delete_all_objects(@memo_table)
    :ets.insert_new(@memo_table, {key, value})
    :ok
  end

  def initialize(root) do
    with true <-
           Config.source_matches?(root) and Config.loaded_core_matches?() and
             Config.build_matches?(root),
         {:ok, source} <- Source.snapshot(root),
         {raw, errors} <- Source.extract(root, source),
         {compiled, diagnostics} <- compile_claims(raw, errors),
         {:ok, generated} <- Compiler.compile(source.sha256, compiled),
         {:ok, fingerprint} <- loaded_fingerprint(),
         {:ok, generated_identity} <- generated_identity(generated),
         true <- Config.source_matches?(root) and Config.build_matches?(root),
         true <- Source.matches?(root, source) do
      %{
        status: :ready,
        source: source,
        law_details: raw,
        claims: compiled,
        diagnostics: diagnostics,
        loaded_fingerprint: fingerprint,
        loaded_modules: Map.new(@fingerprinted, &{&1, &1.module_info(:md5)}),
        generated_identity: generated_identity,
        module: generated,
        evaluator_id:
          Anchor.sha(source.sha256 <> fingerprint <> generated_identity <> Source.version())
      }
    else
      false -> %{status: :unavailable, reason: :source_or_compiled_code_drift, diagnostics: %{}}
      {:error, reason} -> %{status: :unavailable, reason: reason, diagnostics: %{}}
    end
  end

  defp compile_claims(raw, errors) do
    Enum.reduce(raw, {%{}, errors}, fn {slug, law}, {compiled, diagnostics} ->
      case Compiler.prepare(law) do
        {:ok, prepared} -> {Map.put(compiled, slug, prepared), diagnostics}
        {:error, reason} -> {compiled, Map.put(diagnostics, slug, reason)}
      end
    end)
  end

  def snapshot, do: GenServer.call(__MODULE__, :snapshot)

  @impl true
  def handle_call(:snapshot, _from, state), do: {:reply, state, state}

  def catalog do
    case snapshot() do
      %{status: :ready, source: %{catalog: list}} -> {:ok, list}
      %{reason: reason} -> {:error, reason}
    end
  end

  def claim(slug) when is_binary(slug) do
    case snapshot() do
      %{status: :ready, claims: claims, diagnostics: errors} ->
        case Map.fetch(claims, slug) do
          {:ok, law} -> {:ok, law}
          :error -> {:error, Map.get(errors, slug, :unknown_law)}
        end

      %{reason: reason} ->
        {:error, reason}
    end
  end

  def claim(_), do: {:error, :unknown_law}

  def freshness(root \\ Config.root()) do
    with {:ok, _context} <- source_context(root), do: :ok
  end

  @doc "One exact-byte source pass, including any review/report manifest paths."
  def source_context(root \\ Config.root(), extra_paths \\ []) do
    case snapshot() do
      %{status: :ready} = generation -> current_source_context(root, extra_paths, generation)
      _ -> {:error, :source_or_compiled_code_drift}
    end
  end

  defp current_source_context(root, extra_paths, generation) do
    # Initialization already binds these source hashes to the compiled build.
    # Compare them once here, rather than rereading the core/support files again.
    # Loaded identity is the MD5 of the actual in-memory module, not a repeated
    # disk lookup of a BEAM that may no longer be the running module.
    with {:ok, context} <- Source.current_sources(root, generation.source, extra_paths),
         true <- Config.loaded_core_matches?(),
         true <-
           Enum.all?(generation.loaded_modules, fn {module, expected} ->
             module.module_info(:md5) == expected
           end),
         {:ok, identity} <- generated_identity(generation.module),
         true <- identity == generation.generated_identity,
         true <- generation.module.claim_manifest_sha256() == generation.source.sha256,
         true <- generation.module.compiler_version() == Source.version() do
      {:ok, Map.put(context, :generation, generation)}
    else
      _ -> {:error, :source_or_compiled_code_drift}
    end
  rescue
    _ -> {:error, :source_or_compiled_code_drift}
  end

  def loaded_fingerprint do
    Enum.reduce_while(@fingerprinted, {:ok, []}, fn module, {:ok, acc} ->
      with true <- Code.ensure_loaded?(module),
           {^module, binary, _path} <- :code.get_object_code(module),
           md5 when is_binary(md5) <- module.module_info(:md5) do
        {:cont, {:ok, [{Atom.to_string(module), Anchor.sha(binary), Base.encode16(md5)} | acc]}}
      else
        _ -> {:halt, {:error, :unavailable_loaded_code_identity}}
      end
    end)
    |> case do
      {:ok, fingerprints} ->
        {:ok, fingerprints |> Enum.sort() |> :erlang.term_to_binary() |> Anchor.sha()}

      error ->
        error
    end
  end

  # Module.create/3 loads its code from memory, so :code.get_object_code/1
  # need not find an on-disk BEAM for this one module. The loaded module's
  # compiler-provided md5 is checked in addition to the immutable manifest.
  def generated_identity(module) do
    with true <- Code.ensure_loaded?(module),
         md5 when is_binary(md5) <- module.module_info(:md5) do
      {:ok, Base.encode16(md5, case: :lower)}
    else
      _ -> {:error, :unavailable_generated_code_identity}
    end
  rescue
    _ -> {:error, :unavailable_generated_code_identity}
  end

  @doc """
  Evaluate trusted work against one immutable generation. Fresh source and loaded
  code are checked before and after the entire operation; no results escape when
  its final identity check fails. Nothing is cached across operations or processes.
  """
  def with_generation(root, callback) do
    with :ok <- freshness(root) do
      generation = snapshot()

      evaluate = fn slug, values, output ->
        evaluate_generation(generation, slug, values, output)
      end

      result = callback.(evaluate)

      case freshness(root) do
        :ok -> {:ok, result}
        error -> error
      end
    end
  end

  def evaluate(slug, formal_values, output, root \\ Config.root()) do
    with {:ok, result} <- with_generation(root, & &1.(slug, formal_values, output)), do: result
  end

  def explain(slug, formal_values, output, root \\ Config.root()) do
    with {:ok, result} <-
           with_generation(root, &explain_generation(&1, slug, formal_values, output)),
         do: result
  rescue
    _ -> {:error, :source_observation_unavailable}
  end

  defp explain_generation(evaluate, slug, values, output) do
    with {:ok, aggregate} <- evaluate.(slug, values, output) do
      module = snapshot().module
      requires = module.inspect_requires(slug, values)

      if requires.value != aggregate.requires,
        do: raise(ArgumentError, "condition observation mismatch")

      explain_output(module, slug, values, output, aggregate, requires)
    end
  end

  defp explain_output(module, slug, values, output, %{requires: true} = aggregate, requires) do
    actual = module.inspect_actual(slug, values)
    candidate = module.inspect_candidate(slug, values, output)

    if actual.value != aggregate.actual or candidate.value != aggregate.candidate,
      do: raise(ArgumentError, "promise observation mismatch")

    {:ok,
     %{
       requires: observation(requires),
       actual: observation(actual),
       candidate: observation(candidate)
     }}
  end

  defp explain_output(_, _, _, _, _, requires),
    do: {:ok, %{requires: observation(requires), actual: nil, candidate: nil}}

  defp observation(node) do
    value =
      case TermCodec.encode_inspection(node.value) do
        {:ok, value} -> value
        _ -> %{"unavailable" => "outside_typed_display_domain"}
      end

    %{
      "expression" => node.expression,
      "value" => value,
      "status" => Map.get(node, :status, "evaluated"),
      "children" => Enum.map(node.children, &observation/1),
      "helper" => Map.get(node, :helper),
      "source_path" => Map.get(node, :source_path),
      "source_line" => Map.get(node, :source_line)
    }
  end

  defp evaluate_generation(generation, slug, formal_values, output) do
    with {:ok, _} <- TermCodec.encode_output(output),
         {:ok, _law} <- generation_claim(generation, slug) do
      module = generation.module

      try do
        case module.requires(slug, formal_values) do
          true ->
            {:ok,
             %{
               requires: true,
               actual: module.actual(slug, formal_values),
               candidate: module.candidate(slug, formal_values, output),
               operation_output: module.target(slug, formal_values)
             }}

          false ->
            {:ok, %{requires: false}}

          _ ->
            {:error, :non_boolean_requires}
        end
      rescue
        _ -> {:error, :source_expression_error}
      catch
        _, _ -> {:error, :source_expression_error}
      end
    end
  end

  defp generation_claim(generation, slug) do
    case Map.fetch(generation.claims, slug) do
      {:ok, law} -> {:ok, law}
      :error -> {:error, Map.get(generation.diagnostics, slug, :unknown_law)}
    end
  end
end
