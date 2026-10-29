defmodule HoldLedgerReview.Questions do
  @moduledoc "Durable local question history and supervised, consented completion lifecycle."
  use GenServer
  alias HoldLedgerReview.{AI, Canonical, Config, QuestionContext, Trace}

  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, if(name, do: [name: name], else: []))
  end

  def prepare(packet, owner \\ self(), server \\ __MODULE__),
    do: GenServer.call(server, {:prepare, packet, owner})

  def ask(id, digest, consent, server \\ __MODULE__),
    do: GenServer.call(server, {:ask, id, digest, consent}, 15_000)

  def cancel(id, server \\ __MODULE__), do: GenServer.call(server, {:cancel, id})
  def get(id, server \\ __MODULE__), do: GenServer.call(server, {:get, id})

  def list(query \\ "", server \\ __MODULE__, conversation \\ nil, offset \\ 0),
    do: GenServer.call(server, {:list, query, conversation, offset})

  def clear(server \\ __MODULE__), do: GenServer.call(server, :clear)
  def health(server \\ __MODULE__), do: GenServer.call(server, :health)

  @impl true
  def init(opts) do
    dir =
      Keyword.get(
        opts,
        :dir,
        Application.get_env(
          :hold_ledger_review_web,
          :question_store_dir,
          Path.join(Config.root(), "tmp/review_studio/questions")
        )
      )

    state = %{
      dir: dir,
      rows: %{},
      jobs: %{},
      owners: %{},
      error: nil,
      runner:
        Keyword.get(
          opts,
          :runner,
          Application.get_env(:hold_ledger_review_web, :question_runner, &AI.answer(&1, true))
        ),
      timeout: Keyword.get(opts, :timeout, 115_000)
    }

    case recover(dir) do
      {:ok, rows} -> {:ok, recover_running(%{state | rows: rows})}
      {:error, error} -> {:ok, %{state | error: error}}
    end
  end

  @impl true
  def handle_call(:health, _, state),
    do: {:reply, if(state.error, do: {:error, state.error}, else: :ok), state}

  def handle_call({:get, id}, _, state), do: {:reply, state.rows[id], state}

  def handle_call({:list, query, conversation, offset}, _, state) do
    matches =
      state.rows
      |> Map.values()
      |> Enum.filter(
        &(matches?(&1, query) and
            (is_nil(conversation) or &1["packet"]["conversation"] == conversation))
      )
      |> Enum.sort_by(& &1["created_at"], :desc)
      |> Enum.drop(max(0, offset))
      |> Enum.take(50)

    {:reply, matches, state}
  end

  def handle_call({:prepare, packet, owner}, _, state) do
    with nil <- state.error,
         :ok <- QuestionContext.freshness(packet),
         true <- Regex.match?(~r/^trace-[A-Za-z0-9_-]+$/, packet["conversation"]) do
      row = %{
        "id" => Trace.token(),
        "packet" => packet,
        "status" => "prepared",
        "sequence" => 0,
        "created_at" => now(),
        "answer" => nil
      }

      case persist(state, row) do
        :ok ->
          {:reply, {:ok, row},
           %{put_row(state, row) | owners: Map.put(state.owners, row["id"], owner)}}

        _ ->
          {:reply, {:error, :question_log_unavailable}, state}
      end
    else
      _ -> {:reply, {:error, :question_context_or_log_unavailable}, state}
    end
  end

  def handle_call({:ask, _, _, false}, _, state), do: {:reply, {:error, :consent_required}, state}

  def handle_call({:ask, id, digest, true}, _, state) do
    row = state.rows[id]

    with nil <- state.error,
         true <- is_map(row),
         "prepared" <- row["status"],
         true <- row["packet"]["digest"] == digest,
         false <-
           Enum.any?(state.rows, fn {_, other} ->
             other["status"] == "running" and
               other["packet"]["conversation"] == row["packet"]["conversation"]
           end),
         :ok <- QuestionContext.freshness(row["packet"]),
         running =
           Map.merge(row, %{
             "status" => "running",
             "sequence" => 1,
             "sent_at" => now(),
             "consent" => %{
               "actor" => row["packet"]["actor"],
               "packet_digest" => digest,
               "at" => now()
             }
           }),
         :ok <- persist(state, running) do
      runner = state.runner

      task =
        Task.Supervisor.async_nolink(HoldLedgerReview.AITaskSupervisor, fn ->
          runner.(row["packet"])
        end)

      timer = Process.send_after(self(), {:deadline, task.ref}, state.timeout)
      job = %{id: id, task: task, timer: timer}
      {:reply, :ok, %{put_row(state, running) | jobs: Map.put(state.jobs, task.ref, job)}}
    else
      "running" -> {:reply, {:error, :already_dispatched}, state}
      "succeeded" -> {:reply, {:error, :already_dispatched}, state}
      _ -> {:reply, {:error, :request_unavailable_or_already_dispatched}, state}
    end
  end

  def handle_call({:ask, _, _, _}, _, state), do: {:reply, {:error, :consent_required}, state}

  def handle_call({:cancel, id}, _, state) do
    case Enum.find(state.jobs, fn {_, job} -> job.id == id end) do
      {ref, job} ->
        Task.shutdown(job.task, :brutal_kill)

        {:reply, :ok,
         finish(
           state,
           ref,
           "cancelled",
           nil,
           "Remote cancellation is not confirmed; no automatic retry."
         )}

      _ ->
        {:reply, {:error, :not_running}, state}
    end
  end

  def handle_call(:clear, _, state) do
    if map_size(state.jobs) == 0 do
      case File.rm_rf(state.dir) do
        {:ok, _} -> {:reply, :ok, %{state | rows: %{}, owners: %{}, error: nil}}
        _ -> {:reply, {:error, :question_log_unavailable}, state}
      end
    else
      {:reply, {:error, :questions_running}, state}
    end
  end

  @impl true
  def handle_info({ref, result}, state) when is_reference(ref) do
    if state.jobs[ref] do
      Process.demonitor(ref, [:flush])
      row = state.rows[state.jobs[ref].id]

      {checked, state} = check_completion(result, row, state)

      case checked do
        {:ok, answer} ->
          {:noreply, finish(state, ref, "succeeded", answer, nil)}

        _ ->
          {:noreply,
           finish(rejected_response(state, ref, result), ref, "failed", nil, error_text(result))}
      end
    else
      {:noreply, state}
    end
  end

  def handle_info({:DOWN, ref, :process, _, _}, state),
    do: {:noreply, finish(state, ref, "failed", nil, "Worker stopped before answering.")}

  def handle_info({:deadline, ref}, state) do
    if job = state.jobs[ref], do: Task.shutdown(job.task, :brutal_kill)

    {:noreply,
     finish(state, ref, "timed_out", nil, "The answer timed out. Retry only by sending again.")}
  end

  defp check_completion({:ok, answer, metadata}, row, state) when is_map(metadata) do
    {QuestionContext.validate_answer(answer, row["packet"]),
     put_row(state, Map.put(row, "response_metadata", metadata))}
  end

  defp check_completion({:ok, answer}, row, state),
    do: {QuestionContext.validate_answer(answer, row["packet"]), state}

  defp check_completion(_, _, state), do: {{:error, :provider_failed}, state}

  defp rejected_response(state, ref, {:error, %{} = response}) do
    id = state.jobs[ref].id
    put_row(state, Map.put(state.rows[id], "rejected_response", response))
  end

  defp rejected_response(state, _, _), do: state

  defp finish(state, ref, status, answer, error) do
    case Map.pop(state.jobs, ref) do
      {nil, _} ->
        state

      {job, jobs} ->
        Process.cancel_timer(job.timer)

        row =
          Map.merge(state.rows[job.id], %{
            "status" => status,
            "sequence" => 2,
            "answer" => answer,
            "error" => error,
            "finished_at" => now()
          })

        row =
          if persist(state, row) == :ok, do: row, else: Map.put(row, "persistence_error", true)

        if owner = state.owners[job.id], do: Kernel.send(owner, {:question_ready, job.id})

        Phoenix.PubSub.broadcast(
          HoldLedgerReview.PubSub,
          "questions:" <> row["packet"]["conversation"],
          {:question_ready, job.id}
        )

        %{put_row(state, row) | jobs: jobs}
    end
  end

  defp put_row(state, row), do: %{state | rows: Map.put(state.rows, row["id"], row)}

  defp matches?(row, query),
    do:
      String.contains?(
        String.downcase(row["packet"]["question"] <> " " <> Jason.encode!(row["answer"])),
        String.downcase(String.slice(query, 0, 256))
      )

  defp error_text({:error, reason}) when is_atom(reason), do: Atom.to_string(reason)
  defp error_text(_), do: "Provider failed or returned an invalid answer."
  defp now, do: DateTime.to_iso8601(DateTime.utc_now())

  defp persist(state, row) do
    dir = Path.join(state.dir, row["packet"]["conversation"])
    path = Path.join(dir, "events.jsonl")

    with :ok <- File.mkdir_p(dir),
         :ok <- File.chmod(state.dir, 0o700),
         :ok <- File.chmod(dir, 0o700),
         {:ok, file} <- File.open(path, [:append, :binary]) do
      try do
        with :ok <- File.chmod(path, 0o600),
             :ok <-
               IO.binwrite(
                 file,
                 Canonical.json(%{
                   "schema_version" => 1,
                   "event_id" => Trace.token(),
                   "at" => now(),
                   "request_sequence" => row["sequence"],
                   "row" => row
                 }) <> "\n"
               ),
             do: :file.sync(file)
      after
        File.close(file)
      end
    end
  rescue
    _ -> {:error, :question_log_unavailable}
  end

  defp recover_running(state), do: Enum.reduce(state.rows, state, &recover_row/2)

  defp recover_row({_id, %{"status" => "running"} = row}, state) do
    interrupted =
      Map.merge(row, %{
        "status" => "interrupted",
        "sequence" => 2,
        "finished_at" => now(),
        "error" => "Application restarted; no automatic resend."
      })

    if persist(state, interrupted) == :ok,
      do: put_row(state, interrupted),
      else: %{put_row(state, interrupted) | error: :question_log_unavailable}
  end

  defp recover_row(_, state), do: state

  defp recover(dir) do
    Path.wildcard(Path.join(dir, "*/events.jsonl"))
    |> Enum.reduce_while({:ok, %{}}, fn path, {:ok, rows} ->
      case recover_file(path, rows) do
        {:ok, recovered} -> {:cont, {:ok, recovered}}
        _ -> {:halt, {:error, :corrupt_question_log}}
      end
    end)
  end

  defp recover_file(path, rows) do
    with {:ok, bytes} <- File.read(path),
         true <- String.valid?(bytes) do
      lines = String.split(bytes, "\n")
      # A torn tail is preserved separately before valid complete lines are recovered.
      tail = List.last(lines)
      complete = Enum.drop(lines, -1)

      with :ok <- preserve_tail(path, bytes, tail), do: decode_lines(complete, rows)
    else
      _ -> {:error, :corrupt_question_log}
    end
  end

  defp preserve_tail(_, _, ""), do: :ok

  defp preserve_tail(path, bytes, tail) do
    backup = path <> ".torn-" <> Trace.token()

    with :ok <- File.write(backup, tail),
         :ok <- File.chmod(backup, 0o600),
         do: File.write(path, binary_part(bytes, 0, byte_size(bytes) - byte_size(tail)))
  end

  defp decode_lines(lines, rows) do
    Enum.reduce_while(lines, {:ok, rows}, fn line, {:ok, acc} ->
      case Jason.decode(line) do
        {:ok, %{"schema_version" => 1, "row" => %{"id" => id, "packet" => packet} = row}}
        when is_binary(id) and is_map(packet) ->
          {:cont, {:ok, Map.put(acc, id, row)}}

        _ ->
          {:halt, {:error, :corrupt_question_log}}
      end
    end)
  end
end
