# Reproduce with: HOLD_LEDGER_SEED=4808 mix run scripts/demo.exs
# All identities are synthetic. Files are created under a fresh temporary
# directory, never by deleting an existing .local or unrelated journal.
alias HoldLedger.{Ledger, Server, Spec}
alias HoldLedger.Processor.Sim

seed =
  case Integer.parse(System.get_env("HOLD_LEDGER_SEED", "4808")) do
    {n, ""} when n >= 0 -> n
    _ -> raise "HOLD_LEDGER_SEED must be a nonnegative integer"
  end

:rand.seed(:exsss, {seed + 1, seed + 2, seed + 3})
base = rem(seed, 10_000) * 100
k1 = base + 1
k2 = base + 2
k3 = base + 3
k4 = base + 4

dir =
  Path.join(
    System.tmp_dir!(),
    "hold-ledger-demo-#{System.system_time(:nanosecond)}-#{System.unique_integer([:positive])}"
  )

File.mkdir_p!(dir)
path = Path.join(dir, "demo.log")

show = fn label, result ->
  IO.puts("#{label}: #{inspect(result, limit: :infinity)}")
  result
end

{:ok, sim} = Sim.start_link(dedupe: true)

{:ok, server} =
  Server.start_link(
    path: path,
    caps: {100, 5},
    processor: {Sim, sim}
  )

IO.puts("Hold Ledger demonstration seed=#{seed}")
IO.puts("journal directory: #{dir}")

# An authorize operation executes remotely, but the response disappears.
:ok = Sim.queue_fault(sim, :authorize, :execute_then_drop)
{:ok, :admitted} = show.("admit", Server.submit(server, {:request, k1, 40}))
{:ok, :dispatched} = show.("dispatch", Server.submit(server, {:dispatch, k1}))
:ok = Server.await_idle(server)
{:ok, {^k1, 40, :unknown}} = Ledger.find(elem(Server.state(server), 4), k1)
show.("reply lost: local unknown / receiver active", {:unknown, length(Sim.snapshot(sim).active)})

# Leave a second hold genuinely sent at the point of the process stop. The
# delayed task may complete externally, but its callback targets the old PID.
:ok = Sim.queue_fault(sim, :authorize, {:delay, 1_200})
{:ok, :admitted} = Server.submit(server, {:request, k2, 20})
{:ok, :dispatched} = Server.submit(server, {:dispatch, k2})
{:ok, {^k2, 20, :sent}} = Ledger.find(elem(Server.state(server), 4), k2)
show.("before stop", :sent)
:ok = GenServer.stop(server)

{:ok, server} =
  Server.start_link(
    path: path,
    caps: {100, 5},
    processor: {Sim, sim}
  )

%{pre_restart: pre, post_restart: post} = Server.recovery(server)
{:ok, {^k2, 20, :sent}} = Ledger.find(elem(pre, 4), k2)
{:ok, {^k2, 20, :unknown}} = Ledger.find(elem(post, 4), k2)
show.("replayed before restart -> after restart", {:sent, :unknown})
show.("restored historical effects reissued", Server.status(server).pending_effects)

{:ok, {:reconciled, :authorized}} = Server.reconcile(server, k1)
show.("lookup reconciliation", :authorized)

# A different request is lost before execution. Reliable lookup-not-found
# permits an explicit same-ID retry; the processor then authorizes it once.
:ok = Sim.queue_fault(sim, :authorize, :drop_before)
{:ok, :admitted} = Server.submit(server, {:request, k3, 10})
{:ok, :dispatched} = Server.submit(server, {:dispatch, k3})
:ok = Server.await_idle(server)
{:ok, {^k3, 10, :unknown}} = Ledger.find(elem(Server.state(server), 4), k3)
{:ok, :not_found} = show.("lookup lost request", Server.reconcile(server, k3))
{:ok, :retried} = show.("same-ID retry", Server.retry_after_lookup(server, k3))
:ok = Server.await_idle(server)
{:ok, {^k3, 10, :authorized}} = Ledger.find(elem(Server.state(server), 4), k3)

{:ok, :voiding} =
  show.("void retains capacity until confirmation", Server.submit(server, {:void, k1}))

:ok = Server.await_idle(server)
show.("processor void receipts", Server.status(server).void_receipts)

{:ok, :stale} =
  show.("duplicate callback after void", Server.processor_callback(server, k1, :approved))

{:ok, :duplicate} =
  show.("duplicate request after void", Server.submit(server, {:request, k1, 40}))

# 20 unknown + 10 authorized = 30 counted. An amount of 70 fits exactly.
{:ok, :admitted} = show.("exact fit", Server.submit(server, {:request, k4, 70}))
{100, 5, 100, 3, _} = Server.state(server)
show.("at capacity", {elem(Server.state(server), 2), elem(Server.state(server), 3)})

# Explicitly demonstrate conditional external idempotence in a *different*
# journal and processor instance. Local accounting never sees the extra hold.
{:ok, sim_off} = Sim.start_link(dedupe: false)
:ok = Sim.queue_fault(sim_off, :authorize, :execute_then_drop)

{:error, :missing_terminal_attestation} = HoldLedger.Processor.validate({Sim, sim_off})
{:lost, :reply} = Sim.authorize(sim_off, base + 90, 25)
{:ok, :approved} = Sim.authorize(sim_off, base + 90, 25)
2 = length(Sim.snapshot(sim_off).active)
show.("unsupported receiver counterexample (same key, external holds)", {1, 2})

# M2 changes a *temporary source copy*, never the verified Ledger. Compile it
# as an isolated module and exhibit a real counterexample for premature release.
source = File.read!(Path.join([File.cwd!(), "lib", "hold_ledger", "ledger.ex"]))

original = """
      {:ok, {_, _, :sent}} ->
        {{amount_limit, hold_limit, used_amount, used_holds, set_status(entries, key, :unknown)},
         :marked_unknown, []}
"""

replacement = """
      {:ok, {_, amount, :sent}} ->
        {{amount_limit, hold_limit, used_amount - amount, used_holds - 1,
          set_status(entries, key, :unknown)}, :marked_unknown, []}
"""

true = String.contains?(source, original)

mutant =
  source
  |> String.replace(original, replacement, global: false)
  |> String.replace("defmodule HoldLedger.Ledger do", "defmodule HoldLedger.Demo.M2 do",
    global: false
  )

mutant_path = Path.join(dir, "isolated_m2_ledger.ex")
File.write!(mutant_path, mutant)
Code.compile_file(mutant_path)
witness = {100, 2, 30, 1, [{9, 30, :sent}]}
{correct, :marked_unknown, []} = Ledger.step(witness, {:timeout, 9})
{broken, :marked_unknown, []} = HoldLedger.Demo.M2.step(witness, {:timeout, 9})
true = Spec.valid?(correct)
false = Spec.valid?(broken)
show.("M2 isolated mutation witness (baseline valid, mutant valid)", {true, false})

IO.puts("Scope: formal laws cover the pure Ledger; OTP recovery and faults are covered by tests.")

IO.puts(
  "Assumed: processor honesty/lookup meaning, OS/storage flush and physical persistence; remote exactly-once is not proved."
)

IO.puts("Proof catalog includes terminal absorption and finite histories.")
:ok = GenServer.stop(server)
:ok = GenServer.stop(sim)
:ok = GenServer.stop(sim_off)
IO.puts("Demo completed; isolated journal files retained for inspection.")
