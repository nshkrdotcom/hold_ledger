defmodule HoldLedgerReview.Claims do
  @moduledoc """
  A single immutable, source-derived evaluator generation. It is compiled from
  registered law AST once at application start; never compiled by a request.
  Source, inventory, compiler code and loaded BEAM fingerprints are checked for
  *every* new probe. Drift requires a controlled rebuild/restart (no hot purge).
  """
  use GenServer
  alias HoldLedgerReview.{Config, Claims, Anchor}
  alias Claims.{Source, Compiler}

  @fingerprinted [
    HoldLedger.Ledger,
    HoldLedger.Spec,
    HoldLedgerReview.Claims,
    HoldLedgerReview.Claims.Source,
    HoldLedgerReview.Claims.Compiler,
    HoldLedgerReview.ClaimProbe,
    HoldLedgerReview.TermCodec,
    HoldLedgerReview.Canonical,
    HoldLedgerReview.Anchor,
    HoldLedgerReview.Config
  ]

  def start_link(_opts), do: GenServer.start_link(__MODULE__, :startup, name: __MODULE__)

  @impl true
  def init(:startup) do
    {:ok, initialize(Config.root())}
  end

  def initialize(root) do
    with {:ok, source} <- Source.snapshot(root),
         {raw, errors} <- Source.extract(root, source),
         {compiled, diagnostics} <- compile_claims(raw, errors),
         {:ok, generated} <- Compiler.compile(source.sha256, compiled),
         {:ok, fingerprint} <- loaded_fingerprint(),
         {:ok, generated_identity} <- generated_identity(generated) do
      %{
        status: :ready,
        source: source,
        law_details: raw,
        claims: compiled,
        diagnostics: diagnostics,
        loaded_fingerprint: fingerprint,
        generated_identity: generated_identity,
        module: generated,
        evaluator_id: Anchor.sha(source.sha256 <> fingerprint <> generated_identity <> Source.version())
      }
    else
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

      %{reason: reason} -> {:error, reason}
    end
  end

  def claim(_), do: {:error, :unknown_law}

  def freshness(root \\ Config.root()) do
    case snapshot() do
      %{status: :ready} = generation ->
        with true <- Config.source_matches?(root),
             {:ok, current} <- Source.snapshot(root),
             true <- current.sha256 == generation.source.sha256,
             {:ok, current_fingerprint} <- loaded_fingerprint(),
             true <- current_fingerprint == generation.loaded_fingerprint,
             {:ok, current_generated_identity} <- generated_identity(generation.module),
             true <- current_generated_identity == generation.generated_identity,
             true <- generation.module.claim_manifest_sha256() == current.sha256,
             true <- generation.module.compiler_version() == Source.version() do
          :ok
        else
          _ -> {:error, :source_or_compiled_code_drift}
        end

      _ -> {:error, :source_or_compiled_code_drift}
    end
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
      {:ok, fingerprints} -> {:ok, fingerprints |> Enum.sort() |> :erlang.term_to_binary() |> Anchor.sha()}
      error -> error
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

  def evaluate(slug, formal_values, output, root \\ Config.root()) do
    with :ok <- freshness(root),
         {:ok, _} <- HoldLedgerReview.TermCodec.encode_output(output),
         {:ok, _law} <- claim(slug) do
      module = snapshot().module

      evaluation =
        try do
          case apply(module, :requires, [slug, formal_values]) do
            true ->
              {:ok,
               %{
                 requires: true,
                 actual: apply(module, :actual, [slug, formal_values]),
                 candidate: apply(module, :candidate, [slug, formal_values, output]),
                 operation_output: apply(module, :target, [slug, formal_values])
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

      case freshness(root) do
        :ok -> evaluation
        _ -> {:error, :source_or_compiled_code_drift}
      end
    end
  end
end
