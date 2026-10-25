defmodule HoldLedger.Journal do
  @moduledoc """
  Single-owner journal with application-owned framing and exact-byte integrity.

  A file begins with `HOLDJNL1`. Each frame has a payload length, sequence,
  predecessor digest, header digest, payload, and full digest. Header integrity
  is verified before trusting lengths. Replay folds every frame before enabling
  writes. Complete-prefix rollback requires an external freshness anchor.
  """
  @magic "HOLDJNL1"
  @zero <<0::256>>
  @max_payload 65_536
  @header_size 76
  defstruct [:path, :file, :lock, next_seq: 1, digest: @zero, ready?: false, offset: 8]
  @type t :: %__MODULE__{}

  def open(opts) do
    path = Keyword.fetch!(opts, :path)

    if is_binary(path) and path != "" do
      open_path(Path.expand(path))
    else
      {:error, :invalid_journal_options}
    end
  end

  defp open_path(path) do
    lock = {__MODULE__, path}

    if :global.whereis_name(lock) == :undefined and :global.register_name(lock, self()) == :yes do
      case open_file(path) do
        {:ok, file} ->
          {:ok, %__MODULE__{path: path, file: file, lock: lock}}

        {:error, _} = error ->
          :global.unregister_name(lock)
          error
      end
    else
      {:error, :journal_owned}
    end
  end

  defp open_file(path) do
    with :ok <- File.mkdir_p(Path.dirname(path)),
         {:ok, file} <- :file.open(String.to_charlist(path), [:binary, :read, :write]) do
      case initialize_file(file, path) do
        :ok ->
          {:ok, file}

        {:error, _} = error ->
          :file.close(file)
          error
      end
    end
  end

  defp initialize_file(file, path) do
    case :file.pread(file, 0, 8) do
      :eof ->
        with :ok <- :file.pwrite(file, 0, @magic),
             :ok <- :file.sync(file),
             do: sync_directory(path)

      {:ok, @magic} ->
        :ok

      _ ->
        {:error, :invalid_journal_header}
    end
  end

  @doc "Fold verified frames without materializing the complete event history."
  def fold(%{ready?: false} = journal, acc, fun), do: read_frame(journal, acc, fun)
  def fold(_, _, _), do: {:error, :already_replayed}

  def replay(journal) do
    case fold(journal, [], fn event, acc -> [event | acc] end) do
      {:ok, events, next} -> {:ok, Enum.reverse(events), next}
      error -> error
    end
  end

  def append_sync(journal, event, opts \\ [])

  def append_sync(%{ready?: true} = journal, event, opts) do
    if HoldLedger.Event.valid?(event) do
      payload = :erlang.term_to_binary(event, [:deterministic])
      append_payload(journal, payload, Keyword.get(opts, :fault))
    else
      {:error, :invalid_event}
    end
  end

  def append_sync(_, _, _), do: {:error, :replay_required}

  defp append_payload(_journal, payload, _) when byte_size(payload) > @max_payload,
    do: {:error, :event_too_large}

  defp append_payload(_journal, _payload, :append), do: {:error, {:append_failed, :injected}}

  defp append_payload(journal, payload, fault) do
    prefix = <<byte_size(payload)::32, journal.next_seq::64, journal.digest::binary>>
    header = prefix <> hash(prefix)
    digest = hash(header <> payload)
    frame = header <> payload <> digest

    with :ok <- :file.pwrite(journal.file, journal.offset, frame),
         :ok <- sync_append(journal.file, fault) do
      {:ok,
       %{
         journal
         | next_seq: journal.next_seq + 1,
           digest: digest,
           offset: journal.offset + byte_size(frame)
       }}
    end
  end

  defp sync_append(_, :sync),
    do: {:error, {:sync_failed, :injected_sync_failure, :ambiguous_disk_append}}

  defp sync_append(_, :disk_full),
    do: {:error, {:sync_failed, :simulated_disk_full, :ambiguous_disk_append}}

  defp sync_append(file, _), do: :file.sync(file)

  def close(journal) do
    result = :file.close(journal.file)
    :global.unregister_name(journal.lock)
    result
  end

  defp read_frame(journal, acc, fun) do
    case :file.pread(journal.file, journal.offset, @header_size) do
      :eof ->
        {:ok, acc, %{journal | ready?: true}}

      {:ok, header} when byte_size(header) == @header_size ->
        read_payload(journal, header, acc, fun)

      {:ok, _} ->
        {:error, {:incomplete_tail, journal.offset}}

      {:error, reason} ->
        {:error, {:read_failed, journal.offset, reason}}
    end
  end

  defp read_payload(
         journal,
         <<size::32, seq::64, prev::binary-size(32), checksum::binary-size(32)>> = header,
         acc,
         fun
       ) do
    prefix = binary_part(header, 0, 44)

    cond do
      hash(prefix) != checksum -> {:error, {:corrupt_header, journal.offset}}
      size > @max_payload -> {:error, {:invalid_length, journal.offset}}
      seq != journal.next_seq -> {:error, {:sequence_mismatch, journal.next_seq, seq}}
      prev != journal.digest -> {:error, :predecessor_mismatch}
      true -> decode_frame(journal, header, size, acc, fun)
    end
  end

  defp decode_frame(journal, header, size, acc, fun) do
    case :file.pread(journal.file, journal.offset + @header_size, size + 32) do
      {:ok, <<payload::binary-size(^size), digest::binary-size(32)>>} ->
        if hash(header <> payload) == digest do
          apply_frame(journal, payload, digest, acc, fun)
        else
          {:error, {:digest_mismatch, journal.offset}}
        end

      {:error, reason} ->
        {:error, {:read_failed, journal.offset, reason}}

      _ ->
        {:error, {:incomplete_tail, journal.offset}}
    end
  end

  defp apply_frame(journal, payload, digest, acc, fun) do
    case decode(payload) do
      {:ok, event} ->
        next = %{
          journal
          | next_seq: journal.next_seq + 1,
            digest: digest,
            offset: journal.offset + @header_size + byte_size(payload) + 32
        }

        read_frame(next, fun.(event, acc), fun)

      :error ->
        {:error, {:invalid_payload, journal.offset}}
    end
  end

  defp decode(payload), do: HoldLedger.Event.decode(payload)

  @doc "Read-only integrity inspection; never executes effects or repairs files."
  def inspect_file(path) do
    with {:ok, file} <- :file.open(String.to_charlist(path), [:binary, :read]) do
      result =
        case :file.pread(file, 0, 8) do
          {:ok, @magic} -> fold(%__MODULE__{file: file}, 0, &count_event/2)
          _ -> {:error, :invalid_journal_header}
        end

      :file.close(file)

      inspection_result(result)
    end
  end

  defp count_event(_, count), do: count + 1

  defp inspection_result({:ok, count, journal}),
    do: {:ok, %{records: count, verified_bytes: journal.offset, digest: journal.digest}}

  defp inspection_result(error), do: error

  @doc "Copy a verified prefix to a new path only when the final frame is incomplete."
  def recover_tail(source, destination, opts \\ []) do
    lock = {__MODULE__, Path.expand(source)}

    if :global.whereis_name(lock) == :undefined and :global.register_name(lock, self()) == :yes do
      try do
        case inspect_file(source) do
          {:error, {:incomplete_tail, offset}} -> copy_prefix(source, destination, offset, opts)
          {:ok, _} -> {:error, :no_incomplete_tail}
          error -> error
        end
      after
        :global.unregister_name(lock)
      end
    else
      {:error, :journal_owned}
    end
  end

  defp copy_prefix(source, destination, offset, opts) do
    with {:ok, input} <- :file.open(String.to_charlist(source), [:read, :binary]) do
      result = create_recovered(input, destination, offset, opts)
      :file.close(input)
      result
    end
  end

  defp create_recovered(input, destination, offset, opts) do
    with {:ok, output} <-
           :file.open(String.to_charlist(destination), [:write, :binary, :exclusive]) do
      result =
        with {:ok, ^offset} <- :file.copy(input, output, offset),
             :ok <- recovery_sync(output, Keyword.get(opts, :fault)) do
          recovery_directory(destination, Keyword.get(opts, :fault))
        end

      :file.close(output)

      if result != :ok do
        File.rm(destination)
        sync_directory(destination)
      end

      result
    end
  end

  defp recovery_directory(_, :directory_sync), do: {:error, :recovery_directory_sync_failed}
  defp recovery_directory(path, _), do: sync_directory(path)

  defp recovery_sync(_, :sync), do: {:error, :recovery_sync_failed}
  defp recovery_sync(file, _), do: :file.sync(file)

  defp sync_directory(path) do
    with {:ok, directory} <-
           :file.open(String.to_charlist(Path.dirname(path)), [:read, :directory]) do
      result = :file.sync(directory)
      :file.close(directory)
      result
    end
  end

  defp hash(bytes), do: :crypto.hash(:sha256, bytes)
end
