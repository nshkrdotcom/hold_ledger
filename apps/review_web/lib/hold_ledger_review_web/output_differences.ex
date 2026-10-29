defmodule HoldLedgerReviewWeb.OutputDifferences do
  @moduledoc """
  A pure, bounded correspondence projection over two already typed outputs.
  A field change is paired only under an unambiguous list identity; indexes and
  repeated occurrences are retained for every other change. This never calls a
  law, fixes accounting, or treats a difference as a policy judgment.
  """
  alias HoldLedgerReviewWeb.ReviewCopy

  @state_fields [
    {"amount_limit", "Amount limit", :cents},
    {"hold_limit", "Hold limit", :slots},
    {"used_amount", "Reserved", :cents},
    {"used_holds", "Used hold slots", :slots}
  ]

  @doc "One projection supplies both in-place annotations and the full audit list."
  def between(%{"after" => before_state} = actual, %{"after" => after_state} = other) do
    scalar =
      Enum.flat_map(@state_fields, fn {field, label, unit} ->
        field_change(["after", field], label, before_state[field], after_state[field], unit)
      end) ++
        field_change(["result"], "Result", actual["result"], other["result"], :result)

    rows =
      scalar ++
        compare_list(
          before_state["entries"],
          after_state["entries"],
          & &1["key"],
          "Entry",
          &entry/1,
          &entry_changes/5
        ) ++
        compare_list(
          actual["effects"],
          other["effects"],
          &{&1["type"], &1["key"]},
          "Action",
          &ReviewCopy.action/1,
          &effect_changes/5
        )

    fields = Enum.filter(rows, &(&1.kind == :field_change))

    ghosts =
      before_state["entries"]
      |> Enum.with_index()
      |> Enum.filter(fn {e, _} ->
        not Enum.any?(after_state["entries"], &(&1["key"] == e["key"]))
      end)
      |> Enum.map(fn {e, i} -> %{entry: e, before_index: i} end)

    %{
      same?: rows == [],
      rows: rows,
      fields: fields,
      by_path: Map.new(fields, &{&1.after_path, &1}),
      ghosts: ghosts,
      field_count: length(fields),
      other_count: length(rows) - length(fields)
    }
  end

  def between(_, _),
    do: %{
      same?: false,
      rows: [],
      fields: [],
      by_path: %{},
      ghosts: [],
      field_count: 0,
      other_count: 0
    }

  @doc "Return the exact changed field at a structured output path, or nil."
  def at(%{by_path: fields}, path) when is_list(path), do: Map.get(fields, path)
  def at(_, _), do: nil

  @doc "Neutral text for a field change; units follow the signed delta."
  def annotation(nil), do: nil
  def annotation(%{before: before, unit: :result}), do: "was #{before}"
  def annotation(%{delta: delta}) when delta != "", do: String.trim(delta)
  def annotation(%{before: before}), do: "was #{before}"

  defp field_change(path, label, before, after_value, unit, occurrence \\ nil)

  defp field_change(_, _, value, value, _, _), do: []

  defp field_change(path, label, before, after_value, unit, occurrence) do
    signed =
      if is_integer(before) and is_integer(after_value),
        do: after_value - before,
        else: nil

    delta =
      if is_integer(signed),
        do: " (#{if(signed >= 0, do: "+", else: "")}#{signed}#{unit_text(unit, signed)})",
        else: ""

    [
      %{
        kind: :field_change,
        label: label,
        path: path,
        before_path: path_for_before(path, occurrence),
        after_path: path,
        before_value: before,
        after_value: after_value,
        before: formatted(before, unit),
        after: formatted(after_value, unit),
        signed: signed,
        unit: unit,
        delta: delta,
        occurrence: occurrence
      }
    ]
  end

  defp path_for_before(path, nil), do: path

  defp path_for_before(["after", "entries", _, field], %{before_index: index}),
    do: ["after", "entries", index, field]

  defp path_for_before(["effects", _, field], %{before_index: index}),
    do: ["effects", index, field]

  defp formatted(value, :cents), do: "#{value}¢"
  defp formatted(value, :slots), do: "#{value}#{unit_text(:slots, value)}"
  defp formatted(value, :result), do: ReviewCopy.result(value)
  defp formatted(value, :status), do: ReviewCopy.state(value)
  defp formatted(value, _), do: to_string(value)
  defp unit_text(:cents, _), do: "¢"
  defp unit_text(:slots, 1), do: " slot"
  defp unit_text(:slots, -1), do: " slot"
  defp unit_text(:slots, _), do: " slots"
  defp unit_text(_, _), do: ""

  defp entry_changes(key, before, after_value, bi, ai) do
    occurrence = %{identity: key, before_index: bi, after_index: ai}

    field_change(
      ["after", "entries", ai, "amount"],
      "Entry #{key} · amount",
      before["amount"],
      after_value["amount"],
      :cents,
      occurrence
    ) ++
      field_change(
        ["after", "entries", ai, "status"],
        "Entry #{key} · status",
        before["status"],
        after_value["status"],
        :status,
        occurrence
      )
  end

  defp effect_changes({kind, key} = id, before, after_value, bi, ai) do
    field_change(
      ["effects", ai, "amount"],
      "#{kind} action #{key} · amount",
      before["amount"],
      after_value["amount"],
      :cents,
      %{identity: id, before_index: bi, after_index: ai}
    )
  end

  defp compare_list(before, after_value, _identity, _name, _display, _changes)
       when before == after_value,
       do: []

  defp compare_list(before, after_value, identity, name, display, changes) do
    before_ids = Enum.map(before, identity)
    after_ids = Enum.map(after_value, identity)
    collection = if name == "Entry", do: "entries", else: "effects"

    order =
      if before_ids == after_ids do
        []
      else
        [
          row(
            :order_change,
            "#{name} order / identities",
            inspect(before_ids, charlists: :as_lists),
            inspect(after_ids, charlists: :as_lists),
            [collection],
            %{before_ids: before_ids, after_ids: after_ids}
          )
        ]
      end

    singles =
      before_ids
      |> Enum.uniq()
      |> Enum.filter(fn id ->
        Enum.count(before_ids, &(&1 == id)) == 1 and
          Enum.count(after_ids, &(&1 == id)) == 1
      end)

    matched =
      Enum.flat_map(singles, fn id ->
        bi = Enum.find_index(before_ids, &(&1 == id))
        ai = Enum.find_index(after_ids, &(&1 == id))
        changes.(id, Enum.at(before, bi), Enum.at(after_value, ai), bi, ai)
      end)

    removed =
      before
      |> Enum.with_index()
      |> Enum.reject(fn {item, _} -> identity.(item) in singles end)
      |> Enum.map(fn {item, i} ->
        row(
          :removed,
          "Removed #{String.downcase(name)} at position #{i + 1}",
          display.(item),
          "—",
          [collection, i],
          %{
            before_index: i,
            identity: identity.(item),
            value: item
          }
        )
      end)

    added =
      after_value
      |> Enum.with_index()
      |> Enum.reject(fn {item, _} -> identity.(item) in singles end)
      |> Enum.map(fn {item, i} ->
        row(
          :added,
          "Added #{String.downcase(name)} at position #{i + 1}",
          "—",
          display.(item),
          [collection, i],
          %{
            after_index: i,
            identity: identity.(item),
            value: item
          }
        )
      end)

    repeated? =
      Enum.any?(before_ids ++ after_ids, fn id ->
        Enum.count(before_ids, &(&1 == id)) > 1 or
          Enum.count(after_ids, &(&1 == id)) > 1
      end)

    caution =
      if repeated?,
        do: [
          row(
            :correspondence,
            "Correspondence",
            "Repeated identities",
            "Occurrences left unpaired",
            [collection],
            nil
          )
        ],
        else: []

    order ++ matched ++ removed ++ added ++ caution
  end

  defp row(kind, label, before, after_value, path, occurrence) do
    {raw_before, raw_after} =
      case {kind, occurrence} do
        {:removed, %{value: item}} -> {item, nil}
        {:added, %{value: item}} -> {nil, item}
        {:order_change, %{before_ids: old, after_ids: new}} -> {old, new}
        _ -> {nil, nil}
      end

    %{
      kind: kind,
      label: label,
      before: before,
      after: after_value,
      before_value: raw_before,
      after_value: raw_after,
      signed: nil,
      delta: "",
      path: path,
      before_path: if(kind == :added, do: nil, else: path),
      after_path: if(kind == :removed, do: nil, else: path),
      occurrence: occurrence,
      unit: nil
    }
  end

  defp entry(e), do: "key #{e["key"]} · #{e["amount"]}¢ · #{e["status"]}"
end
