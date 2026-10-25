defmodule HoldLedger.Journal do
  @moduledoc """
  A single-owner, append/sync-first `:disk_log` journal in `:halt`/`:internal` mode.

  Every record carries a one-based sequence and SHA-256 predecessor chain.
  `replay/2` consumes *every* chunk before declaring the log usable. An invalid
  frame, discontinuity, bad byte count, or disk_log read error is fatal; no
  recovered prefix is silently installed as the ledger. In particular, OTP may
  open a truncated log successfully and only report corruption on a later read.

  The chain detects missing/corrupted records in an existing log, but cannot
  authenticate a wholesale replacement with a fresh log. Filesystem ordering,
  durable flushes, and physical media remain external assumptions.
  """

  @initial_digest :binary.copy(<<0>>, 32)
  @record_tag :hold_ledger_event_v1

  defstruct [:name, :path, next_seq: 1, digest: @initial_digest, ready?: false]

  @type t :: %__MODULE__{
          name: atom(),
          path: String.t(),
          next_seq: pos_integer(),
          digest: binary()
        }

  @doc "Open a log by an explicitly supplied atom name and pathname. No repair is attempted."
  @spec open(keyword()) :: {:ok, t()} | {:error, term()}
  def open(opts) do
    name = Keyword.fetch!(opts, :name)
    path = Keyword.fetch!(opts, :path)

    if not is_atom(name) or not is_binary(path) or path == "" do
      {:error, :invalid_journal_options}
    else
      open_log(name, path)
    end
  end

  defp open_log(name, path) do
    with :ok <- File.mkdir_p(Path.dirname(path)) do
      case :disk_log.open(
             name: name,
             file: String.to_charlist(path),
             type: :halt,
             format: :internal,
             repair: false
           ) do
        {:ok, ^name} ->
          {:ok, %__MODULE__{name: name, path: path}}

        {:repaired, ^name, recovered, bad} ->
          :disk_log.close(name)
          {:error, {:unexpected_repair, recovered, bad}}

        {:error, reason} ->
          {:error, {:open_failed, reason}}

        other ->
          {:error, {:open_unexpected, other}}
      end
    end
  end

  @doc "Check and collect every chunk in order, returning events and an append-ready handle."
  @spec replay(t(), keyword()) :: {:ok, list(), t()} | {:error, term()}
  def replay(journal, opts \\ [])

  def replay(%__MODULE__{ready?: false} = journal, opts) do
    chunk_size = Keyword.get(opts, :chunk_size, 128)

    if is_integer(chunk_size) and chunk_size > 0 do
      read_chunks(journal, :start, chunk_size, [], 0)
    else
      {:error, :invalid_chunk_size}
    end
  end

  def replay(%__MODULE__{}, _opts), do: {:error, :already_replayed}

  @doc "Persist a term and sync it before advancing the in-memory cursor."
  @spec append_sync(t(), term(), keyword()) :: {:ok, t()} | {:error, term()}
  def append_sync(journal, event, opts \\ [])

  def append_sync(%__MODULE__{ready?: true} = journal, event, opts) do
    fault = Keyword.get(opts, :fault)
    seq = journal.next_seq
    prev = journal.digest
    digest = digest_record(seq, prev, event)
    record = {@record_tag, seq, prev, event, digest}

    if fault == :append do
      {:error, {:append_failed, :injected}}
    else
      append_record(journal, record, fault, digest)
    end
  end

  def append_sync(%__MODULE__{}, _event, _opts), do: {:error, :replay_required}

  defp append_record(journal, record, fault, digest) do
    case :disk_log.log(journal.name, record) do
      :ok -> sync_record(journal, fault, digest)
      {:error, reason} -> {:error, {:append_failed, reason}}
    end
  end

  defp sync_record(journal, fault, digest) do
    result =
      case fault do
        :sync -> {:error, :injected_sync_failure}
        :disk_full -> {:error, :simulated_disk_full}
        _ -> :disk_log.sync(journal.name)
      end

    case result do
      :ok -> {:ok, %{journal | next_seq: journal.next_seq + 1, digest: digest}}
      {:error, reason} -> {:error, {:sync_failed, reason, :ambiguous_disk_append}}
    end
  end

  @spec close(t()) :: :ok | {:error, term()}
  def close(%__MODULE__{name: name}), do: :disk_log.close(name)

  defp read_chunks(journal, continuation, chunk_size, reversed, count) do
    case :disk_log.chunk(journal.name, continuation, chunk_size) do
      :eof ->
        {:ok, Enum.reverse(reversed), %{journal | ready?: true}}

      {:error, reason} ->
        {:error, {:chunk_read_failed, count, reason}}

      {_, _items, bad_bytes} when bad_bytes != 0 ->
        {:error, {:corrupt_chunk_bytes, count, bad_bytes}}

      {next, items, 0} when is_list(items) ->
        verify_chunk(journal, next, items, chunk_size, reversed, count)

      {next, items} when is_list(items) ->
        verify_chunk(journal, next, items, chunk_size, reversed, count)

      other ->
        {:error, {:unexpected_chunk, count, other}}
    end
  end

  defp verify_chunk(journal, continuation, items, chunk_size, reversed, count) do
    case Enum.reduce_while(items, {:ok, journal, reversed, count}, &verify_record/2) do
      {:ok, next_journal, new_reversed, new_count} ->
        read_chunks(next_journal, continuation, chunk_size, new_reversed, new_count)

      {:error, _} = error ->
        error
    end
  end

  defp verify_record(record, {:ok, current, acc, n}) do
    case check_record(current, record) do
      {:ok, event, next} -> {:cont, {:ok, next, [event | acc], n + 1}}
      {:error, reason} -> {:halt, {:error, {:invalid_record, n + 1, reason}}}
    end
  end

  defp check_record(
         %__MODULE__{next_seq: seq, digest: prev} = journal,
         {@record_tag, actual_seq, actual_prev, event, actual_digest}
       ) do
    cond do
      actual_seq != seq -> {:error, {:sequence_mismatch, seq, actual_seq}}
      actual_prev != prev -> {:error, :predecessor_mismatch}
      actual_digest != digest_record(seq, prev, event) -> {:error, :digest_mismatch}
      true -> {:ok, event, %{journal | next_seq: seq + 1, digest: actual_digest}}
    end
  end

  defp check_record(_journal, _record), do: {:error, :malformed_frame}

  defp digest_record(seq, prev, event) do
    :crypto.hash(:sha256, :erlang.term_to_binary({@record_tag, seq, prev, event}))
  end
end
