defmodule HoldLedgerReview.ConditionOutlineTest do
  use ExUnit.Case, async: true
  alias HoldLedgerReview.{Anchor, ConditionOutline, Config, ProofReading}

  defp node(expression, value, children \\ [], status \\ "evaluated") do
    %{"expression" => expression, "value" => value, "status" => status,
      "children" => children}
  end

  test "reviewed grouping requires exact source bytes and reviewed digests" do
    path = "test/laws/po_exposure_retain_test.exs"
    source = File.read!(Path.join(Config.root(), path))
    sha = Anchor.sha(source)
    group = %{"id" => "representation", "title" => "Amount representation",
              "phase" => "requires", "source_path" => path,
              "expressions" => ["is_integer(amount)"], "collapse_satisfied" => true}

    assert [^group] = ConditionOutline.validate([group], %{path => source}, %{path => sha}, %{path => sha})
    assert [] == ConditionOutline.validate([group], %{path => source}, %{path => sha},
                    %{path => String.duplicate("0", 64)})
    assert [] == ConditionOutline.validate([
      %{group | "expressions" => ["invented_source_condition(key)"]}
    ], %{path => source}, %{path => sha}, %{path => sha})
  end

  test "separate observations count true, false and unevaluated without inferring passed children" do
    domain = node("amount > 0", false)
    nested = node("unknown_guard()", nil,
      [node("deep_guard()", nil, [], "not_evaluated")], "not_evaluated")
    root = node("amount > 0 and unknown_guard()", false, [domain, nested])
    group = %{"id" => "domain", "title" => "Positive amounts", "phase" => "requires",
              "source_path" => "approved", "expressions" => ["amount > 0"],
              "collapse_satisfied" => true}

    assert [first, skipped] = ConditionOutline.project(root, "requires", [group])
    assert first.counts == %{"true" => 0, "false" => 1, "not_evaluated" => 0, "unavailable" => 0}
    assert first.attention? and not first.collapsed?
    assert first.observations |> hd() |> Map.get(:path) == [0]
    assert skipped.counts["not_evaluated"] == 1
    assert skipped.collapsed? and skipped.attention?
    assert skipped.observations |> hd() |> Map.get(:path) == [1]
  end

  test "source comparisons flag changed successful hypotheses even without a counterexample" do
    root = node("amount > 0", true)
    group = %{"id" => "domain", "title" => "Positive amounts", "phase" => "requires",
              "source_path" => "lib/hold_ledger/spec.ex", "expressions" => ["amount > 0"],
              "collapse_satisfied" => true}
    [ordinary] = ConditionOutline.project(root, "requires", [group])
    [changed] = ConditionOutline.project(root, "requires", [group], ["lib/hold_ledger/spec.ex"])
    assert ordinary.collapsed?
    refute changed.collapsed?
    assert changed.changed_source? and changed.attention?
    assert changed.counts["true"] == 1
  end

  test "generic fallback never implies unreviewed OR, NOT or helper nodes are folded away" do
    root = node("a or not b", true, [node("a", false), node("not b", true,
      [node("b", false)])])
    assert [%{id: "generic", observations: [%{node: ^root, path: []}]}] =
             ConditionOutline.project(root, "requires", [])
    assert root["children"] |> Enum.at(1) |> Map.get("expression") == "not b"
  end

  test "source-bound reading exposes the same condition outlines to command clients" do
    {:ok, reading} = ProofReading.document("po_a2")
    assert reading["reading_status"] == "current"
    assert Enum.any?(reading["condition_groups"], &(&1["id"] == "eligibility"))
    {:ok, unsupported} = ProofReading.document("po_a4_duplicate")
    assert unsupported["condition_groups"] == []
  end
end
