defmodule HoldLedgerHardeningTest do
  use ExUnit.Case, async: false
  alias HoldLedger.{ControlledProcessor, Journal, Server}

  setup do
    dir = Path.join(System.tmp_dir!(), "hl-hardening-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, path: Path.join(dir, "journal")}
  end

  defp server(path, opts \\ []) do
    {:ok, server} =
      Server.start_link(Keyword.merge([path: path, caps: {100, 10}, allow_faults: true], opts))

    Process.unlink(server)
    on_exit(fn -> if Process.alive?(server), do: GenServer.stop(server) end)
    server
  end

  defp processor(modes) do
    {:ok, processor} = ControlledProcessor.start_link(owner: self(), modes: modes)
    on_exit(fn -> if Process.alive?(processor), do: Agent.stop(processor) end)
    processor
  end

  defp authorize(server, key) do
    assert {:ok, :admitted} = Server.submit(server, {:request, key, 10})
    assert {:ok, :dispatched} = Server.submit(server, {:dispatch, key})
    assert :ok = Server.await_idle(server)
    assert_receive {:entered, :authorize, _, ^key}
  end

  defp unknown(server, key) do
    assert {:ok, :admitted} = Server.submit(server, {:request, key, 10})
    assert {:ok, :dispatched} = Server.submit(server, {:dispatch, key})
    assert :ok = Server.await_idle(server)
    assert [{^key, 10, :unknown}] = elem(Server.state(server), 4)
    assert_receive {:entered, :authorize, _, ^key}
  end

  test "killed worker becomes uncertain and frees its pending slot", %{path: path} do
    processor = processor(%{authorize: [:block]})
    server = server(path, processor: {ControlledProcessor, processor})
    assert {:ok, :admitted} = Server.submit(server, {:request, 1, 10})
    assert {:ok, :dispatched} = Server.submit(server, {:dispatch, 1})
    assert_receive {:entered, :authorize, worker, 1}
    Process.exit(worker, :kill)
    assert :ok = Server.await_idle(server)
    assert [{1, 10, :unknown}] = elem(Server.state(server), 4)
    assert Server.status(server).pending_effects == 0
    assert :sys.get_state(server).attempts |> HoldLedger.Attempts.count() == 0
  end

  test "deadline kills the worker and stale refs cannot authorize", %{path: path} do
    processor = processor(%{authorize: [:block]})
    server = server(path, processor: {ControlledProcessor, processor}, authorize_timeout: 100)
    Server.submit(server, {:request, 1, 10})
    Server.submit(server, {:dispatch, 1})
    assert_receive {:entered, :authorize, worker, 1}
    [{ref, _}] = Map.to_list(:sys.get_state(server).tasks)
    monitor = Process.monitor(worker)
    assert :ok = Server.await_idle(server)
    assert_receive {:DOWN, ^monitor, :process, ^worker, :killed}
    send(server, {ref, {:callbacks, [:approved]}})
    assert [{1, 10, :unknown}] = elem(Server.state(server), 4)
    assert {:monitors, []} = Process.info(server, :monitors)
  end

  test "a rejected lifecycle deadline cannot execute another shutdown", %{path: path} do
    processor = processor(%{authorize: [:block]})
    server = server(path, processor: {ControlledProcessor, processor}, authorize_timeout: 10_000)
    Server.submit(server, {:request, 1, 10})
    Server.submit(server, {:dispatch, 1})
    assert_receive {:entered, :authorize, worker, 1}
    on_exit(fn -> if Process.alive?(worker), do: Process.exit(worker, :kill) end)
    original = :sys.get_state(server)
    [{ref, attempt}] = Map.to_list(original.tasks)

    # Inject the interval after the model has already requested shutdown.
    :sys.replace_state(server, fn data ->
      {attempts, [{:shutdown, _, :authorize, 1}]} =
        HoldLedger.Attempts.step(data.attempts, {:deadline, attempt.id})

      %{data | attempts: attempts}
    end)

    send(server, {:deadline, ref})
    assert :sys.get_state(server).tasks == original.tasks
    assert Process.alive?(worker)
    assert [{1, 10, :sent}] = elem(Server.state(server), 4)

    :sys.replace_state(server, &%{&1 | attempts: original.attempts})
    send(worker, {:respond, {:ok, :approved}})
    assert :ok = Server.await_idle(server)
    assert [{1, 10, :authorized}] = elem(Server.state(server), 4)
  end

  test "forged_completion cannot retire a durable void obligation", %{path: path} do
    processor = processor(%{void: [:block]})
    server = server(path, processor: {ControlledProcessor, processor})
    authorize(server, 1)
    Server.submit(server, {:void, 1})
    assert_receive {:entered, :void, worker, 1}
    assert {:error, :reserved_event} = Server.submit(server, {:void_outcome, 1, {:ok, :voided}})
    assert {:error, :reserved_event} = Server.submit(server, {:void_confirmed, 1})
    assert {:error, :reserved_event} = Server.submit(server, {:processor_lookup_not_found, 1})
    send(server, {make_ref(), {:ok, :voided}})
    assert [{1, %{status: :pending}}] = Server.inspect_work(server, :voids)
    send(worker, {:respond, {:ok, :voided}})
    assert :ok = Server.await_idle(server)
    assert [] = Server.inspect_work(server, :voids)
    GenServer.stop(server)
    {:ok, journal} = Journal.open(path: path)
    {:ok, events, journal} = Journal.replay(journal)
    assert {:rejected_submission, :void_outcome} in events
    assert Enum.count(events, &(&1 == {:void_confirmed, 1})) == 1
    Journal.close(journal)
  end

  test "void committed without execution is redriven on boot exactly once", %{path: path} do
    first = server(path)
    Server.submit(first, {:request, 1, 10})
    Server.submit(first, {:dispatch, 1})
    Server.processor_callback(first, 1, :approved)
    Server.submit(first, {:void, 1})
    GenServer.stop(first)
    processor = processor(%{})
    recovered = server(path, processor: {ControlledProcessor, processor})
    assert_receive {:entered, :void, _, 1}
    assert :ok = Server.await_idle(recovered)
    assert [] = Server.inspect_work(recovered, :voids)
    GenServer.stop(recovered)
    again = server(path, processor: {ControlledProcessor, processor})
    assert :ok = Server.await_idle(again)
    refute_receive {:entered, :void, _, 1}
    refute_receive {:entered, :authorize, _, _}
  end

  test "blocked lookup does not block submissions or callbacks and rechecks eligibility", %{
    path: path
  } do
    processor = processor(%{authorize: [{:lost, :request}], lookup: [:block]})
    server = server(path, processor: {ControlledProcessor, processor})
    unknown(server, 1)
    caller = Task.async(fn -> Server.retry_after_lookup(server, 1) end)
    assert_receive {:entered, :lookup, worker, 1}
    assert {:ok, :admitted} = Server.submit(server, {:request, 2, 5})
    assert {:ok, :authorized} = Server.processor_callback(server, 1, :approved)
    send(worker, {:respond, :not_found})
    assert {:ok, :not_found} = Task.await(caller)
    refute_receive {:entered, :authorize, _, 1}
  end

  test "raising lookup is bounded, durable and preserves Server", %{path: path} do
    processor = processor(%{authorize: [{:lost, :request}], lookup: [:raise]})
    server = server(path, processor: {ControlledProcessor, processor})
    unknown(server, 1)
    assert {:error, {:lookup_unavailable, :adapter_exception}} = Server.reconcile(server, 1)
    assert [{1, 10, :unknown}] = elem(Server.state(server), 4)
    assert Process.alive?(server)
  end

  test "nolink workers survive Server kill; recovered refs cannot receive their replies", %{
    path: path
  } do
    processor = processor(%{authorize: [:block]})
    server = server(path, processor: {ControlledProcessor, processor})
    Server.submit(server, {:request, 1, 10})
    Server.submit(server, {:dispatch, 1})
    assert_receive {:entered, :authorize, worker, 1}
    monitor = Process.monitor(server)
    Process.exit(server, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^server, :killed}
    assert Process.alive?(worker)
    recovered = server(path, processor: {ControlledProcessor, processor})
    assert [{1, 10, :unknown}] = elem(Server.state(recovered), 4)
    worker_monitor = Process.monitor(worker)
    send(worker, {:respond, {:ok, :approved}})
    assert_receive {:DOWN, ^worker_monitor, :process, ^worker, :normal}
    assert [{1, 10, :unknown}] = elem(Server.state(recovered), 4)
    Server.processor_callback(recovered, 1, :approved)
    assert [{1, 10, :authorized}] = elem(Server.state(recovered), 4)
  end

  test "max_children exhaustion records uncertainty instead of leaking attempts", %{path: path} do
    {:ok, supervisor} = Task.Supervisor.start_link(max_children: 1)

    {:ok, blocker} =
      Task.Supervisor.start_child(supervisor, fn ->
        receive do
          :stop -> :ok
        end
      end)

    processor = processor(%{})

    server =
      server(path, processor: {ControlledProcessor, processor}, effect_supervisor: supervisor)

    Server.submit(server, {:request, 1, 10})
    Server.submit(server, {:dispatch, 1})
    assert :ok = Server.await_idle(server)
    assert [{1, 10, :unknown}] = elem(Server.state(server), 4)
    assert {:error, {:lookup_unavailable, :task_start_failed}} = Server.reconcile(server, 1)
    Server.processor_callback(server, 1, :approved)
    Server.submit(server, {:void, 1})
    assert :ok = Server.await_idle(server)
    assert [{1, %{status: :pending, attempts: 1}}] = Server.inspect_work(server, :voids)
    assert Server.status(server).pending_effects == 0
    send(blocker, :stop)
  end

  test "retry budget, per-key slot and conflict inspection remain coherent", %{path: path} do
    processor = processor(%{void: [:block, {:error, :unavailable}]})

    server =
      server(path,
        processor: {ControlledProcessor, processor},
        void_retry_base: 1,
        void_max_attempts: 2
      )

    authorize(server, 1)
    Server.submit(server, {:void, 1})
    assert_receive {:entered, :void, worker, 1}
    assert {:error, :attempt_active} = Server.redrive_void(server, 1)
    assert Server.status(server).pending_effects == 1
    send(worker, {:respond, {:error, :unavailable}})
    assert_receive {:entered, :void, _, 1}
    assert :ok = Server.await_idle(server)
    assert [{1, %{status: :pending}}] = Server.inspect_work(server, :voids)
    assert {:error, :invalid_page} = Server.inspect_work(server, :voids, 0, 101)
  end

  test "rejection marker sync failure poisons without applying forged completion", %{path: path} do
    server = server(path)
    Server.inject_fault(server, :sync)

    assert {:error, {:sync_failed, _, _}} =
             Server.submit(server, {:void_outcome, 99, {:ok, :voided}})

    assert Server.state(server) == {100, 10, 0, 0, []}
    assert Server.status(server).poisoned != nil
  end

  test "deadline shutdown consumes an already queued successful result", %{path: path} do
    processor = processor(%{authorize: [:block]})
    server = server(path, processor: {ControlledProcessor, processor})
    Server.submit(server, {:request, 1, 10})
    Server.submit(server, {:dispatch, 1})
    assert_receive {:entered, :authorize, worker, 1}
    [{ref, _}] = Map.to_list(:sys.get_state(server).tasks)
    :sys.suspend(server)
    send(server, {:deadline, ref})
    monitor = Process.monitor(worker)
    send(worker, {:respond, {:ok, :approved}})
    assert_receive {:DOWN, ^monitor, :process, ^worker, :normal}
    :sys.resume(server)
    assert :ok = Server.await_idle(server)
    assert [{1, 10, :authorized}] = elem(Server.state(server), 4)
    assert {:monitors, []} = Process.info(server, :monitors)
  end

  test "lost void receipt redrives the same identity after poisoned completion", %{path: path} do
    processor = processor(%{void: [:block, {:ok, :already_voided}]})
    server = server(path, processor: {ControlledProcessor, processor})
    authorize(server, 1)
    Server.submit(server, {:void, 1})
    assert_receive {:entered, :void, worker, 1}
    Server.inject_fault(server, :append)
    send(worker, {:respond, {:ok, :voided}})
    assert {:error, {:journal_poisoned, _}} = Server.await_idle(server)
    assert [{1, %{status: :pending}}] = Server.inspect_work(server, :voids)
    GenServer.stop(server)
    recovered = server(path, processor: {ControlledProcessor, processor})
    assert_receive {:entered, :void, _, 1}
    assert :ok = Server.await_idle(recovered)
    assert [] = Server.inspect_work(recovered, :voids)
    assert elem(Server.state(recovered), 2) == 0
  end

  @tag capture_log: true
  test "invariant quarantine stops writes and preserves inspectable history", %{path: path} do
    server = server(path)
    :sys.replace_state(server, fn data -> %{data | ledger: {100, 10, 99, 0, []}} end)
    monitor = Process.monitor(server)
    catch_exit(Server.submit(server, {:transport_ack, 1}))
    assert_receive {:DOWN, ^monitor, :process, ^server, {:shutdown, {:quarantined, _}}}
    assert {:ok, %{records: 3}} = Journal.inspect_file(path)
    restored = server(path)
    assert Server.state(restored) == {100, 10, 0, 0, []}
  end

  test "contradictory processor reports are visible without reversing terminal state", %{
    path: path
  } do
    server = server(path)
    Server.submit(server, {:request, 1, 10})
    Server.submit(server, {:dispatch, 1})
    Server.processor_callback(server, 1, :declined)
    assert {:ok, :stale} = Server.processor_callback(server, 1, :approved)

    assert [{:processor_conflict, 1, :declined, :approved}] =
             Server.inspect_work(server, :conflicts)

    assert [{1, 10, :declined}] = elem(Server.state(server), 4)
  end

  test "dead idle callers are removed and invalid options are rejected", %{path: path} do
    Process.flag(:trap_exit, true)

    assert {:error, :invalid_runtime_options} =
             Server.start_link(path: path, caps: {100, 10}, authorize_timeout: 0)

    processor = processor(%{authorize: [:block]})
    server = server(path, processor: {ControlledProcessor, processor})
    Server.submit(server, {:request, 1, 10})
    Server.submit(server, {:dispatch, 1})
    assert_receive {:entered, :authorize, worker, 1}
    owner = self()

    caller =
      spawn(fn ->
        send(owner, :waiting)
        Server.await_idle(server, :infinity)
      end)

    assert_receive :waiting
    :sys.get_state(server)
    Process.exit(caller, :kill)
    send(worker, {:respond, {:ok, :approved}})
    assert :ok = Server.await_idle(server)
    assert :sys.get_state(server).waiters == %{}
  end

  test "lookup cannot report success when its observation did not persist", %{path: path} do
    processor = processor(%{authorize: [{:lost, :request}], lookup: [:block]})
    server = server(path, processor: {ControlledProcessor, processor})
    unknown(server, 1)
    caller = Task.async(fn -> Server.reconcile(server, 1) end)
    assert_receive {:entered, :lookup, worker, 1}
    Server.inject_fault(server, :append)
    send(worker, {:respond, :not_found})
    assert {:error, {:append_failed, :injected}} = Task.await(caller)
    assert {:error, {:journal_poisoned, _}} = Server.await_idle(server)
  end

  test "arbitrary malformed and reserved payloads leave only bounded markers", %{path: path} do
    server = server(path)
    payload = :binary.copy("x", 2_000_000)
    assert {:ok, :malformed} = Server.submit(server, {:unexpected, payload})
    assert {:error, :reserved_event} = Server.submit(server, {:void_outcome, payload, self()})
    GenServer.stop(server)
    assert File.stat!(path).size < 1_000
    {:ok, journal} = Journal.open(path: path)
    {:ok, events, journal} = Journal.replay(journal)
    assert {:malformed_submission, :other} in events
    assert {:rejected_submission, :void_outcome} in events
    Journal.close(journal)
  end

  test "processor mailbox callbacks retain the explicit trusted-input boundary", %{path: path} do
    server = server(path)
    Server.submit(server, {:request, 1, 10})
    Server.submit(server, {:dispatch, 1})
    send(server, {:processor_callback, 1, :approved})
    assert [{1, 10, :authorized}] = elem(Server.state(server), 4)
  end

  test "orphaned blocked workers still have a lifetime cap", %{path: path} do
    processor = processor(%{authorize: [:block]})
    server = server(path, processor: {ControlledProcessor, processor}, authorize_timeout: 200)
    Server.submit(server, {:request, 1, 10})
    Server.submit(server, {:dispatch, 1})
    assert_receive {:entered, :authorize, worker, 1}
    owner_monitor = Process.monitor(server)
    worker_monitor = Process.monitor(worker)
    Process.exit(server, :kill)
    assert_receive {:DOWN, ^owner_monitor, :process, ^server, :killed}
    assert_receive {:DOWN, ^worker_monitor, :process, ^worker, :killed}, 1_000
  end

  test "invalid runtime history is quarantined instead of restart looping", %{path: path} do
    Process.flag(:trap_exit, true)
    {:ok, journal} = Journal.open(path: path)
    {:ok, [], journal} = Journal.replay(journal)
    {:ok, journal} = Journal.append_sync(journal, {:hold_ledger_caps, 100, 10})
    {:ok, journal} = Journal.append_sync(journal, {:void_attempt, 99})
    Journal.close(journal)

    assert {:error, {:shutdown, {:quarantined, :invalid_runtime_history}}} =
             Server.start_link(path: path, caps: {100, 10})

    assert {:ok, %{records: 2}} = Journal.inspect_file(path)
  end

  test "empty callback batches are uncertainty, not an unobserved sent hold", %{path: path} do
    processor = processor(%{authorize: [{:callbacks, []}]})
    server = server(path, processor: {ControlledProcessor, processor})
    unknown(server, 1)
  end
end
