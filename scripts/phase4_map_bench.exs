# Experimental source-checked benchmark, not a production performance claim.
# Run: MIX_ENV=test mix run scripts/phase4_map_bench.exs
Code.require_file("../verification/research/0300_map_ledger.ex", __DIR__)

alias HoldLedger.{Ledger, Spec}
alias HoldLedger.Research.MapLedger

iterations =
  case System.get_env("HOLD_LEDGER_BENCH_ITERATIONS", "500") do
    value ->
      case Integer.parse(value) do
        {n, ""} when n > 0 and n <= 100_000 -> n
        _ -> raise ArgumentError, "iterations must be in 1..100000"
      end
  end

measure = fn fun ->
  {microseconds, :ok} =
    :timer.tc(fn ->
      Enum.each(1..iterations, fn _ ->
        _ = fun.()
      end)
    end)

  Float.round(microseconds / iterations, 3)
end

IO.puts("research-only; timing us/op; includes BEAM and VM warmup effects")
IO.puts("size,ledger_find,map_find,ledger_request,map_request,encode,decode")

for size <- [0, 16, 256, 2048] do
  # The fixture constructor is independent of Ledger.step and the Spec oracle:
  # terminal entries retain their keys but do not consume exposure.
  entries = Enum.map(1..size//1, fn i -> {i, 1, :declined} end)
  entries = if size == 0, do: [], else: entries
  state = {100, 1, 0, 0, entries}
  candidate = MapLedger.encode(state)
  event = {:request, -1, 1}
  {next_old, result, effects} = Ledger.step(state, event)
  {next_new, ^result, ^effects} = MapLedger.step(candidate, event)

  unless Spec.valid?(state) and MapLedger.decode(candidate) === state and
           MapLedger.decode(next_new) === next_old and
           Ledger.find(entries, size + 1) === MapLedger.find(candidate, size + 1) and
           Spec.expected_step(state, event) === {next_old, result, effects} do
    raise "equivalence check failed at size #{size}"
  end

  values = [
    measure.(fn -> Ledger.find(entries, size + 1) end),
    measure.(fn -> MapLedger.find(candidate, size + 1) end),
    measure.(fn -> Ledger.step(state, event) end),
    measure.(fn -> MapLedger.step(candidate, event) end),
    measure.(fn -> MapLedger.encode(state) end),
    measure.(fn -> MapLedger.decode(candidate) end)
  ]

  IO.puts(Enum.join([size | values], ","))
end
