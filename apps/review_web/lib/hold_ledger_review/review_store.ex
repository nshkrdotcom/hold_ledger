defmodule HoldLedgerReview.ReviewStore do
  @moduledoc "Single writer for current trace documents, using synced atomic replacement."
  use GenServer
  alias HoldLedgerReview.{Canonical, Config}

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, if(name, do: [name: name], else: []))
  end

  @impl true
  def init(opts) do
    dir =
      Keyword.get(
        opts,
        :dir,
        Application.get_env(
          :hold_ledger_review_web,
          :review_store_dir,
          Path.join(Config.root(), "tmp/review_studio/reviews")
        )
      )

    with :ok <- File.mkdir_p(dir),
         {:ok, %{type: :directory}} <- File.lstat(dir) do
      state = %{
        dir: Path.expand(dir),
        writer: Keyword.get(opts, :writer, &atomic_write/2)
      }

      {:ok, state}
    else
      _ -> {:stop, :unsafe_review_directory}
    end
  end

  @impl true
  def handle_call({:trace_create, mode, amount, slots}, _from, state) do
    result =
      with {:ok, doc} <- HoldLedgerReview.Trace.new(mode, amount, slots),
           do: HoldLedgerReview.Trace.write(state, doc)

    {:reply, result, state}
  end

  def handle_call({:trace_create_from, json}, _from, state) do
    result =
      with {:ok, native} <- HoldLedgerReview.TermCodec.decode_state(json),
           true <- HoldLedger.Spec.valid?(native),
           {:ok, doc} <- HoldLedgerReview.Trace.new("ledger", elem(native, 0), elem(native, 1)),
           do: HoldLedgerReview.Trace.write(state, Map.put(doc, "initial", json))

    {:reply, result, state}
  end

  def handle_call({:trace_get, id}, _from, state) do
    {:reply, HoldLedgerReview.Trace.read(state.dir, id), state}
  end

  def handle_call({:trace_command, id, revision, request_id, action}, _from, state) do
    result =
      with {:ok, command} <- canonical_command(action),
           {:ok, doc} <- HoldLedgerReview.Trace.read(state.dir, id),
           {:ok, updated} <-
             HoldLedgerReview.Trace.apply_command(doc, revision, request_id, command),
           do: HoldLedgerReview.Trace.write(state, updated)

    {:reply, result, state}
  end

  defp canonical_command(command) when is_map(command) do
    if Enum.all?(Map.keys(command), &(is_binary(&1) or is_atom(&1))) do
      normalized =
        Map.new(command, fn {k, v} -> {if(is_atom(k), do: Atom.to_string(k), else: k), v} end)

      try do
        _ = Canonical.json(normalized)
        {:ok, normalized}
      rescue
        _ -> {:error, :invalid_command}
      end
    else
      {:error, :invalid_command}
    end
  end

  defp canonical_command(_), do: {:error, :invalid_command}

  def atomic_write(path, bytes) do
    tmp =
      path <> "." <> Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false) <> ".tmp"

    result =
      with {:ok, io} <- :file.open(String.to_charlist(tmp), [:write, :binary, :exclusive]),
           do: sync_and_close(io, bytes)

    case result do
      :ok ->
        case File.rename(tmp, path) do
          :ok ->
            :ok

          error ->
            File.rm(tmp)
            error
        end

      error ->
        File.rm(tmp)
        error
    end
  end

  defp sync_and_close(io, bytes) do
    with :ok <- :file.write(io, bytes), do: :file.sync(io)
  after
    :file.close(io)
  end
end
