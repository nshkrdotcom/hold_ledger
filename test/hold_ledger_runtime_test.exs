defmodule HoldLedgerRuntimeTest do
  use ExUnit.Case, async: false
  alias HoldLedger.{Ledger, Server, Spec}
  alias HoldLedger.Processor.Sim

  defp location do
    dir = Path.join(System.tmp_dir!(), "hl-runtime-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)

    Path.join(dir, "runtime.log")
  end

  defp start_server(path, opts \\ []) do
    defaults = [path: path, caps: {100, 10}, allow_faults: true]
    {:ok, pid} = Server.start_link(Keyword.merge(defaults, opts))
    Process.unlink(pid)
    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)
    pid
  end

  defp simulator(opts \\ []) do
    {:ok, pid} = Sim.start_link(opts)
    Process.unlink(pid)
    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)
    pid
  end

  defp entry(server, key) do
    {:ok, result} = Ledger.find(elem(Server.state(server), 4), key)
    result
  end

  test "append failure is fail-closed: no local apply and no receiver effect" do
    path = location()
    sim = simulator()
    server = start_server(path, processor: {Sim, sim})
    before = Server.state(server)
    assert :ok = Server.inject_fault(server, :append)
    assert {:error, {:append_failed, :injected}} = Server.submit(server, {:request, 1, 10})
    assert Server.state(server) == before
    assert Sim.snapshot(sim).attempts == []
    assert Server.status(server).poisoned != nil
    assert {:error, {:journal_poisoned, _}} = Server.submit(server, {:request, 2, 10})
  end

  test "sync failure and disk-full leave memory unchanged without dispatch" do
    for fault <- [:sync, :disk_full] do
      path = location()
      sim = simulator()
      server = start_server(path, processor: {Sim, sim})
      assert {:ok, :admitted} = Server.submit(server, {:request, 9, 30})
      before = Server.state(server)
      assert :ok = Server.inject_fault(server, fault)

      assert {:error, {:sync_failed, _, :ambiguous_disk_append}} =
               Server.submit(server, {:dispatch, 9})

      assert Server.state(server) == before
      assert Sim.snapshot(sim).records == []
      assert {:error, {:journal_poisoned, _}} = Server.submit(server, {:void, 9})
    end
  end

  @tag capture_log: true
  test "crash after durable append before apply replays exactly one transition" do
    path = location()
    server = start_server(path, processor: nil)
    assert :ok = Server.inject_fault(server, :crash_after_sync)
    monitor = Process.monitor(server)

    task =
      Task.async(fn ->
        try do
          Server.submit(server, {:request, 23, 20})
        catch
          :exit, _ -> :caller_observed_exit
        end
      end)

    assert_receive {:DOWN, ^monitor, :process, ^server, :injected_after_durable_append}, 2_000
    assert Task.await(task, 2_000) == :caller_observed_exit

    restored = start_server(path, processor: nil)
    assert Server.recovery(restored).pre_restart == {100, 10, 20, 1, [{23, 20, :reserved}]}
    assert entry(restored, 23) == {23, 20, :reserved}
    assert elem(Server.state(restored), 3) == 1
  end

  test "replay shows sent before restart and unknown afterwards; it does not resend" do
    path = location()
    sim = simulator()
    server = start_server(path, processor: nil)
    assert {:ok, :admitted} = Server.submit(server, {:request, 4, 40})
    assert {:ok, :dispatched} = Server.submit(server, {:dispatch, 4})
    assert entry(server, 4) == {4, 40, :sent}
    assert :ok = GenServer.stop(server)

    restored = start_server(path, processor: {Sim, sim})
    assert elem(Server.recovery(restored).pre_restart, 4) == [{4, 40, :sent}]
    assert entry(restored, 4) == {4, 40, :unknown}
    assert Sim.snapshot(sim).attempts == []
    assert Spec.valid?(Server.state(restored))
  end

  test "execute then lose reply retains capacity; lookup reconciles existing remote hold" do
    path = location()
    sim = simulator()
    :ok = Sim.queue_fault(sim, :authorize, :execute_then_drop)
    server = start_server(path, processor: {Sim, sim})
    assert {:ok, :admitted} = Server.submit(server, {:request, 1, 80})
    assert {:ok, :dispatched} = Server.submit(server, {:dispatch, 1})
    assert :ok = Server.await_idle(server)
    assert entry(server, 1) == {1, 80, :unknown}
    assert elem(Server.state(server), 2) == 80
    assert length(Sim.snapshot(sim).active) == 1
    assert {:ok, {:reconciled, :authorized}} = Server.reconcile(server, 1)
    assert entry(server, 1) == {1, 80, :authorized}
    assert length(Sim.snapshot(sim).active) == 1
  end

  test "dropped request -> not-found lookup -> same identity retry" do
    path = location()
    sim = simulator()
    :ok = Sim.queue_fault(sim, :authorize, :drop_before)
    server = start_server(path, processor: {Sim, sim})
    assert {:ok, :admitted} = Server.submit(server, {:request, 50, 40})
    assert {:ok, :dispatched} = Server.submit(server, {:dispatch, 50})
    assert :ok = Server.await_idle(server)
    assert entry(server, 50) == {50, 40, :unknown}
    assert Sim.snapshot(sim).active == []
    assert {:ok, :not_found} = Server.reconcile(server, 50)
    assert {:ok, :retried} = Server.retry_after_lookup(server, 50)
    assert :ok = Server.await_idle(server)
    assert entry(server, 50) == {50, 40, :authorized}

    assert Enum.map(Sim.snapshot(sim).attempts, fn {key, amount, _} -> {key, amount} end) ==
             [{50, 40}, {50, 40}]

    assert length(Sim.snapshot(sim).active) == 1
  end

  test "unavailable lookup leaves unknown held and never authorizes or retries" do
    path = location()
    sim = simulator()
    :ok = Sim.queue_fault(sim, :authorize, :drop_before)
    server = start_server(path, processor: {Sim, sim})
    assert {:ok, :admitted} = Server.submit(server, {:request, 51, 35})
    assert {:ok, :dispatched} = Server.submit(server, {:dispatch, 51})
    :ok = Server.await_idle(server)
    :ok = Sim.queue_fault(sim, :lookup, :unavailable)
    assert {:error, {:lookup_unavailable, :unavailable}} = Server.retry_after_lookup(server, 51)
    assert entry(server, 51) == {51, 35, :unknown}
    assert length(Sim.snapshot(sim).attempts) == 1
  end

  test "duplicate callback and out-of-order terminal result do not release capacity" do
    path = location()
    sim = simulator()
    :ok = Sim.queue_fault(sim, :authorize, {:out_of_order, [:approved, :declined]})
    server = start_server(path, processor: {Sim, sim})
    assert {:ok, :admitted} = Server.submit(server, {:request, 12, 90})
    assert {:ok, :dispatched} = Server.submit(server, {:dispatch, 12})
    assert :ok = Server.await_idle(server)
    assert entry(server, 12) == {12, 90, :authorized}
    assert {:ok, :stale} = Server.processor_callback(server, 12, :declined)
    assert elem(Server.state(server), 2) == 90
    assert length(Sim.snapshot(sim).active) == 1
  end

  test "duplicated callbacks are each journaled but only first outcome applies" do
    path = location()
    sim = simulator()
    :ok = Sim.queue_fault(sim, :authorize, :duplicate_callback)
    server = start_server(path, processor: {Sim, sim})
    assert {:ok, :admitted} = Server.submit(server, {:request, 14, 7})
    assert {:ok, :dispatched} = Server.submit(server, {:dispatch, 14})
    assert :ok = Server.await_idle(server)
    assert entry(server, 14) == {14, 7, :authorized}
    assert elem(Server.state(server), 3) == 1
    assert length(Sim.snapshot(sim).active) == 1
  end

  test "delayed callback remains sent until later journaled reply" do
    path = location()
    sim = simulator()
    :ok = Sim.queue_fault(sim, :authorize, {:delay, 120})
    server = start_server(path, processor: {Sim, sim})
    assert {:ok, :admitted} = Server.submit(server, {:request, 20, 20})
    assert {:ok, :dispatched} = Server.submit(server, {:dispatch, 20})
    assert entry(server, 20) == {20, 20, :sent}
    assert :ok = Server.await_idle(server)
    assert entry(server, 20) == {20, 20, :authorized}
  end

  test "void is local intent until processor confirms; duplicate after void stays stale" do
    path = location()
    sim = simulator()
    :ok = Sim.queue_fault(sim, :void, :unavailable)
    server = start_server(path, processor: {Sim, sim})
    assert {:ok, :admitted} = Server.submit(server, {:request, 30, 30})
    assert {:ok, :dispatched} = Server.submit(server, {:dispatch, 30})
    :ok = Server.await_idle(server)
    assert {:ok, :voiding} = Server.submit(server, {:void, 30})
    assert entry(server, 30) == {30, 30, :voiding}
    assert :ok = Server.await_idle(server)
    assert Sim.snapshot(sim).active != []

    assert {:void_outcome, 30, {:error, :unavailable}} in Server.status(server).void_receipts

    assert {:ok, :stale} = Server.processor_callback(server, 30, :approved)
    assert {:ok, :duplicate} = Server.submit(server, {:request, 30, 30})
    assert elem(Server.state(server), 2) == 30
  end

  test "receiver dedupe-on holds once, dedupe-off exposes duplicate external authorization" do
    for dedupe <- [true] do
      path = location()
      sim = simulator(dedupe: dedupe)
      :ok = Sim.queue_fault(sim, :authorize, :execute_then_drop)
      server = start_server(path, processor: {Sim, sim})
      assert {:ok, :admitted} = Server.submit(server, {:request, 88, 25})
      assert {:ok, :dispatched} = Server.submit(server, {:dispatch, 88})
      :ok = Server.await_idle(server)
      assert entry(server, 88) == {88, 25, :unknown}
      # Explicit operator retry tests receiver idempotency independently from
      # the safer lookup-gated retry_after_lookup path.
      assert {:ok, :retried} = Server.submit(server, {:retry, 88})
      :ok = Server.await_idle(server)
      assert entry(server, 88) == {88, 25, :authorized}
      assert length(Sim.snapshot(sim).active) == if(dedupe, do: 1, else: 2)
      assert elem(Server.state(server), 3) == 1
      assert {:ok, :voiding} = Server.submit(server, {:void, 88})
      assert :ok = Server.await_idle(server)
      assert elem(Server.state(server), 3) == 0
      assert length(Sim.snapshot(sim).active) == if(dedupe, do: 0, else: 1)
    end
  end

  test "concurrent clients serialize at independent slot/amount caps" do
    path = location()
    server = start_server(path, caps: {25, 25}, processor: nil)

    results =
      1..60
      |> Task.async_stream(fn k -> Server.submit(server, {:request, k, 1}) end,
        max_concurrency: 16,
        ordered: false,
        timeout: 10_000
      )
      |> Enum.map(fn {:ok, result} -> result end)

    assert Enum.count(results, &(&1 == {:ok, :admitted})) == 25
    assert Enum.count(results, &(&1 == {:ok, :insufficient_holds})) == 35
    assert {25, 25, 25, 25, entries} = Server.state(server)
    assert length(entries) == 25
    assert Spec.valid?(Server.state(server))
  end

  test "zero slots, exact fit, and cap mismatch on restart" do
    Process.flag(:trap_exit, true)
    path = location()
    server = start_server(path, caps: {50, 1})
    assert {:ok, :admitted} = Server.submit(server, {:request, 1, 50})
    assert {:ok, :insufficient_holds} = Server.submit(server, {:request, 2, 1})
    assert {50, 1, 50, 1, _} = Server.state(server)
    assert :ok = GenServer.stop(server)

    assert {:error, {:recovery_failed, {:caps_mismatch, {50, 1}, {51, 1}}}} =
             Server.start_link(path: path, caps: {51, 1})
  end

  @tag capture_log: true
  test "a durable dispatch lost before application replays sent then becomes unknown" do
    path = location()
    server = start_server(path, processor: nil)
    assert {:ok, :admitted} = Server.submit(server, {:request, 99, 5})
    assert :ok = Server.inject_fault(server, :crash_after_sync)
    monitor = Process.monitor(server)

    task =
      Task.async(fn ->
        try do
          Server.submit(server, {:dispatch, 99})
        catch
          :exit, _ -> :caller_observed_exit
        end
      end)

    assert_receive {:DOWN, ^monitor, :process, ^server, :injected_after_durable_append}, 2_000
    assert Task.await(task, 2_000) == :caller_observed_exit
    sim = simulator()
    restored = start_server(path, processor: {Sim, sim})
    assert {:ok, {99, 5, :sent}} = Ledger.find(elem(Server.recovery(restored).pre_restart, 4), 99)
    assert entry(restored, 99) == {99, 5, :unknown}
    assert Sim.snapshot(sim).attempts == []
  end

  test "declined lookup after lost reply releases capacity only upon durable result" do
    path = location()
    sim = simulator(decisions: [{44, :declined}])
    :ok = Sim.queue_fault(sim, :authorize, :execute_then_drop)
    server = start_server(path, processor: {Sim, sim})
    assert {:ok, :admitted} = Server.submit(server, {:request, 44, 65})
    assert {:ok, :dispatched} = Server.submit(server, {:dispatch, 44})
    :ok = Server.await_idle(server)
    assert entry(server, 44) == {44, 65, :unknown}
    assert elem(Server.state(server), 2) == 65
    assert {:ok, {:reconciled, :declined}} = Server.reconcile(server, 44)
    assert entry(server, 44) == {44, 65, :declined}
    assert elem(Server.state(server), 2) == 0
    assert elem(Server.state(server), 3) == 0
  end

  test "reserved void has no processor-side effect or uncertainty" do
    path = location()
    sim = simulator()
    server = start_server(path, processor: {Sim, sim})
    assert {:ok, :admitted} = Server.submit(server, {:request, 45, 10})
    assert {:ok, :voided} = Server.submit(server, {:void, 45})
    assert :ok = Server.await_idle(server)
    assert entry(server, 45) == {45, 10, :voided}
    assert Sim.snapshot(sim).voids == []
    assert Sim.snapshot(sim).attempts == []
  end

  test "partial tail refuses server startup and cannot reset to empty" do
    Process.flag(:trap_exit, true)
    path = location()
    server = start_server(path)
    assert {:ok, :admitted} = Server.submit(server, {:request, 70, 4})
    assert :ok = GenServer.stop(server)
    bytes = File.read!(path)
    File.write!(path, binary_part(bytes, 0, byte_size(bytes) - 3))

    case Server.start_link(path: path, caps: {100, 10}) do
      {:error, {:recovery_failed, reason}} ->
        assert reason != nil

      {:error, {:journal_open_failed, reason}} ->
        assert reason != nil

      {:ok, unexpected} ->
        GenServer.stop(unexpected)
        flunk("corrupt log was silently accepted")
    end
  end

  test "physical replay never regenerates authorize tasks even after many records" do
    path = location()
    server = start_server(path, processor: nil)

    for key <- 1..5 do
      assert {:ok, :admitted} = Server.submit(server, {:request, key, 10})
      assert {:ok, :dispatched} = Server.submit(server, {:dispatch, key})
    end

    assert :ok = GenServer.stop(server)

    sim = simulator()
    recovered = start_server(path, processor: {Sim, sim})
    assert Enum.all?(elem(Server.state(recovered), 4), fn {_, _, s} -> s == :unknown end)
    assert Sim.snapshot(sim).attempts == []
    assert Server.recovery(recovered).replayed_event_count >= 11
  end

  test "abruptly killed owner recovers synced sent intent without reissuing effects" do
    path = location()
    server = start_server(path, processor: nil)
    assert {:ok, :admitted} = Server.submit(server, {:request, 101, 15})
    assert {:ok, :dispatched} = Server.submit(server, {:dispatch, 101})
    monitor = Process.monitor(server)
    Process.exit(server, :kill)
    assert_receive {:DOWN, ^monitor, :process, ^server, :killed}, 2_000

    sim = simulator()
    restored = start_server(path, processor: {Sim, sim})

    assert {:ok, {101, 15, :sent}} =
             Ledger.find(elem(Server.recovery(restored).pre_restart, 4), 101)

    assert entry(restored, 101) == {101, 15, :unknown}
    assert elem(Server.state(restored), 2) == 15
    assert Sim.snapshot(sim).attempts == []
  end

  test "zero slots and amount-only exhaustion reject independently" do
    path = location()
    zero = start_server(path, caps: {100, 0})
    assert {:ok, :insufficient_holds} = Server.submit(zero, {:request, 1, 1})
    assert Server.state(zero) == {100, 0, 0, 0, []}

    path = location()
    amount = start_server(path, caps: {25, 100})
    assert {:ok, :admitted} = Server.submit(amount, {:request, 1, 25})
    assert {:ok, :insufficient_amount} = Server.submit(amount, {:request, 2, 1})
    assert Server.state(amount) == {25, 100, 25, 1, [{1, 25, :reserved}]}
  end
end
