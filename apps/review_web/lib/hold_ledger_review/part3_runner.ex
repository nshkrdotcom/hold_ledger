defmodule HoldLedgerReview.Part3Runner do
  @moduledoc """
  Bounded OS-process coordinator. Each snapshot is compiled and executed by the
  pinned local wrapper in its own MIX_BUILD_PATH and BEAM. The selected code is
  operator-trusted: an OS process is not a hostile-code sandbox.
  """
  use GenServer
  alias HoldLedgerReview.{Canonical, Config, Part3Snapshots, Part3Store}

  @max_active 2
  @max_input 400_000
  @job_dir "tmp/review_studio/jobs"

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    Process.flag(:trap_exit, true)
    {:ok, %{ports: %{}, ids: %{}}}
  end

  def replay(review_id, witness) do
    with {:ok, package, attempts} <- Part3Store.queue_replay(review_id, witness),
         :ok <- (if attempts == [], do: :ok, else: GenServer.call(__MODULE__, {:launch, review_id, package, attempts})) do
      {:ok, attempts}
    end
  end

  def verify(review_id) do
    with {:ok, package, attempt} <- Part3Store.queue_verification(review_id),
         :ok <- GenServer.call(__MODULE__, {:launch, review_id, package, [attempt]}) do
      {:ok, attempt}
    end
  end

  def cancel(review_id, attempt_id), do: GenServer.call(__MODULE__, {:cancel, review_id, attempt_id})

  @impl true
  def handle_call({:launch, id, p, attempts}, _from, state) do
    if map_size(state.ports) + length(attempts) > @max_active do
      Enum.each(attempts, &Part3Store.fail_attempt(id, &1["id"], :resource_limit))
      {:reply, {:error, :runner_busy}, state}
    else
      {next, outcomes} = Enum.reduce(attempts, {state, []}, fn attempt, {acc, outcomes} ->
        case open_worker(id, p, attempt) do
          {:ok, port, info} ->
            acc = %{acc | ports: Map.put(acc.ports, port, info), ids: Map.put(acc.ids, attempt["id"], port)}
            {acc, [:ok | outcomes]}
          {:error, reason} ->
            Part3Store.fail_attempt(id, attempt["id"], reason)
            {acc, [{:error, reason} | outcomes]}
        end
      end)
      result = if Enum.all?(outcomes, &(&1 == :ok)), do: :ok, else: {:error, :runner_launch_failed}
      {:reply, result, next}
    end
  end

  def handle_call({:cancel, id, attempt_id}, _from, state) do
    case Map.fetch(state.ids, attempt_id) do
      {:ok, port} ->
        info = state.ports[port]
        if info.review_id == id do
          # Closing the port closes the worker's stdin; the Python supervisor
          # terminates the full child process group, not just the Mix launcher.
          Port.close(port)
          result = Part3Store.fail_attempt(id, attempt_id, :cancelled)
          {:reply, result, drop(state, port)}
        else
          {:reply, {:error, :unknown_attempt}, state}
        end
      :error -> {:reply, {:error, :unknown_attempt}, state}
    end
  end

  @impl true
  def handle_info({port, {:data, chunk}}, state) when is_port(port) do
    # Worker stdout is diagnostic only, never a trusted completion protocol.
    next = case Map.fetch(state.ports, port) do
      {:ok, info} ->
        line = (info.stdout <> chunk) |> String.slice(0, 1200)
        put_in(state, [:ports, port, :stdout], line)
      :error -> state
    end
    {:noreply, next}
  end

  def handle_info({port, {:exit_status, code}}, state) when is_port(port) do
    case Map.fetch(state.ports, port) do
      {:ok, info} ->
        finish(info, code)
        {:noreply, drop(state, port)}
      :error -> {:noreply, state}
    end
  end

  # A normal linked-Port EXIT can precede its exit_status message. Let the
  # status message own completion and provenance, instead of losing success.
  def handle_info({:EXIT, port, :normal}, state) when is_port(port), do: {:noreply, state}

  def handle_info({:EXIT, port, _reason}, state) when is_port(port) do
    case Map.fetch(state.ports, port) do
      {:ok, info} ->
        Part3Store.fail_attempt(info.review_id, info.attempt["id"], :port_closed)
        {:noreply, drop(state, port)}
      :error -> {:noreply, state}
    end
  end

  def handle_info(_, state), do: {:noreply, state}

  defp drop(state, port) do
    info = state.ports[port]
    %{state | ports: Map.delete(state.ports, port), ids: Map.delete(state.ids, info.attempt["id"])}
  end

  defp finish(info, 0) do
    outcome =
      if info.attempt["kind"] == "replay" do
        with {:ok, bytes} <- File.read(info.result),
             true <- byte_size(bytes) <= @max_input,
             {:ok, result} <- Jason.decode(bytes) do
          Part3Store.complete_replay(info.review_id, info.attempt["id"], result)
        else
          _ -> {:error, :result_invalid_or_missing}
        end
      else
        Part3Store.complete_verification(info.review_id, info.attempt["id"], info.report)
      end
    if not match?({:ok, _}, outcome),
      do: Part3Store.fail_attempt(info.review_id, info.attempt["id"], :invalid_completion)
  end

  defp finish(info, code) do
    reason = case code do
      124 -> :timeout
      130 -> :cancelled
      _ -> :worker_failed
    end
    Part3Store.fail_attempt(info.review_id, info.attempt["id"], reason)
  end

  defp open_worker(review_id, p, attempt) do
    with {:ok, _snapshot} <- Part3Snapshots.load(attempt["snapshot_id"]),
         {:ok, _doc, :ok} <- Part3Store.get(review_id),
         {:ok, _updated} <- Part3Store.running(review_id, attempt["id"]),
         {:ok, python} <- executable("python3"),
         {:ok, request, result, report} <- prepare_files(p, attempt) do
      script = Path.join(Config.root(), "apps/review_web/scripts/part3_worker.py")
      args = [script, "--kind", if(attempt["kind"] == "replay", do: "pointwise", else: "formal"),
        "--snapshot-root", Part3Snapshots.root(attempt["snapshot_id"]),
        "--request", request, "--result", result, "--timeout",
        if(attempt["kind"] == "replay", do: "120", else: "7200")]
      try do
        port = Port.open({:spawn_executable, python}, [:binary, :exit_status, :use_stdio, :stderr_to_stdout, args: args])
        {:ok, port, %{review_id: review_id, attempt: attempt, result: result, report: report, stdout: ""}}
      rescue
        _ -> {:error, :worker_spawn_failed}
      end
    else
      _ -> {:error, :runner_preflight_failed}
    end
  end

  defp prepare_files(p, attempt) do
    base = Path.join(Config.root(), @job_dir)
    request = Path.join(base, attempt["id"] <> ".json")
    relative = "tmp/verification/part3-" <> attempt["id"] <> "/checked.json"
    result = if attempt["kind"] == "replay", do: Path.join(base, attempt["id"] <> ".result.json"),
      else: Path.join(Part3Snapshots.root(attempt["snapshot_id"]), relative)
    body = if attempt["kind"] == "replay" do
      %{"schema_version" => 1, "request_id" => attempt["id"], "snapshot_id" => attempt["snapshot_id"],
        "context_digest" => p["context_digest"], "input_digest" => attempt["input_digest"], "witness" => attempt["witness"]}
    else
      %{"schema_version" => 1, "snapshot_id" => attempt["snapshot_id"], "context_digest" => p["context_digest"],
        "scope" => "full_required_catalog"}
    end
    with :ok <- File.mkdir_p(base),
         :ok <- File.mkdir_p(Path.dirname(result)),
         :ok <- File.write(request, Canonical.json(body) <> "\n", [:exclusive]) do
      {:ok, request, result, relative}
    else
      _ -> {:error, :runner_io_unavailable}
    end
  end

  defp executable(name) do
    case System.find_executable(name) do
      nil -> {:error, :python_unavailable}
      path -> {:ok, path}
    end
  end
end
