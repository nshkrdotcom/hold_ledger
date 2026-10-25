defmodule HoldLedgerJournalTest do
  use ExUnit.Case, async: false
  alias HoldLedger.Journal

  defp fixture do
    dir = Path.join(System.tmp_dir!(), "hl-journal-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    Path.join(dir, "events.log")
  end

  defp populated do
    path = fixture()
    {:ok, journal} = Journal.open(path: path)
    {:ok, [], journal} = Journal.replay(journal)
    {:ok, journal} = Journal.append_sync(journal, {:request, 7, 2})
    prefix = journal.offset
    {:ok, journal} = Journal.append_sync(journal, {:dispatch, 7})
    :ok = Journal.close(journal)
    {path, prefix}
  end

  test "owned frames replay and streaming fold agree across 257 events" do
    path = fixture()
    {:ok, journal} = Journal.open(path: path)
    {:ok, [], journal} = Journal.replay(journal)
    assert {:error, :already_replayed} = Journal.replay(journal)
    events = for k <- 1..257, do: {:request, k, k}

    journal =
      Enum.reduce(events, journal, fn e, j ->
        {:ok, j} = Journal.append_sync(j, e)
        j
      end)

    assert journal.next_seq == 258
    :ok = Journal.close(journal)
    {:ok, journal} = Journal.open(path: path)
    assert {:ok, ^events, recovered} = Journal.replay(journal)
    :ok = Journal.close(recovered)
    {:ok, journal} = Journal.open(path: path)
    assert {:ok, 257, recovered} = Journal.fold(journal, 0, fn _, n -> n + 1 end)
    :ok = Journal.close(recovered)
  end

  test "header and payload corruption are rejected; neither is repaired" do
    for where <- [8, 90] do
      {path, _} = populated()
      bytes = File.read!(path)
      <<prefix::binary-size(^where), byte, rest::binary>> = bytes
      File.write!(path, <<prefix::binary, Bitwise.bxor(byte, 1), rest::binary>>)
      assert {:error, _} = Journal.inspect_file(path)
      assert {:error, _} = Journal.recover_tail(path, path <> ".recovered")
      refute File.exists?(path <> ".recovered")
    end
  end

  test "missing first frame violates the sequence and predecessor chain" do
    {path, boundary} = populated()
    bytes = File.read!(path)

    File.write!(
      path,
      binary_part(bytes, 0, 8) <> binary_part(bytes, boundary, byte_size(bytes) - boundary)
    )

    assert {:error, {:sequence_mismatch, 1, 2}} = Journal.inspect_file(path)
  end

  test "every incomplete final frame boundary is inspectable and recovers only to a new file" do
    {path, boundary} = populated()
    original = File.read!(path)

    for size <- (boundary + 1)..(byte_size(original) - 1) do
      File.write!(path, binary_part(original, 0, size))
      assert {:error, {:incomplete_tail, ^boundary}} = Journal.inspect_file(path)
      target = path <> ".#{size}"
      assert :ok = Journal.recover_tail(path, target)
      assert File.read!(path) == binary_part(original, 0, size)
      {:ok, j} = Journal.open(path: target)
      assert {:ok, [{:request, 7, 2}], j} = Journal.replay(j)
      :ok = Journal.close(j)
    end
  end

  test "complete suffix rollback remains an explicit external freshness limitation" do
    {path, boundary} = populated()
    File.write!(path, binary_part(File.read!(path), 0, boundary))
    assert {:ok, %{records: 1}} = Journal.inspect_file(path)
    assert {:error, :no_incomplete_tail} = Journal.recover_tail(path, path <> ".recovered")
  end

  test "recovery sync failures fail and existing targets are never overwritten" do
    {path, _} = populated()
    bytes = File.read!(path)
    File.write!(path, binary_part(bytes, 0, byte_size(bytes) - 1))

    assert {:error, :recovery_sync_failed} =
             Journal.recover_tail(path, path <> ".failed", fault: :sync)

    refute File.exists?(path <> ".failed")

    assert {:error, :recovery_directory_sync_failed} =
             Journal.recover_tail(path, path <> ".dir-failed", fault: :directory_sync)

    refute File.exists?(path <> ".dir-failed")

    File.write!(path <> ".exists", "evidence")
    assert {:error, :eexist} = Journal.recover_tail(path, path <> ".exists")
    assert File.read!(path <> ".exists") == "evidence"
  end

  test "single owner and bounded payloads" do
    path = fixture()
    {:ok, j} = Journal.open(path: path)
    assert {:error, :journal_owned} = Journal.open(path: path)
    {:ok, [], j} = Journal.replay(j)

    assert {:error, :event_too_large} =
             Journal.append_sync(j, {:request, 1, Bitwise.bsl(1, 524_288)})

    :ok = Journal.close(j)
  end

  test "append, sync and disk-full faults never advance the cursor" do
    path = fixture()
    {:ok, j} = Journal.open(path: path)
    {:ok, [], j} = Journal.replay(j)

    assert {:error, {:append_failed, :injected}} =
             Journal.append_sync(j, {:timeout, 7}, fault: :append)

    for fault <- [:sync, :disk_full] do
      assert {:error, {:sync_failed, _, :ambiguous_disk_append}} =
               Journal.append_sync(j, {:timeout, 7}, fault: fault)
    end

    assert j.next_seq == 1
    :ok = Journal.close(j)
  end
end
