defmodule HoldLedgerReview.TermCodec do
  @moduledoc "Bounded JSON variants. Display strings are never evaluated."
  @statuses ~w(reserved sent unknown authorized voiding declined voided)a
  def encode(term) when is_tuple(term),
    do: %{"tuple" => term |> Tuple.to_list() |> Enum.map(&encode/1)}

  def encode(term) when is_list(term), do: Enum.map(term, &encode/1)

  def encode(term) when is_map(term),
    do: Map.new(term, fn {k, v} -> {to_string(k), encode(v)} end)

  def encode(term) when is_atom(term) and term not in [true, false, nil], do: Atom.to_string(term)
  def encode(term), do: term

  def decode_state(
        %{
          "amount_limit" => al,
          "hold_limit" => hl,
          "used_amount" => ua,
          "used_holds" => uh,
          "entries" => entries
        } = m
      )
      when map_size(m) == 5 and is_list(entries) and length(entries) <= 100 do
    with true <- Enum.all?([al, hl, ua, uh], &bounded?/1),
         {:ok, decoded} <- decode_entries(entries),
         state = {al, hl, ua, uh, decoded},
         true <- HoldLedger.Spec.valid?(state) do
      {:ok, state}
    else
      _ -> {:error, :malformed}
    end
  end

  def decode_state(_), do: {:error, :malformed}

  def decode_event(%{"type" => "request", "key" => k, "amount" => a} = m) when map_size(m) == 3 do
    if bounded?(k) and bounded?(a) and a > 0,
      do: {:ok, {:request, k, a}},
      else: {:error, :malformed}
  end

  def decode_event(%{"type" => type, "key" => k} = m) when map_size(m) == 2 do
    allowed = %{"void" => :void, "timeout" => :timeout, "dispatch" => :dispatch}

    case Map.fetch(allowed, type) do
      {:ok, tag} -> if bounded?(k), do: {:ok, {tag, k}}, else: {:error, :malformed}
      _ -> {:error, :malformed}
    end
  end

  def decode_event(_), do: {:error, :malformed}
  defp bounded?(n), do: is_integer(n) and n >= 0 and n <= 1_000_000_000

  defp decode_entries(entries) do
    Enum.reduce_while(entries, {:ok, []}, fn
      %{"key" => k, "amount" => a, "status" => s} = m, {:ok, acc} when map_size(m) == 3 ->
        status = Enum.find(@statuses, &(Atom.to_string(&1) == s))

        if bounded?(k) and bounded?(a) and a > 0 and status,
          do: {:cont, {:ok, acc ++ [{k, a, status}]}},
          else: {:halt, {:error, :malformed}}

      _, _ ->
        {:halt, {:error, :malformed}}
    end)
  end
end
