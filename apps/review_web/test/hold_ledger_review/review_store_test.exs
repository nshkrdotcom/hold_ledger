defmodule HoldLedgerReview.ReviewStoreTest do
  use ExUnit.Case, async: true
  alias HoldLedgerReview.{ReviewStore, Trace}

  setup do
    dir = Path.join(System.tmp_dir!(), "trace-writer-#{Trace.token()}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    %{dir: dir}
  end

  test "restart preserves current traces and leaves retired documents untouched", %{dir: dir} do
    legacy = Path.join(dir, "retired-review.json")
    File.write!(legacy, ~s({"ai_jobs":[{"status":"pending"}]}))
    before = File.read!(legacy)
    store = start_supervised!({ReviewStore, name: nil, dir: dir})
    assert {:ok, doc} = GenServer.call(store, {:trace_create, "ledger", 100, 2})
    stop_supervised!(ReviewStore)
    recovered = start_supervised!({ReviewStore, name: nil, dir: dir})
    assert {:ok, ^doc} = GenServer.call(recovered, {:trace_get, doc["id"]})
    assert File.read!(legacy) == before
  end

  test "failed writes cannot create a visible trace", %{dir: dir} do
    store =
      start_supervised!(
        {ReviewStore, name: nil, dir: dir, writer: fn _, _ -> {:error, :enospc} end}
      )

    assert {:error, :enospc} = GenServer.call(store, {:trace_create, "ledger", 100, 2})
    assert File.ls!(dir) == []
  end

  test "synced replacement leaves no temporary files", %{dir: dir} do
    path = Path.join(dir, "record.json")
    assert :ok = ReviewStore.atomic_write(path, "first")
    assert :ok = ReviewStore.atomic_write(path, "second")
    assert File.read!(path) == "second"
    assert File.ls!(dir) == ["record.json"]
  end
end
