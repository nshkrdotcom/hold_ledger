defmodule HoldLedgerReview.Part3Editor do
  @moduledoc """
  Structured, temporary editor over the existing exact TermCodec. A starting
  state may be temporarily inconsistent while being edited but cannot execute;
  a structurally valid, semantically wrong candidate is intentionally allowed.
  Counters are NEVER adjusted except by the explicit recalculate action.
  """
  alias HoldLedger.{Spec}
  alias HoldLedgerReview.{Adversarial, TermCodec}

  @state_fields ~w(amount_limit hold_limit used_amount used_holds)
  @entry_fields ~w(key amount status)
  @event_types ~w(request dispatch timeout void)

  def change(witness, %{"action" => action} = command) do
    with {:ok, _} <- Adversarial.decode(witness),
         {:ok, changed} <- change_fields(witness, action, command),
         {:ok, decoded} <- Adversarial.decode(changed),
         {:ok, canonical} <- Adversarial.encode(decoded) do
      {:ok, canonical}
    else
      _ -> {:error, :invalid_structured_edit}
    end
  end

  def change(_, _), do: {:error, :invalid_structured_edit}

  defp change_fields(w, "state", %{"section" => section, "field" => field, "value" => value})
       when section in ~w(before candidate) and field in @state_fields do
    with {:ok, n} <- integer(value) do
      path = if section == "before", do: ["before", field], else: ["output", "after", field]
      {:ok, put_in(w, path, n)}
    end
  end

  defp change_fields(w, "entry", %{"section" => section, "field" => field, "index" => idx, "value" => value})
       when section in ~w(before candidate) and field in @entry_fields do
    path = if section == "before", do: ["before", "entries"], else: ["output", "after", "entries"]
    with {:ok, index} <- integer(idx),
         entries when is_list(entries) <- get_in(w, path),
         true <- index < length(entries),
         {:ok, converted} <- entry_value(field, value) do
      {:ok, put_in(w, path, List.update_at(entries, index, &Map.put(&1, field, converted)))}
    else
      _ -> {:error, :invalid_entry}
    end
  end

  defp change_fields(w, "add_entry", %{"section" => section}) when section in ~w(before candidate) do
    path = if section == "before", do: ["before", "entries"], else: ["output", "after", "entries"]
    entries = get_in(w, path)
    if length(entries) < TermCodec.limits().entries do
      keys = Enum.map(entries, & &1["key"])
      next = Enum.find(0..TermCodec.limits().number, &(&1 not in keys))
      {:ok, put_in(w, path, entries ++ [%{"key" => next, "amount" => 1, "status" => "reserved"}])}
    else
      {:error, :entry_limit}
    end
  end

  defp change_fields(w, "remove_entry", %{"section" => section, "index" => raw}) when section in ~w(before candidate) do
    path = if section == "before", do: ["before", "entries"], else: ["output", "after", "entries"]
    entries = get_in(w, path)
    with {:ok, index} <- integer(raw), true <- index < length(entries) do
      {:ok, put_in(w, path, List.delete_at(entries, index))}
    else
      _ -> {:error, :invalid_entry_index}
    end
  end

  defp change_fields(w, "recalculate", %{"section" => section}) when section in ~w(before candidate) do
    path = if section == "before", do: ["before"], else: ["output", "after"]
    state = get_in(w, path)
    with {:ok, native} <- TermCodec.decode_state(state) do
      entries = elem(native, 4)
      updated = state |> Map.put("used_amount", Spec.hold_amount(entries)) |> Map.put("used_holds", Spec.hold_count(entries))
      {:ok, put_in(w, path, updated)}
    end
  end

  defp change_fields(w, "event", %{"section" => section, "field" => field, "value" => value})
       when section in ~w(event follow_on) and field in ~w(type key amount) do
    current = w[section] || %{"type" => "request", "key" => 1, "amount" => 1}
    with {:ok, modified} <- event_field(current, field, value) do
      {:ok, Map.put(w, section, modified)}
    end
  end

  defp change_fields(w, "no_follow_on", _), do: {:ok, Map.put(w, "follow_on", nil)}

  defp change_fields(w, "result", %{"value" => value}) do
    if value in TermCodec.results(), do: {:ok, put_in(w, ["output", "result"], value)}, else: {:error, :invalid_result}
  end

  defp change_fields(w, "effect", %{"field" => field, "index" => raw, "value" => value}) when field in ~w(type key amount) do
    with {:ok, index} <- integer(raw), effects when is_list(effects) <- get_in(w, ["output", "effects"]),
         true <- index < length(effects), {:ok, changed} <- effect_field(Enum.at(effects, index), field, value) do
      {:ok, put_in(w, ["output", "effects"], List.replace_at(effects, index, changed))}
    else
      _ -> {:error, :invalid_effect}
    end
  end

  defp change_fields(w, "add_effect", _) do
    effects = get_in(w, ["output", "effects"])
    if length(effects) < TermCodec.limits().effects,
      do: {:ok, put_in(w, ["output", "effects"], effects ++ [%{"type" => "void", "key" => 1, "amount" => nil}])},
      else: {:error, :effect_limit}
  end

  defp change_fields(w, "remove_effect", %{"index" => raw}) do
    effects = get_in(w, ["output", "effects"])
    with {:ok, index} <- integer(raw), true <- index < length(effects) do
      {:ok, put_in(w, ["output", "effects"], List.delete_at(effects, index))}
    else
      _ -> {:error, :invalid_effect_index}
    end
  end

  defp change_fields(_, _, _), do: {:error, :unsupported_edit}

  defp event_field(_current, "type", value) when value in @event_types do
    {:ok, %{"type" => value, "key" => 1, "amount" => if(value == "request", do: 1, else: nil)}}
  end

  defp event_field(current, field, value) when field in ~w(key amount) do
    with {:ok, converted} <- integer(value) do
      {:ok, Map.put(current, field, converted)}
    end
  end

  defp event_field(_, _, _), do: {:error, :invalid_event}

  defp effect_field(_effect, "type", "void"), do: {:ok, %{"type" => "void", "key" => 1, "amount" => nil}}
  defp effect_field(_effect, "type", "authorize"), do: {:ok, %{"type" => "authorize", "key" => 1, "amount" => 1}}
  defp effect_field(effect, field, value) when field in ~w(key amount) do
    with {:ok, converted} <- integer(value) do
      {:ok, Map.put(effect, field, converted)}
    end
  end

  defp effect_field(_, _, _), do: {:error, :invalid_effect}
  defp entry_value("status", status), do: if(status in TermCodec.statuses(), do: {:ok, status}, else: {:error, :invalid_status})
  defp entry_value(_, raw), do: integer(raw)

  defp integer(n) when is_integer(n) and n >= 0 and n <= 1_000_000, do: {:ok, n}
  defp integer(s) when is_binary(s) do
    case Integer.parse(s) do
      {n, ""} -> integer(n)
      _ -> {:error, :invalid_number}
    end
  end
  defp integer(_), do: {:error, :invalid_number}
end
