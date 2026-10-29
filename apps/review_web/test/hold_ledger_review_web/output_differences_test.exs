defmodule HoldLedgerReviewWeb.OutputDifferencesTest do
  use ExUnit.Case, async: true
  alias HoldLedgerReviewWeb.OutputDifferences

  defp output(entries \\ [], effects \\ [], overrides \\ %{}) do
    state = %{
      "amount_limit" => 100,
      "hold_limit" => 2,
      "used_amount" => 100,
      "used_holds" => 1,
      "entries" => entries
    }

    %{
      "after" => Map.merge(state, overrides),
      "result" => "voiding",
      "effects" => effects
    }
  end

  defp entry(key, amount, status),
    do: %{"key" => key, "amount" => amount, "status" => status}

  test "identical outputs are named without difference rows" do
    actual = output([entry(11, 100, "voiding")])
    assert %{same?: true, rows: []} = OutputDifferences.between(actual, actual)
  end

  test "bounded limits, counters and result receive deterministic signed changes" do
    actual = output()

    alternative =
      actual
      |> put_in(["after", "amount_limit"], 101)
      |> put_in(["after", "hold_limit"], 3)
      |> put_in(["after", "used_amount"], 0)
      |> put_in(["after", "used_holds"], 0)
      |> Map.put("result", "voided")

    original = actual
    rows = OutputDifferences.between(actual, alternative).rows

    assert Enum.map(rows, & &1.label) == [
             "Amount limit",
             "Hold limit",
             "Reserved",
             "Used hold slots",
             "Result"
           ]

    assert Enum.at(rows, 2).before == "100¢"
    assert Enum.at(rows, 2).after == "0¢"
    assert Enum.at(rows, 2).delta == " (-100¢)"
    assert actual == original
  end

  test "unambiguous entry updates show status and amount, not an invented replacement" do
    actual = output([entry(11, 100, "voiding")])
    candidate = output([entry(11, 50, "voided")])
    rows = OutputDifferences.between(actual, candidate).rows

    assert Enum.any?(rows, &(&1.label == "Entry 11 · amount" && &1.delta == " (-50¢)"))
    assert Enum.any?(rows, &(&1.label == "Entry 11 · status" && &1.after == "Cancelled"))
    refute Enum.any?(rows, &String.starts_with?(&1.label, "Added entry"))
  end

  test "changed entry identity is explicitly removed and added, never paired" do
    rows =
      OutputDifferences.between(
        output([entry(11, 100, "voiding")]),
        output([entry(12, 100, "voiding")])
      ).rows

    assert Enum.any?(rows, &(&1.label == "Removed entry at position 1"))
    assert Enum.any?(rows, &(&1.label == "Added entry at position 1"))
    refute Enum.any?(rows, &String.contains?(&1.label, "Entry 11 · status"))
  end

  test "duplicate keys on either side remain separate positional occurrences" do
    actual = output([entry(11, 30, "reserved"), entry(11, 70, "voiding")])
    alternative = output([entry(11, 100, "voided")])
    rows = OutputDifferences.between(actual, alternative).rows

    assert Enum.count(rows, &String.starts_with?(&1.label, "Removed entry")) == 2
    assert Enum.count(rows, &String.starts_with?(&1.label, "Added entry")) == 1
    assert Enum.any?(rows, &(&1.label == "Correspondence"))
  end

  test "reordered entries and repeated effects preserve list order and multiplicity" do
    a = entry(11, 40, "reserved")
    b = entry(12, 60, "voiding")
    void = %{"type" => "void", "key" => 11, "amount" => nil}
    authorize = %{"type" => "authorize", "key" => 12, "amount" => 60}

    actual = output([a, b], [void, void, authorize])
    candidate = output([b, a], [authorize, void])
    rows = OutputDifferences.between(actual, candidate).rows

    assert Enum.any?(rows, &(&1.label == "Entry order / identities"))
    assert Enum.any?(rows, &(&1.label == "Action order / identities"))
    assert Enum.count(rows, &String.starts_with?(&1.label, "Removed action")) == 2
    assert Enum.count(rows, &String.starts_with?(&1.label, "Added action")) == 1
  end

  test "a singular effect retains its identity when the amount changes" do
    actual = output([], [%{"type" => "authorize", "key" => 4, "amount" => 50}])
    changed = output([], [%{"type" => "authorize", "key" => 4, "amount" => 49}])
    rows = OutputDifferences.between(actual, changed).rows

    assert [%{label: "authorize action 4 · amount", delta: " (-1¢)"}] = rows
  end

  test "integer identities are displayed as numbers, never character lists" do
    actual = output([entry(11, 100, "voiding")])
    alternative = output([])
    %{rows: rows} = OutputDifferences.between(actual, alternative)

    assert %{before: "[11]", after: "[]"} =
             Enum.find(rows, &(&1.label == "Entry order / identities"))
  end
  test "one structured projection drives exact field markers, counts and typed IDs" do
    before = output([entry(11, 100, "voiding")])
    after_value =
      output([entry(11, 99, "voided")])
      |> put_in(["after", "used_amount"], 99)
      |> put_in(["after", "used_holds"], 0)
      |> Map.put("result", "voided")

    result = OutputDifferences.between(before, after_value)
    assert result.field_count == 5
    assert result.other_count == 0
    assert result.ghosts == []
    assert %{kind: :field_change, before_value: 100, after_value: 99, signed: -1,
             unit: :cents, path: ["after", "used_amount"]} =
             OutputDifferences.at(result, ["after", "used_amount"])

    assert %{before_path: ["after", "entries", 0, "amount"],
             after_path: ["after", "entries", 0, "amount"],
             occurrence: %{identity: 11, before_index: 0, after_index: 0}} =
             OutputDifferences.at(result, ["after", "entries", 0, "amount"])

    assert OutputDifferences.annotation(OutputDifferences.at(result, ["result"])) ==
             "was Cancellation requested"
    assert OutputDifferences.at(result, ["after", "entries", 0, "key"]) == nil
  end

  test "reordered unique identities use exact before and after occurrence indexes" do
    a = entry(11, 40, "reserved")
    b = entry(12, 60, "voiding")
    before = output([a, b])
    after_value = output([%{b | "amount" => 55}, a])
    result = OutputDifferences.between(before, after_value)

    assert %{before_path: ["after", "entries", 1, "amount"],
             after_path: ["after", "entries", 0, "amount"],
             signed: -5} = OutputDifferences.at(result, ["after", "entries", 0, "amount"])
    assert Enum.any?(result.rows, &(&1.kind == :order_change))
    assert result.field_count == 1
    assert result.other_count == 1
  end

  test "a missing entry is an annotation only, never a proposed member or total" do
    original = output([entry(11, 100, "voiding")])
    next = output([], [], %{"used_amount" => 0, "used_holds" => 0})
    result = OutputDifferences.between(original, next)

    assert [%{entry: %{"key" => 11}, before_index: 0}] = result.ghosts
    assert next["after"]["entries"] == []
    assert Enum.any?(result.rows, &(&1.kind == :removed))
    assert result.other_count == 2
  end

  test "repeated identities do not acquire an unsafe field-to-field annotation" do
    actual = output([entry(11, 60, "reserved"), entry(11, 40, "voiding")])
    candidate = output([entry(11, 100, "voided")])
    result = OutputDifferences.between(actual, candidate)

    assert result.field_count == 0
    assert Enum.any?(result.rows, &(&1.kind == :correspondence))
    assert OutputDifferences.at(result, ["after", "entries", 0, "status"]) == nil
    assert result.ghosts == []
    assert Enum.count(result.rows, &(&1.kind == :removed)) == 2
    assert Enum.count(result.rows, &(&1.kind == :added)) == 1
  end

  test "effect multiplicity prevents claiming that duplicate actions are the same" do
    action = %{"type" => "authorize", "key" => 12, "amount" => 50}
    result = OutputDifferences.between(output([], [action, action]), output([], [action]))
    assert result.field_count == 0
    assert Enum.count(result.rows, &(&1.kind == :removed)) == 2
    assert Enum.count(result.rows, &(&1.kind == :added)) == 1
    assert Enum.any?(result.rows, &(&1.kind == :correspondence))
  end

end
