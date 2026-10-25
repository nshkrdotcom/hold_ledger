defmodule HoldLedger.Server do
  @moduledoc """
  The single in-memory ledger owner for one injected journal pathname.

  Recovery verifies the *entire* hash-chained journal, checks its persisted
  capacity configuration, folds events with the pure `Ledger.run/2` **without
  executing old effects**, then appends/syncs a fresh `:restart` before serving
  calls. A pre-restart `:sent` therefore becomes post-restart `:unknown`.

  Every submitted event, including stale/malformed callbacks, is appended and
  synced before `Ledger.step/2` or scheduling effects. Any append/sync error
  leaves the current in-memory state unchanged, schedules nothing, and poisons
  the writer fail-closed. A sync error may leave an unacknowledged record on
  disk, so reopening must reconcile the actual persisted history.

  `reconcile/2` queries a processor. Approved/declined lookup results are
  journaled as normal processor results. A reliable `:not_found` may lead to
  an *explicit* `retry_after_lookup/2` with the same identity; an unavailable
  lookup never releases a hold or triggers an automatic retry. A local void
  is only a durable *intent*, not evidence that an external void succeeded.
  """
  use GenServer

  alias HoldLedger.{EffectExecutor, Journal, Ledger, Spec}

  @doc "Start an injected server; `:path` and `:caps` are mandatory."
  def start_link(opts) do
    {name, init_opts} = Keyword.pop(opts, :name)
    GenServer.start_link(__MODULE__, init_opts, if(name, do: [name: name], else: []))
  end

  @doc "Apply one event; returns `{:ok, result}` only after a successful sync."
  def submit(server, event), do: GenServer.call(server, {:submit, event}, :infinity)

  def state(server), do: GenServer.call(server, :state)
  def status(server), do: GenServer.call(server, :status)
  def recovery(server), do: GenServer.call(server, :recovery)

  @doc "Wait for scheduled processor tasks and all of their journaled outcomes."
  def await_idle(server, timeout \\ 5_000), do: GenServer.call(server, :await_idle, timeout)

  @doc "Inject a deterministic one-shot journal failure/crash in test-only mode."
  def inject_fault(server, fault)
      when fault in [:append, :sync, :disk_full, :crash_after_sync] do
    GenServer.call(server, {:inject_fault, fault})
  end

  @doc "A synthetic processor callback enters precisely the regular input path."
  def processor_callback(server, key, outcome),
    do: GenServer.call(server, {:submit, {:processor_result, key, outcome}})

  @doc "Lookup without retrying or releasing any uncertain hold."
  def reconcile(server, key), do: GenServer.call(server, {:reconcile, key}, :infinity)

  @doc "Lookup first, and retry only if the processor reliably reports not found."
  def retry_after_lookup(server, key),
    do: GenServer.call(server, {:retry_after_lookup, key}, :infinity)

  @impl true
  def init(opts) do
    path = Keyword.fetch!(opts, :path)
    {amount_limit, hold_limit} = caps = Keyword.fetch!(opts, :caps)
    journal_name = Keyword.get(opts, :journal_name, :hold_ledger_journal)

    # Validate limits before opening a persistent log.
    _initial = Ledger.init(amount_limit, hold_limit)

    case Journal.open(name: journal_name, path: path) do
      {:ok, journal} ->
        initialize_journal(journal, caps, opts)

      {:error, reason} ->
        {:stop, {:journal_open_failed, reason}}
    end
  end

  defp initialize_journal(journal, caps, opts) do
    case boot(journal, caps, Keyword.get(opts, :chunk_size, 128)) do
      {:ok, journal, before, after_restart, event_count, void_receipts} ->
        install_recovered(journal, before, after_restart, event_count, void_receipts, opts)

      {:error, reason} ->
        Journal.close(journal)
        {:stop, {:recovery_failed, reason}}
    end
  end

  defp install_recovered(journal, before, after_restart, event_count, void_receipts, opts) do
    if not Spec.valid?(before) or not Spec.valid?(after_restart) do
      Journal.close(journal)
      {:stop, {:recovery_failed, :invalid_replayed_ledger}}
    else
      {:ok,
       %{
         journal: journal,
         ledger: after_restart,
         pre_restart: before,
         boot_post_restart: after_restart,
         replayed_event_count: event_count,
         processor: Keyword.get(opts, :processor),
         effect_supervisor: Keyword.get(opts, :effect_supervisor, HoldLedger.EffectSupervisor),
         monitor: Keyword.get(opts, :monitor, true),
         allow_faults: Keyword.get(opts, :allow_faults, false),
         faults: [],
         poisoned: nil,
         pending: MapSet.new(),
         waiters: [],
         void_receipts: void_receipts
       }}
    end
  end

  defp boot(journal, caps, chunk_size) do
    with {:ok, events, journal} <- Journal.replay(journal, chunk_size: chunk_size),
         {:ok, journal} <- check_caps(journal, events, caps),
         before = Ledger.run(Ledger.init(elem(caps, 0), elem(caps, 1)), events),
         {:ok, journal} <- Journal.append_sync(journal, :restart) do
      {after_restart, :restarted, []} = Ledger.step(before, :restart)

      receipts =
        Enum.filter(events, fn
          {:processor_void_result, _, _} -> true
          _ -> false
        end)

      {:ok, journal, before, after_restart, length(events), receipts}
    end
  end

  defp check_caps(journal, [], {amount_limit, hold_limit}) do
    Journal.append_sync(journal, {:hold_ledger_caps_v1, amount_limit, hold_limit})
  end

  defp check_caps(journal, [{:hold_ledger_caps_v1, amount, holds} | _], {amount, holds}),
    do: {:ok, journal}

  defp check_caps(_journal, [{:hold_ledger_caps_v1, old_amount, old_holds} | _], caps),
    do: {:error, {:caps_mismatch, {old_amount, old_holds}, caps}}

  defp check_caps(_journal, [_ | _], _caps), do: {:error, :missing_capacity_header}

  @impl true
  def handle_call(:state, _from, data), do: {:reply, data.ledger, data}

  def handle_call(:status, _from, data) do
    {:reply,
     %{
       ledger: data.ledger,
       poisoned: data.poisoned,
       pending_effects: MapSet.size(data.pending),
       void_receipts: data.void_receipts
     }, data}
  end

  def handle_call(:recovery, _from, data) do
    {:reply,
     %{
       pre_restart: data.pre_restart,
       post_restart: data.boot_post_restart,
       replayed_event_count: data.replayed_event_count
     }, data}
  end

  def handle_call(:await_idle, from, data) do
    if MapSet.size(data.pending) == 0 do
      {:reply, :ok, data}
    else
      {:noreply, %{data | waiters: [from | data.waiters]}}
    end
  end

  def handle_call({:inject_fault, fault}, _from, data) do
    if data.allow_faults do
      {:reply, :ok, %{data | faults: data.faults ++ [fault]}}
    else
      {:reply, {:error, :fault_injection_disabled}, data}
    end
  end

  def handle_call({:submit, event}, _from, data) do
    case journal_and_apply(data, event) do
      {:ok, result, next} -> {:reply, {:ok, result}, next}
      {:error, reason, next} -> {:reply, {:error, reason}, next}
    end
  end

  def handle_call({:reconcile, key}, _from, data) do
    {reply, data} = do_reconcile(data, key, false)
    {:reply, reply, data}
  end

  def handle_call({:retry_after_lookup, key}, _from, data) do
    {reply, data} = do_reconcile(data, key, true)
    {:reply, reply, data}
  end

  defp do_reconcile(%{poisoned: reason} = data, _key, _retry?) when not is_nil(reason),
    do: {{:error, {:journal_poisoned, reason}}, data}

  defp do_reconcile(%{processor: nil} = data, _key, _retry?),
    do: {{:error, :processor_unavailable}, data}

  defp do_reconcile(data, key, retry?) do
    case Ledger.find(elem(data.ledger, 4), key) do
      {:ok, {_, _, :unknown}} ->
        # A lookup is a *new live* external query, never an effect of replay.
        # Journal its intent before contacting the processor, then journal its
        # outcome through the exact same input path.
        case journal_and_apply(data, {:processor_lookup_requested, key}) do
          {:ok, _, next} -> perform_lookup(next, key, retry?)
          {:error, reason, next} -> {{:error, reason}, next}
        end

      _ ->
        {{:error, :not_unknown}, data}
    end
  end

  defp perform_lookup(data, key, retry?) do
    {module, target} = data.processor

    handle_lookup(module.lookup(target, key), data, key, retry?)
  end

  defp handle_lookup({:ok, outcome}, data, key, _retry?) when outcome in [:approved, :declined] do
    lookup_reply(data, {:processor_result, key, outcome}, :reconciled)
  end

  defp handle_lookup(:not_found, data, key, retry?) do
    case journal_and_apply(data, {:processor_lookup_not_found, key}) do
      {:ok, _, next} when retry? -> retry_lookup(next, key)
      {:ok, _, next} -> {{:ok, :not_found}, next}
      {:error, reason, next} -> {{:error, reason}, next}
    end
  end

  defp handle_lookup({:error, reason}, data, key, _retry?) do
    lookup_reply(
      data,
      {:processor_lookup_unavailable, key},
      {:error, {:lookup_unavailable, reason}}
    )
  end

  defp handle_lookup(other, data, key, _retry?) do
    lookup_reply(
      data,
      {:processor_lookup_unexpected, key, other},
      {:error, {:unexpected_lookup, other}}
    )
  end

  defp lookup_reply(data, event, reply) do
    case journal_and_apply(data, event) do
      {:ok, result, next} when reply == :reconciled -> {{:ok, {:reconciled, result}}, next}
      {:ok, _, next} -> {reply, next}
      {:error, reason, next} -> {{:error, reason}, next}
    end
  end

  defp retry_lookup(data, key) do
    case journal_and_apply(data, {:retry, key}) do
      {:ok, result, next} -> {{:ok, result}, next}
      {:error, reason, next} -> {{:error, reason}, next}
    end
  end

  # One path for client input, processor callbacks and internal effect outcomes.
  defp journal_and_apply(%{poisoned: reason} = data, _event) when not is_nil(reason) do
    {:error, {:journal_poisoned, reason}, data}
  end

  defp journal_and_apply(data, event) do
    {fault, data} = pop_fault(data)
    journal_fault = if(fault in [:append, :sync, :disk_full], do: fault, else: nil)

    case Journal.append_sync(data.journal, event, fault: journal_fault) do
      {:ok, journal} ->
        if fault == :crash_after_sync, do: exit(:injected_after_durable_append)

        {ledger, result, effects} = Ledger.step(data.ledger, event)

        if data.monitor and not Spec.valid?(ledger) do
          exit({:invalid_ledger_after_persisted_event, event})
        end

        receipts =
          case event do
            {:processor_void_result, _, _} -> data.void_receipts ++ [event]
            _ -> data.void_receipts
          end

        next = %{data | journal: journal, ledger: ledger, void_receipts: receipts}
        {:ok, result, schedule_effects(next, effects)}

      {:error, reason} ->
        # A disk_log write may be partially present even if sync fails: fail
        # closed rather than append to an ambiguous predecessor cursor.
        {:error, reason, %{data | poisoned: reason}}
    end
  end

  defp pop_fault(%{faults: [head | rest]} = data), do: {head, %{data | faults: rest}}
  defp pop_fault(data), do: {nil, data}

  defp schedule_effects(%{processor: nil} = data, _effects), do: data

  defp schedule_effects(data, effects) do
    Enum.reduce(effects, data, &schedule_effect/2)
  end

  defp schedule_effect(effect, acc) do
    case EffectExecutor.dispatch(acc.effect_supervisor, self(), acc.processor, effect) do
      {:ok, ref} ->
        %{acc | pending: MapSet.put(acc.pending, ref)}

      {:error, reason} ->
        # Scheduling failed *after* committing the intent. Record an uncertain
        # authorization (or failed void result) through the journal path.
        ref = make_ref()

        events =
          case effect do
            {:authorize, key, _} -> [{:timeout, key}]
            {:void, key} -> [{:processor_void_result, key, {:error, {:task_start, reason}}}]
          end

        send(self(), {:hold_ledger_effects, ref, events})
        %{acc | pending: MapSet.put(acc.pending, ref)}
    end
  end

  @impl true
  def handle_info({:hold_ledger_effects, ref, events}, data) do
    if MapSet.member?(data.pending, ref) do
      data = %{data | pending: MapSet.delete(data.pending, ref)}

      next =
        Enum.reduce(events, data, &apply_effect_event/2)

      {:noreply, wake_waiters(next)}
    else
      {:noreply, data}
    end
  end

  def handle_info({:processor_callback, key, outcome}, data) do
    next =
      case journal_and_apply(data, {:processor_result, key, outcome}) do
        {:ok, _, committed} -> committed
        {:error, _, failed} -> failed
      end

    {:noreply, wake_waiters(next)}
  end

  def handle_info(_unexpected, data), do: {:noreply, data}

  defp apply_effect_event(event, data) do
    case journal_and_apply(data, event) do
      {:ok, _, committed} -> committed
      {:error, _, failed} -> failed
    end
  end

  defp wake_waiters(data) do
    if MapSet.size(data.pending) == 0 do
      Enum.each(data.waiters, &GenServer.reply(&1, :ok))
      %{data | waiters: []}
    else
      data
    end
  end

  @impl true
  def terminate(_reason, data) do
    Journal.close(data.journal)
    :ok
  end
end
