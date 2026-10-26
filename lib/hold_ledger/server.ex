defmodule HoldLedger.Server do
  @moduledoc """
  Single-owner, sync-before-apply ledger runtime.

  External work uses monitored tasks with deadlines. Durable void obligations
  redrive with the same key; authorization effects are never replayed. Lookup
  runs outside the mailbox and rechecks eligibility on completion. Internal
  event tags are rejected with bounded audit markers. Processor callbacks remain
  trusted integration inputs, not authenticated evidence.
  """
  use GenServer, restart: :transient
  alias HoldLedger.{Attempts, Composite, EffectExecutor, Event, Journal, Ledger, Outbox, Spec}

  @defaults [
    authorize_timeout: 5_000,
    void_timeout: 5_000,
    lookup_timeout: 5_000,
    max_attempts: 32,
    void_retry_base: 1_000,
    void_retry_max: 60_000,
    void_max_attempts: 5
  ]

  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)
    GenServer.start_link(__MODULE__, opts, if(name, do: [name: name], else: []))
  end

  def submit(server, event), do: GenServer.call(server, {:submit, event}, :infinity)
  def state(server), do: GenServer.call(server, :state)
  def status(server), do: GenServer.call(server, :status)
  def recovery(server), do: GenServer.call(server, :recovery)
  def await_idle(server, timeout \\ 5_000), do: GenServer.call(server, :await_idle, timeout)
  def reconcile(server, key), do: GenServer.call(server, {:lookup, key, false}, :infinity)
  def retry_after_lookup(server, key), do: GenServer.call(server, {:lookup, key, true}, :infinity)

  def processor_callback(server, key, outcome),
    do: submit(server, {:processor_result, key, outcome})

  @doc "Bounded inspection of unknown holds, void obligations, receipts or conflicts."
  def inspect_work(server, kind, offset \\ 0, limit \\ 100),
    do: GenServer.call(server, {:inspect_work, kind, offset, limit})

  @doc "Explicitly restart the bounded attempt budget for an unresolved void."
  def redrive_void(server, key), do: GenServer.call(server, {:redrive_void, key})

  def inject_fault(server, fault) when fault in [:append, :sync, :disk_full, :crash_after_sync],
    do: GenServer.call(server, {:inject_fault, fault})

  @impl true
  def init(opts) do
    config = Map.new(Keyword.take(Keyword.merge(@defaults, opts), Keyword.keys(@defaults)))

    with true <- Enum.all?(config, fn {_, n} -> is_integer(n) and n > 0 end),
         :ok <- HoldLedger.Processor.validate(Keyword.get(opts, :processor)) do
      initialize(opts, config)
    else
      false -> {:stop, :invalid_runtime_options}
      {:error, reason} -> {:stop, reason}
    end
  end

  defp initialize(opts, config) do
    {amount, holds} = caps = Keyword.fetch!(opts, :caps)
    initial = Ledger.init(amount, holds)

    case Journal.open(path: Keyword.fetch!(opts, :path)) do
      {:ok, journal} -> boot(journal, initial, caps, config, opts)
      {:error, reason} -> {:stop, {:journal_open_failed, reason}}
    end
  end

  defp boot(journal, initial, caps, config, opts) do
    seed = %{ledger: initial, outbox: [], receipts: [], conflicts: [], count: 0, caps: nil}

    case replay(journal, seed) do
      {:ok, recovered, journal} ->
        install(recovered, journal, caps, config, opts)

      {:error, :invalid_runtime_history} ->
        Journal.close(journal)
        {:stop, {:shutdown, {:quarantined, :invalid_runtime_history}}}

      {:error, reason} ->
        Journal.close(journal)
        {:stop, {:recovery_failed, reason}}
    end
  end

  defp replay(journal, seed) do
    Journal.fold(journal, seed, &replay_event/2)
  rescue
    _ -> {:error, :invalid_runtime_history}
  end

  defp replay_event(event, acc) do
    case event do
      {tag, key} when tag in [:void_attempt, :void_retry_enabled] ->
        if Outbox.fetch(acc.outbox, key) == :not_found, do: raise("orphan attempt event")

      {:void_outcome, key, _} ->
        if Outbox.fetch(acc.outbox, key) == :not_found, do: raise("orphan outcome event")

      _ ->
        :ok
    end

    caps = if acc.count == 0, do: event, else: acc.caps
    {{ledger, outbox}, _, _} = Composite.step({acc.ledger, acc.outbox}, event)
    if not Spec.composite_valid?({ledger, outbox}), do: raise("invalid composite prefix")

    %{
      acc
      | ledger: ledger,
        outbox: outbox,
        caps: caps,
        count: acc.count + 1,
        receipts: receipt(event, acc.receipts),
        conflicts: conflict(event, acc.conflicts)
    }
  end

  defp install(recovered, journal, {amount, holds} = caps, config, opts) do
    cond do
      recovered.count > 0 and recovered.caps != {:hold_ledger_caps, amount, holds} ->
        Journal.close(journal)

        old_caps =
          case recovered.caps do
            {:hold_ledger_caps, a, h} -> {a, h}
            _ -> :missing
          end

        {:stop, {:recovery_failed, {:caps_mismatch, old_caps, caps}}}

      not Spec.valid?(recovered.ledger) ->
        Journal.close(journal)
        {:stop, {:shutdown, {:quarantined, :invalid_replayed_ledger}}}

      true ->
        install_valid(recovered, journal, caps, config, opts)
    end
  end

  defp install_valid(recovered, journal, {amount, holds}, config, opts) do
    result =
      if recovered.count == 0,
        do: Journal.append_sync(journal, {:hold_ledger_caps, amount, holds}),
        else: {:ok, journal}

    with {:ok, journal} <- result,
         {:ok, journal} <- Journal.append_sync(journal, :restart),
         {{ledger, outbox}, :restarted, []} <-
           Composite.step({recovered.ledger, recovered.outbox}, :restart),
         true <- Spec.composite_valid?({ledger, outbox}) and Spec.no_sent?(elem(ledger, 4)) do
      send(self(), :redrive)

      {:ok,
       %{
         journal: journal,
         ledger: ledger,
         pre_restart: recovered.ledger,
         boot_post_restart: ledger,
         replayed_event_count: recovered.count,
         outbox: outbox,
         receipts: recovered.receipts,
         conflicts: recovered.conflicts,
         processor: Keyword.get(opts, :processor),
         effect_supervisor: Keyword.get(opts, :effect_supervisor, HoldLedger.EffectSupervisor),
         monitor: Keyword.get(opts, :monitor, true),
         allow_faults: Keyword.get(opts, :allow_faults, false),
         faults: [],
         poisoned: nil,
         attempts: Attempts.init(),
         tasks: %{},
         waiters: %{},
         retries: %{},
         config: config
       }}
    else
      false ->
        Journal.close(journal)
        {:stop, {:shutdown, {:quarantined, :invalid_restart}}}

      {:error, reason} ->
        Journal.close(journal)
        {:stop, {:recovery_failed, reason}}
    end
  end

  @impl true
  def handle_call(:state, _, data), do: {:reply, data.ledger, data}

  def handle_call(:status, _, data) do
    {:reply,
     %{
       ledger: data.ledger,
       poisoned: data.poisoned,
       pending_effects: map_size(data.tasks),
       void_receipts: Enum.reverse(data.receipts),
       unresolved_voids: data.outbox |> outbox_view() |> Enum.sort() |> Enum.take(100),
       conflicts: Enum.reverse(data.conflicts)
     }, data}
  end

  def handle_call(:recovery, _, data) do
    {:reply,
     Map.take(data, [:pre_restart, :replayed_event_count])
     |> Map.put(:post_restart, data.boot_post_restart), data}
  end

  def handle_call({:inspect_work, kind, offset, limit}, _, data)
      when is_integer(offset) and offset >= 0 and is_integer(limit) and limit in 1..100 do
    items =
      case kind do
        :unknown -> Enum.filter(elem(data.ledger, 4), fn {_, _, s} -> s == :unknown end)
        :voids -> data.outbox |> outbox_view() |> Enum.sort()
        :receipts -> Enum.reverse(data.receipts)
        :conflicts -> Enum.reverse(data.conflicts)
        _ -> []
      end

    {:reply, Enum.slice(items, offset, limit), data}
  end

  def handle_call({:inspect_work, _, _, _}, _, data), do: {:reply, {:error, :invalid_page}, data}

  def handle_call(:await_idle, from, data) do
    if map_size(data.tasks) == 0 do
      {:reply, idle_reply(data), data}
    else
      ref = Process.monitor(elem(from, 0))
      {:noreply, %{data | waiters: Map.put(data.waiters, ref, from)}}
    end
  end

  def handle_call({:inject_fault, fault}, _, %{allow_faults: true} = data),
    do: {:reply, :ok, %{data | faults: data.faults ++ [fault]}}

  def handle_call({:inject_fault, _}, _, data),
    do: {:reply, {:error, :fault_injection_disabled}, data}

  def handle_call({:submit, event}, _, data) do
    {input, rejection} = Event.public(event)

    case commit(data, input) do
      {:ok, result, next} ->
        {:reply, if(rejection, do: {:error, :reserved_event}, else: {:ok, result}), next}

      {:error, reason, next} ->
        {:reply, {:error, reason}, next}
    end
  end

  def handle_call({:lookup, key, retry?}, from, data) do
    cond do
      data.poisoned != nil ->
        {:reply, idle_reply(data), data}

      data.processor == nil ->
        {:reply, {:error, :processor_unavailable}, data}

      not is_integer(key) ->
        {:reply, {:error, :not_unknown}, data}

      Ledger.find(elem(data.ledger, 4), key) |> unknown?() ->
        start_lookup(data, key, retry?, from)

      true ->
        {:reply, {:error, :not_unknown}, data}
    end
  end

  def handle_call({:redrive_void, key}, _, data) do
    case {Outbox.fetch(data.outbox, key),
          Attempts.occupied?(Attempts.entries(data.attempts), :void, key)} do
      {_, true} ->
        {:reply, {:error, :attempt_active}, data}

      {{^key, _, _}, false} ->
        case commit(data, {:void_retry_enabled, key}) do
          {:ok, _, next} -> {:reply, :ok, start_void(next, key)}
          {:error, reason, next} -> {:reply, {:error, reason}, next}
        end

      _ ->
        {:reply, {:error, :not_pending}, data}
    end
  end

  defp unknown?({:ok, {_, _, :unknown}}), do: true
  defp unknown?(_), do: false

  defp start_lookup(data, key, retry?, from) do
    if Attempts.occupied?(Attempts.entries(data.attempts), :lookup, key) do
      {:reply, {:error, :lookup_in_progress}, data}
    else
      case commit(data, {:processor_lookup_requested, key}) do
        {:ok, _, next} -> {:noreply, start_attempt(next, {:lookup, key}, {from, retry?})}
        {:error, reason, next} -> {:reply, {:error, reason}, next}
      end
    end
  end

  defp commit(%{poisoned: reason} = data, _) when reason != nil,
    do: {:error, {:journal_poisoned, reason}, data}

  defp commit(data, event) do
    {fault, faults} =
      case data.faults do
        [fault | rest] -> {fault, rest}
        [] -> {nil, []}
      end

    data = %{data | faults: faults}
    disk_fault = if fault in [:append, :sync, :disk_full], do: fault

    case Journal.append_sync(data.journal, event, fault: disk_fault) do
      {:ok, journal} ->
        if fault == :crash_after_sync, do: exit(:injected_after_durable_append)
        apply_committed(%{data | journal: journal}, event)

      {:error, reason} ->
        {attempts, []} = Attempts.step(data.attempts, :poison)
        {:error, reason, %{data | poisoned: reason, attempts: attempts}}
    end
  end

  defp apply_committed(data, event) do
    {{ledger, outbox}, result, effects} = Composite.step({data.ledger, data.outbox}, event)

    if data.monitor and not Spec.composite_valid?({ledger, outbox}),
      do: exit({:shutdown, {:quarantined, data.journal.next_seq - 1}})

    next = %{
      data
      | ledger: ledger,
        outbox: outbox,
        receipts: receipt(event, data.receipts),
        conflicts: conflict(event, data.conflicts)
    }

    next = Enum.reduce(effects, next, &schedule/2)
    record_conflict(next, data.ledger, event, result)
  end

  defp record_conflict(data, before, {:processor_result, key, outcome}, :stale) do
    case Ledger.find(elem(before, 4), key) do
      {:ok, {_, _, :authorized}} when outcome == :declined ->
        commit_conflict(data, key, :approved, outcome)

      {:ok, {_, _, :declined}} when outcome == :approved ->
        commit_conflict(data, key, :declined, outcome)

      _ ->
        {:ok, :stale, data}
    end
  end

  defp record_conflict(data, _, _, result), do: {:ok, result, data}

  defp commit_conflict(data, key, first, later) do
    case commit(data, {:processor_conflict, key, first, later}) do
      {:ok, _, next} -> {:ok, :stale, next}
      error -> error
    end
  end

  defp outbox_view(entries) do
    Enum.map(entries, fn {key, attempts, outcome} ->
      {key, %{attempts: attempts, status: :pending, outcome: outcome}}
    end)
  end

  defp receipt({:void_confirmed, _} = event, receipts), do: Enum.take([event | receipts], 100)

  defp receipt({:void_outcome, _, _} = event, receipts),
    do: Enum.take([event | receipts], 100)

  defp receipt(_, receipts), do: receipts

  defp conflict({:processor_conflict, _, _, _} = event, conflicts),
    do: Enum.take([event | conflicts], 100)

  defp conflict(_, conflicts), do: conflicts
  defp schedule({:void, key}, data), do: start_void(data, key)
  defp schedule(effect, data), do: start_attempt(data, effect, nil)

  defp start_void(%{processor: nil} = data, _), do: data
  defp start_void(%{poisoned: reason} = data, _) when reason != nil, do: data

  defp start_void(data, key) do
    case Outbox.fetch(data.outbox, key) do
      :not_found -> data
      {^key, attempts, _} -> start_pending_void(data, key, attempts)
    end
  end

  defp start_pending_void(data, key, attempts) do
    if attempts < data.config.void_max_attempts and
         not Attempts.occupied?(Attempts.entries(data.attempts), :void, key) do
      case commit(data, {:void_attempt, key}) do
        {:ok, _, next} -> start_attempt(next, {:void, key}, nil)
        {:error, _, next} -> next
      end
    else
      data
    end
  end

  defp start_attempt(%{processor: nil} = data, _, _), do: data

  defp start_attempt(data, effect, caller) do
    kind = elem(effect, 0)
    key = elem(effect, 1)

    {attempts, intents} =
      Attempts.step(data.attempts, {:start, kind, key, data.config.max_attempts})

    case intents do
      [{:spawn, id}] -> spawn_attempt(%{data | attempts: attempts}, effect, id, caller)
      [] -> failed_start(data, effect, caller)
    end
  end

  defp spawn_attempt(data, effect, id, caller) do
    timeout = Map.fetch!(data.config, timeout_key(elem(effect, 0)))

    case EffectExecutor.dispatch(data.effect_supervisor, data.processor, effect, timeout) do
      {:ok, task} ->
        timer = Process.send_after(self(), {:deadline, task.ref}, timeout)
        caller_ref = if caller, do: Process.monitor(elem(elem(caller, 0), 0))

        attempt = %{
          id: id,
          effect: effect,
          task: task,
          timer: timer,
          caller: caller,
          caller_ref: caller_ref
        }

        %{data | tasks: Map.put(data.tasks, task.ref, attempt)}

      {:error, reason} ->
        attempt = %{id: id, effect: effect, caller: caller, caller_ref: nil}

        case attempt_intent(data, :down, attempt, :persist) do
          {:ok, committing} ->
            {next, reply} = outcome(committing, attempt, {:error, reason})
            reply_caller(caller, reply)
            retire(next, id)

          :ignored ->
            data
        end
    end
  end

  defp failed_start(data, effect, caller) do
    {next, reply} = outcome(data, %{effect: effect, caller: caller}, {:error, :capacity})
    reply_caller(caller, reply)
    next
  end

  defp timeout_key(:authorize), do: :authorize_timeout
  defp timeout_key(:void), do: :void_timeout
  defp timeout_key(:lookup), do: :lookup_timeout

  @impl true
  def handle_info({ref, result}, data) when is_reference(ref),
    do: finish(data, ref, :result, result)

  def handle_info({:DOWN, ref, :process, _, _}, data) do
    if Map.has_key?(data.tasks, ref) do
      finish(data, ref, :down, {:error, :task_down})
    else
      tasks =
        Map.new(data.tasks, fn {r, a} ->
          {r, if(a.caller_ref == ref, do: %{a | caller: nil, caller_ref: nil}, else: a)}
        end)

      {:noreply, %{data | tasks: tasks, waiters: Map.delete(data.waiters, ref)}}
    end
  end

  def handle_info({:deadline, ref}, data) do
    case Map.fetch(data.tasks, ref) do
      {:ok, attempt} ->
        case attempt_intent(data, :deadline, attempt, :shutdown) do
          {:ok, stopping} ->
            finish(stopping, ref, :shutdown_result, shutdown_result(attempt.task))

          :ignored ->
            {:noreply, data}
        end

      :error ->
        {:noreply, data}
    end
  end

  def handle_info(:redrive, data) do
    next =
      Enum.reduce(
        Outbox.due(data.outbox, data.config.void_max_attempts),
        data,
        &start_void(&2, &1)
      )

    {:noreply, wake_waiters(next)}
  end

  def handle_info({:retry_void, key, token}, data) do
    if Map.get(data.retries, key) == token do
      {:noreply, start_void(%{data | retries: Map.delete(data.retries, key)}, key)}
    else
      {:noreply, data}
    end
  end

  def handle_info({:processor_callback, key, result}, data) do
    {event, _} = Event.public({:processor_result, key, result})
    {:noreply, event_commit(data, event) |> wake_waiters()}
  end

  def handle_info(_, data), do: {:noreply, data}

  defp shutdown_result(task) do
    case Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> result
      _ -> {:error, :timeout}
    end
  end

  defp finish(data, ref, event, result) do
    case Map.fetch(data.tasks, ref) do
      {:ok, attempt} ->
        case attempt_intent(data, event, attempt, :persist) do
          {:ok, committing} ->
            Process.demonitor(ref, [:flush])
            Process.cancel_timer(attempt.timer)
            if attempt.caller_ref, do: Process.demonitor(attempt.caller_ref, [:flush])
            {next, reply} = outcome(committing, attempt, result)
            reply_caller(attempt.caller, reply)
            next = %{next | tasks: Map.delete(next.tasks, ref)} |> retire(attempt.id)
            {:noreply, wake_waiters(next)}

          :ignored ->
            {:noreply, data}
        end

      :error ->
        {:noreply, data}
    end
  end

  defp attempt_intent(data, event, %{id: id, effect: effect}, tag) do
    kind = elem(effect, 0)
    key = elem(effect, 1)

    case Attempts.step(data.attempts, {event, id}) do
      {attempts, [{^tag, ^id, ^kind, ^key}]} -> {:ok, %{data | attempts: attempts}}
      {_, []} -> :ignored
    end
  end

  defp retire(%{poisoned: nil} = data, id) do
    case Attempts.step(data.attempts, {:committed, id}) do
      {attempts, [{:retire, ^id}]} -> %{data | attempts: attempts}
      {_, []} -> data
    end
  end

  defp retire(data, _), do: data

  defp outcome(data, %{effect: {:authorize, key, _}}, {:callbacks, results}) do
    {Enum.reduce(results, data, fn result, acc ->
       event_commit(acc, {:processor_result, key, result})
     end), :ok}
  end

  defp outcome(data, %{effect: {:authorize, key, _}}, _),
    do: {event_commit(data, {:timeout, key}), :ok}

  defp outcome(data, %{effect: {:void, key}}, result) do
    case result do
      {:ok, confirmation} when confirmation in [:voided, :already_voided] ->
        next = event_commit(data, {:void_confirmed, key})
        {%{next | retries: Map.delete(next.retries, key)}, :ok}

      _ ->
        next = event_commit(data, {:void_outcome, key, result})
        {schedule_retry(next, key), :ok}
    end
  end

  defp outcome(data, %{effect: {:lookup, key}, caller: caller}, result),
    do: lookup_outcome(data, key, caller, result)

  defp lookup_outcome(data, key, _, {:ok, result}) when result in [:approved, :declined] do
    case commit(data, {:processor_result, key, result}) do
      {:ok, applied, next} -> {next, {:ok, {:reconciled, applied}}}
      {:error, reason, next} -> {next, {:error, reason}}
    end
  end

  defp lookup_outcome(data, key, caller, :not_found) do
    case commit(data, {:processor_lookup_not_found, key}) do
      {:ok, _, next} -> lookup_retry(next, key, caller)
      {:error, reason, next} -> {next, {:error, reason}}
    end
  end

  defp lookup_outcome(data, key, _, {:error, reason}) do
    case commit(data, {:processor_lookup_unavailable, key}) do
      {:ok, _, next} -> {next, {:error, {:lookup_unavailable, reason}}}
      {:error, error, next} -> {next, {:error, error}}
    end
  end

  defp lookup_retry(data, key, caller) do
    retry? = caller != nil and elem(caller, 1)

    if retry? and unknown?(Ledger.find(elem(data.ledger, 4), key)) do
      case commit(data, {:retry, key}) do
        {:ok, result, next} -> {next, {:ok, result}}
        {:error, reason, next} -> {next, {:error, reason}}
      end
    else
      {data, {:ok, :not_found}}
    end
  end

  defp event_commit(data, event) do
    case commit(data, event) do
      {:ok, _, next} -> next
      {:error, _, next} -> next
    end
  end

  defp schedule_retry(%{poisoned: reason} = data, _) when reason != nil, do: data

  defp schedule_retry(data, key) do
    {^key, attempts, _} = Outbox.fetch(data.outbox, key)

    if attempts < data.config.void_max_attempts do
      token = make_ref()

      delay =
        min(
          data.config.void_retry_max,
          data.config.void_retry_base * Integer.pow(2, min(attempts, 16))
        )

      Process.send_after(self(), {:retry_void, key, token}, delay)
      %{data | retries: Map.put(data.retries, key, token)}
    else
      data
    end
  end

  defp reply_caller(nil, _), do: :ok
  defp reply_caller({from, _}, reply), do: GenServer.reply(from, reply)
  defp idle_reply(%{poisoned: nil}), do: :ok
  defp idle_reply(data), do: {:error, {:journal_poisoned, data.poisoned}}

  defp wake_waiters(data) do
    if map_size(data.tasks) == 0 do
      Enum.each(data.waiters, fn {ref, from} ->
        Process.demonitor(ref, [:flush])
        GenServer.reply(from, idle_reply(data))
      end)

      %{data | waiters: %{}}
    else
      data
    end
  end

  @impl true
  def terminate(_, data), do: Journal.close(data.journal)
end
