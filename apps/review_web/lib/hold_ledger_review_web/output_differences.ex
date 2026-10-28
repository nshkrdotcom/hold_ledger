defmodule HoldLedgerReviewWeb.OutputDifferences do
  alias HoldLedgerReviewWeb.ReviewCopy

  @moduledoc """
  A bounded, read-only description of two already-typed outputs. Never evaluates
  a law, normalizes counters, or assumes duplicate identities correspond.
  """

  @state_fields [
    {"amount_limit", "Amount limit", "¢"},
    {"hold_limit", "Hold limit", " slots"},
    {"used_amount", "Reserved", "¢"},
    {"used_holds", "Used hold slots", " slots"}
  ]

  def between(%{"after" => actual} = code, %{"after" => alternative} = other) do
    scalar =
      Enum.flat_map(@state_fields, fn {field, label, unit} ->
        change(label, actual[field], alternative[field], unit)
      end) ++ change("Result", code["result"], other["result"], "")

    rows =
      scalar ++
        entries(actual["entries"], alternative["entries"]) ++
        effects(code["effects"], other["effects"])

    %{same?: rows == [], rows: rows}
  end

  def between(_, _), do: %{same?: false, rows: []}

  defp change(_, value, value, _), do: []

  defp change(label, before, after_value, unit) do
    delta =
      if is_integer(before) and is_integer(after_value),
        do:
          " (#{if(after_value - before >= 0, do: "+", else: "")}#{after_value - before}#{unit})",
        else: ""

    [%{label: label, before: "#{before}#{unit}", after: "#{after_value}#{unit}", delta: delta}]
  end

  defp entries(before, after_value) do
    compare_list(before, after_value, & &1["key"], "Entry", &entry/1, fn key, a, b ->
      change("Entry #{key} · amount", a["amount"], b["amount"], "¢") ++
        change(
          "Entry #{key} · status",
          ReviewCopy.state(a["status"]),
          ReviewCopy.state(b["status"]),
          ""
        )
    end)
  end

  defp effects(before, after_value) do
    compare_list(
      before,
      after_value,
      &{&1["type"], &1["key"]},
      "Action",
      &effect/1,
      fn {kind, key}, a, b ->
        change("#{kind} action #{key} · amount", a["amount"], b["amount"], "¢")
      end
    )
  end

  defp compare_list(before, after_value, _identity, _name, _display, _compare)
       when before == after_value, do: []

  defp compare_list(before, after_value, identity, name, display, compare) do
    before_ids = Enum.map(before, identity)
    after_ids = Enum.map(after_value, identity)

    order =
      if before_ids == after_ids,
        do: [],
        else: [
          row(
            "#{name} order / identities",
            inspect(before_ids, charlists: :as_lists),
            inspect(after_ids, charlists: :as_lists)
          )
        ]

    # Match ONLY when a key occurs exactly once in each list. A duplicate on
    # either side makes every occurrence of that key unpaired, even if equal.
    singles =
      before_ids
      |> Enum.filter(fn key ->
        Enum.count(before_ids, &(&1 == key)) == 1 and
          Enum.count(after_ids, &(&1 == key)) == 1
      end)

    matched =
      Enum.flat_map(singles, fn key ->
        a = Enum.find(before, &(identity.(&1) == key))
        b = Enum.find(after_value, &(identity.(&1) == key))
        compare.(key, a, b)
      end)

    removed =
      before
      |> Enum.with_index(1)
      |> Enum.reject(fn {item, _} -> identity.(item) in singles end)
      |> Enum.map(fn {item, index} ->
        row("Removed #{name |> String.downcase()} at position #{index}", display.(item), "—")
      end)

    added =
      after_value
      |> Enum.with_index(1)
      |> Enum.reject(fn {item, _} -> identity.(item) in singles end)
      |> Enum.map(fn {item, index} ->
        row("Added #{name |> String.downcase()} at position #{index}", "—", display.(item))
      end)

    caution =
      if Enum.any?(before_ids ++ after_ids, fn key ->
           Enum.count(before_ids, &(&1 == key)) > 1 or
             Enum.count(after_ids, &(&1 == key)) > 1
         end),
         do: [row("Correspondence", "Repeated identities", "Occurrences left unpaired")],
         else: []

    order ++ matched ++ removed ++ added ++ caution
  end

  defp row(label, before, after_value),
    do: %{label: label, before: before, after: after_value, delta: ""}

  defp entry(e), do: "key #{e["key"]} · #{e["amount"]}¢ · #{e["status"]}"

  defp effect(e), do: ReviewCopy.action(e)
end
