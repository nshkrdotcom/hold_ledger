defmodule HoldLedger.TerminalContractTest do
  use ExUnit.Case, async: false
  alias HoldLedger.{ControlledProcessor, Ledger, Processor, Server}
  alias HoldLedger.Processor.Sim

  defmodule LyingAdapter do
    @behaviour HoldLedger.Processor
    @impl true
    def capabilities(_), do: %{terminal_confirmation: true, non_resurrection: :permanent}
    @impl true
    def authorize(context, key, amount), do: Sim.authorize(context, key, amount)
    @impl true
    def lookup(context, key), do: Sim.lookup(context, key)
    @impl true
    def void(context, key), do: Sim.void(context, key)
  end

  setup do
    dir = Path.join(System.tmp_dir!(), "hl-terminal-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, path: Path.join(dir, "journal")}
  end

  test "attestation validation catches absent support, not a false declaration", %{path: path} do
    {:ok, sim} = start_supervised({Sim, dedupe: false})
    assert {:error, :missing_terminal_attestation} = Processor.validate({Sim, sim})
    assert {:error, :missing_terminal_attestation} = Processor.validate({String, nil})
    assert :ok = Processor.validate({LyingAdapter, sim})

    {:ok, _server} =
      start_supervised({Server, path: path, caps: {100, 2}, processor: {LyingAdapter, sim}})

    assert {:ok, :approved} = Sim.authorize(sim, 1, 100)
    assert {:ok, :approved} = Sim.authorize(sim, 1, 100)
    assert {:ok, :voided} = LyingAdapter.void(sim, 1)
    assert length(Sim.snapshot(sim).active) == 1
  end

  test "simulated unseen-key void fences all subsequent authorize deliveries" do
    {:ok, sim} = start_supervised(Sim)
    assert {:ok, :already_voided} = Sim.void(sim, 99)
    assert {:ok, :declined} = Sim.authorize(sim, 99, 100)
    assert {:ok, :already_voided} = Sim.void(sim, 99)
    assert Sim.snapshot(sim).active == []
  end

  test "same identity rejects a changed payload without disturbing the existing authorization" do
    {:ok, sim} = start_supervised(Sim)
    assert {:ok, :approved} = Sim.authorize(sim, 1, 40)
    assert {:error, :identity_conflict} = Sim.authorize(sim, 1, 60)
    assert [%{key: 1, amount: 40, status: :active}] = Sim.snapshot(sim).active
    assert {:ok, :approved} = Sim.lookup(sim, 1)
    assert {:ok, :voided} = Sim.void(sim, 1)
    assert {:error, :identity_conflict} = Sim.authorize(sim, 1, 60)
    assert Sim.snapshot(sim).active == []
  end

  @tag capture_log: true
  test "one synced confirmation recovers release and retirement together", %{path: path} do
    {:ok, processor} =
      start_supervised({ControlledProcessor, owner: self(), modes: %{void: [:block]}})

    opts = [
      path: path,
      caps: {100, 2},
      processor: {ControlledProcessor, processor},
      allow_faults: true
    ]

    {:ok, server} = Server.start_link(opts)
    Process.unlink(server)
    assert {:ok, :admitted} = Server.submit(server, {:request, 1, 100})
    assert {:ok, :dispatched} = Server.submit(server, {:dispatch, 1})
    assert :ok = Server.await_idle(server)
    assert {:ok, :voiding} = Server.submit(server, {:void, 1})
    assert_receive {:entered, :void, worker, 1}
    assert {:ok, :insufficient_amount} = Server.submit(server, {:request, 2, 100})
    assert {:error, :reserved_event} = Server.submit(server, {:void_confirmed, 1})
    assert :ok = Server.inject_fault(server, :crash_after_sync)
    ref = Process.monitor(server)
    send(worker, {:respond, {:ok, :voided}})
    assert_receive {:DOWN, ^ref, :process, ^server, :injected_after_durable_append}
    {:ok, recovered} = start_supervised({Server, opts})
    assert {:ok, {1, 100, :voided}} = Ledger.find(elem(Server.state(recovered), 4), 1)
    assert Server.inspect_work(recovered, :voids) == []
    assert {:ok, :admitted} = Server.submit(recovered, {:request, 2, 100})
  end
end
