# Synthetic capacity/recovery measurements; not a hardware durability test.
alias HoldLedger.{Journal, Server}

for count <- [100, 1_000] do
  folder = Path.join(System.tmp_dir!(), "hold-ledger-bench-#{System.unique_integer([:positive])}")
  path = Path.join(folder, "journal")
  {:ok, server} = Server.start_link(path: path, caps: {count, count})

  samples =
    for key <- 1..count do
      {elapsed, {:ok, :admitted}} = :timer.tc(fn -> Server.submit(server, {:request, key, 1}) end)
      elapsed
    end

  {:memory, memory} = Process.info(server, :memory)
  :ok = GenServer.stop(server)

  {recovery_us, {:ok, recovered}} =
    :timer.tc(fn -> Server.start_link(path: path, caps: {count, count}) end)

  :ok = GenServer.stop(recovered)
  {:ok, %{records: records}} = Journal.inspect_file(path)
  p95 = samples |> Enum.sort() |> Enum.at(div(count * 95, 100) - 1)

  IO.puts(
    "entries=#{count} records=#{records} request_p95_us=#{p95} recovery_us=#{recovery_us} server_bytes=#{memory}"
  )

  File.rm_rf!(folder)
end
