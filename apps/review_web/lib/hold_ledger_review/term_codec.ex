defmodule HoldLedgerReview.TermCodec do
  @moduledoc """
  The single, bounded JSON codec for native review events, effects, states and
  full outputs. JSON shapes are exact; decoding never creates atoms.

  Structural validation is deliberately distinct from `HoldLedger.Spec.valid?/1`:
  a coherent JSON after-state with inconsistent counters is a valid what-if.
  """

  @max_number 1_000_000
  @max_entries 8
  @max_effects 8
  @statuses ~w(reserved sent unknown authorized voiding declined voided)a
  @results ~w(admitted dispatched marked_unknown restarted retried authorized declined voided voiding duplicate conflict insufficient_holds insufficient_amount stale not_found malformed)a

  def limits, do: %{number: @max_number, entries: @max_entries, effects: @max_effects}

  def encode_event({:request, key, amount}) do
    if key?(key) and positive?(amount),
      do: {:ok, %{"type" => "request", "key" => key, "amount" => amount}},
      else: {:error, :unsupported_event}
  end

  def encode_event({tag, key}) when tag in [:dispatch, :timeout, :void] do
    if key?(key),
      do: {:ok, %{"type" => Atom.to_string(tag), "key" => key, "amount" => nil}},
      else: {:error, :unsupported_event}
  end

  def encode_event(_), do: {:error, :unsupported_event}

  def decode_event(%{"type" => "request", "key" => key, "amount" => amount} = obj)
      when map_size(obj) == 3 do
    if key?(key) and positive?(amount),
      do: {:ok, {:request, key, amount}},
      else: {:error, :invalid_event}
  end

  for {name, tag} <- [{"dispatch", :dispatch}, {"timeout", :timeout}, {"void", :void}] do
    def decode_event(%{"type" => unquote(name), "key" => key, "amount" => nil} = obj)
        when map_size(obj) == 3 do
      if key?(key), do: {:ok, {unquote(tag), key}}, else: {:error, :invalid_event}
    end
  end

  def decode_event(_), do: {:error, :invalid_event}

  def encode_effect({:authorize, key, amount}) do
    if key?(key) and positive?(amount),
      do: {:ok, %{"type" => "authorize", "key" => key, "amount" => amount}},
      else: {:error, :unsupported_effect}
  end

  def encode_effect({:void, key}) do
    if key?(key),
      do: {:ok, %{"type" => "void", "key" => key, "amount" => nil}},
      else: {:error, :unsupported_effect}
  end

  def encode_effect(_), do: {:error, :unsupported_effect}

  def decode_effect(%{"type" => "authorize", "key" => key, "amount" => amount} = obj)
      when map_size(obj) == 3 do
    if key?(key) and positive?(amount),
      do: {:ok, {:authorize, key, amount}},
      else: {:error, :invalid_effect}
  end

  def decode_effect(%{"type" => "void", "key" => key, "amount" => nil} = obj)
      when map_size(obj) == 3 do
    if key?(key), do: {:ok, {:void, key}}, else: {:error, :invalid_effect}
  end

  def decode_effect(_), do: {:error, :invalid_effect}

  def encode_state({al, hl, ua, uh, entries})
      when is_list(entries) and length(entries) <= @max_entries do
    with true <- Enum.all?([al, hl, ua, uh], &number?/1),
         {:ok, encoded} <- map_checked(entries, &encode_entry/1) do
      {:ok,
       %{
         "amount_limit" => al,
         "hold_limit" => hl,
         "used_amount" => ua,
         "used_holds" => uh,
         "entries" => encoded
       }}
    else
      _ -> {:error, :unsupported_state}
    end
  end

  def encode_state(_), do: {:error, :unsupported_state}

  def decode_state(
        %{
          "amount_limit" => al,
          "hold_limit" => hl,
          "used_amount" => ua,
          "used_holds" => uh,
          "entries" => entries
        } = obj
      )
      when map_size(obj) == 5 and is_list(entries) and length(entries) <= @max_entries do
    with true <- Enum.all?([al, hl, ua, uh], &number?/1),
         {:ok, decoded} <- map_checked(entries, &decode_entry/1) do
      {:ok, {al, hl, ua, uh, decoded}}
    else
      _ -> {:error, :invalid_state}
    end
  end

  def decode_state(_), do: {:error, :invalid_state}

  def encode_output({after_state, result, effects})
      when is_list(effects) and length(effects) <= @max_effects do
    with {:ok, after_json} <- encode_state(after_state),
         {:ok, result_json} <- encode_result(result),
         {:ok, effect_json} <- map_checked(effects, &encode_effect/1) do
      {:ok, %{"after" => after_json, "result" => result_json, "effects" => effect_json}}
    end
  end

  def encode_output(_), do: {:error, :unsupported_output}

  def decode_output(%{"after" => after_json, "result" => result_json, "effects" => effects} = obj)
      when map_size(obj) == 3 and is_list(effects) and length(effects) <= @max_effects do
    with {:ok, after_state} <- decode_state(after_json),
         {:ok, result} <- decode_result(result_json),
         {:ok, decoded} <- map_checked(effects, &decode_effect/1) do
      {:ok, {after_state, result, decoded}}
    end
  end

  def decode_output(_), do: {:error, :invalid_output}

  defp encode_entry({key, amount, status}) do
    if key?(key) and positive?(amount) and status in @statuses,
      do: {:ok, %{"key" => key, "amount" => amount, "status" => Atom.to_string(status)}},
      else: {:error, :unsupported_state}
  end

  defp encode_entry(_), do: {:error, :unsupported_state}

  defp decode_entry(%{"key" => key, "amount" => amount, "status" => status} = obj)
       when map_size(obj) == 3 do
    case Enum.find(@statuses, &(Atom.to_string(&1) == status)) do
      nil ->
        {:error, :invalid_state}

      atom ->
        if key?(key) and positive?(amount),
          do: {:ok, {key, amount, atom}},
          else: {:error, :invalid_state}
    end
  end

  defp decode_entry(_), do: {:error, :invalid_state}

  defp encode_result(result) when result in @results, do: {:ok, Atom.to_string(result)}
  defp encode_result(_), do: {:error, :unsupported_result}

  defp decode_result(result) when is_binary(result) do
    case Enum.find(@results, &(Atom.to_string(&1) == result)) do
      nil -> {:error, :invalid_result}
      atom -> {:ok, atom}
    end
  end

  defp decode_result(_), do: {:error, :invalid_result}

  defp map_checked(list, fun) do
    Enum.reduce_while(list, {:ok, []}, fn item, {:ok, acc} ->
      case fun.(item) do
        {:ok, converted} -> {:cont, {:ok, [converted | acc]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, reversed} -> {:ok, Enum.reverse(reversed)}
      error -> error
    end
  end

  defp number?(n), do: is_integer(n) and n >= 0 and n <= @max_number
  defp key?(n), do: number?(n)
  defp positive?(n), do: number?(n) and n > 0
end
