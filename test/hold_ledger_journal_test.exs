defmodule HoldLedgerJournalTest do
  use ExUnit.Case, async: false
  alias HoldLedger.Journal

  defp fixture do
    dir = Path.join(System.tmp_dir!(), "hl-journal-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    {Path.join(dir, "events.log"), String.to_atom("hl_j08_#{System.unique_integer([:positive])}")}
  end

  test "ordered halt/internal append and sync, chunked full replay, sealed sequence" do
    {path, name} = fixture()
    {:ok, opened} = Journal.open(path: path, name: name)
    {:ok, [], journal} = Journal.replay(opened, chunk_size: 2)
    assert {:error, :already_replayed} = Journal.replay(journal)

    events = for k <- 1..257, do: {:request, k, k}

    journal =
      Enum.reduce(events, journal, fn event, current ->
        assert {:ok, next} = Journal.append_sync(current, event)
        next
      end)

    assert journal.next_seq == 258
    assert :ok == Journal.close(journal)

    {:ok, opened} = Journal.open(path: path, name: name)
    assert {:ok, ^events, recovered} = Journal.replay(opened, chunk_size: 3)
    assert recovered.next_seq == 258
    assert :ok == Journal.close(recovered)
  end

  test "malformed chain cannot silently omit its first record" do
    {path, name} = fixture()
    {:ok, opened} = Journal.open(path: path, name: name)
    {:ok, [], journal} = Journal.replay(opened)

    assert :ok ==
             :disk_log.log(
               name,
               {:hold_ledger_event_v1, 2, <<0::256>>, :missing_first, <<1::256>>}
             )

    assert :ok == :disk_log.sync(name)
    assert :ok == Journal.close(journal)

    {:ok, reopened} = Journal.open(path: path, name: name)
    assert {:error, {:invalid_record, 1, {:sequence_mismatch, 1, 2}}} = Journal.replay(reopened)
    Journal.close(reopened)
  end

  test "invalid digest is rejected, not treated as an empty journal" do
    {path, name} = fixture()
    {:ok, opened} = Journal.open(path: path, name: name)
    {:ok, [], journal} = Journal.replay(opened)
    assert :ok == :disk_log.log(name, {:hold_ledger_event_v1, 1, <<0::256>>, :event, <<99::256>>})
    assert :ok == :disk_log.sync(name)
    Journal.close(journal)

    {:ok, reopened} = Journal.open(path: path, name: name)
    assert {:error, {:invalid_record, 1, :digest_mismatch}} = Journal.replay(reopened)
    Journal.close(reopened)
  end

  test "truncated tail is an explicit failure even if disk_log.open succeeds" do
    {path, name} = fixture()
    {:ok, opened} = Journal.open(path: path, name: name)
    {:ok, [], journal} = Journal.replay(opened)
    {:ok, journal} = Journal.append_sync(journal, {:request, 7, 2})
    {:ok, journal} = Journal.append_sync(journal, {:dispatch, 7})
    assert :ok == Journal.close(journal)

    bytes = File.read!(path)
    File.write!(path, binary_part(bytes, 0, byte_size(bytes) - 5))

    case Journal.open(path: path, name: name) do
      {:error, reason} ->
        assert reason != nil

      {:ok, reopened} ->
        assert {:error, reason} = Journal.replay(reopened, chunk_size: 1)
        assert reason != nil
        Journal.close(reopened)
    end
  end

  test "simulated sync and disk-full do not advance the cursor" do
    {path, name} = fixture()
    {:ok, opened} = Journal.open(path: path, name: name)
    {:ok, [], journal} = Journal.replay(opened)

    assert {:error, {:append_failed, :injected}} =
             Journal.append_sync(journal, :any, fault: :append)

    assert {:error, {:sync_failed, :simulated_disk_full, :ambiguous_disk_append}} =
             Journal.append_sync(journal, :uncertain, fault: :disk_full)

    assert journal.next_seq == 1
    Journal.close(journal)
  end
end
