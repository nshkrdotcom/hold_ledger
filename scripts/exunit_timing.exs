defmodule HoldLedger.ExUnitTiming do
  @moduledoc false
  use GenServer

  @impl true
  def init(_options), do: {:ok, %{started: %{}, files: %{}}}

  @impl true
  def handle_cast({:module_started, test_module}, state) do
    {:noreply, put_in(state, [:started, test_module.name], System.monotonic_time(:microsecond))}
  end

  def handle_cast({:module_finished, test_module}, state) do
    now = System.monotonic_time(:microsecond)
    elapsed = (now - Map.get(state.started, test_module.name, now)) / 1_000_000
    files = Map.update(state.files, test_module.file, elapsed, &(&1 + elapsed))
    {:noreply, %{state | files: files}}
  end

  def handle_cast({:suite_finished, _times}, state), do: finish(state)
  def handle_cast(_event, state), do: {:noreply, state}

  defp finish(state) do
    path = System.fetch_env!("HOLD_LEDGER_EXUNIT_TIMINGS")
    File.write!(path <> ".tmp", JSON.encode!(state.files))
    File.rename!(path <> ".tmp", path)
    {:noreply, state}
  end
end
