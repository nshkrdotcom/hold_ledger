defmodule HoldLedger.ProofCaseTest do
  use ExUnit.Case, async: true

  test "contracts are extracted from actual law declarations without proof bodies" do
    declarations = HoldLedger.ProofCase.law_declarations("test/laws/l1_find_test.exs")
    assert [{{:l1_find, _, args}, opts}] = declarations
    assert length(args) == 2
    assert Keyword.has_key?(opts, :requires)
    assert Keyword.has_key?(opts, :expects)
    assert function_exported?(HoldLedger.ProofContracts, :"l1_find:requires", 2)
  end

  test "missing, skipped and empty law results fail closed" do
    module = HoldLedger.Laws.Example
    laws = [example: 1]

    assert_raise ExUnit.AssertionError, fn ->
      HoldLedger.ProofCase.validate_reports!([], module, laws)
    end

    report = %{
      module: "Elixir.HoldLedger.Laws.Example.laws",
      status: :ok,
      theorems: [%{name: "example/1"}]
    }

    assert :ok = HoldLedger.ProofCase.validate_reports!([report], module, laws)

    for changed <- [
          %{report | status: :skipped},
          %{report | theorems: []},
          %{report | theorems: [%{name: "different/1"}]}
        ] do
      assert_raise ExUnit.AssertionError, fn ->
        HoldLedger.ProofCase.validate_reports!([changed], module, laws)
      end
    end
  end

  test "shared support imports each dependency once before its users" do
    files = HoldLedger.ProofCase.support_files(po_s: 2, po_c1: 2)
    names = Enum.map(files, & &1["module"])
    assert length(names) == length(Enum.uniq(names))

    for {file, index} <- Enum.with_index(files),
        dependency <- file["imports"],
        String.starts_with?(dependency, "HoldLedgerProof.") do
      assert Enum.find_index(names, &(&1 == dependency)) < index
    end

    assert "HoldLedgerProof.Step" in names
    assert "HoldLedgerProof.Replay" in names
    refute "HoldLedgerProof.Uncertainty" in names
    refute Enum.any?(files, &Map.has_key?(&1, "cache_key"))
  end

  test "generated B5 contracts retain loose numeric equality and arbitrary events" do
    for status <- [:declined, :voided] do
      state = {100, 1, 0, 0, [{1, 100, status}]}

      requires =
        Function.capture(HoldLedger.ProofContracts, String.to_atom("po_b5_#{status}:requires"), 4)

      assert requires.(state, {:unexpected, %{anything: true}}, 1.0, 100.0)
    end
  end

  test "development cache keys change when a shared source or its dependency changes" do
    files = [
      %{"module" => "Core", "imports" => [], "contents" => ["original"]},
      %{"module" => "Law", "imports" => ["Core"], "contents" => ["proof"]}
    ]

    original = HoldLedger.ProofCase.cache_files(files)

    changed =
      HoldLedger.ProofCase.cache_files([
        put_in(hd(files)["contents"], ["changed"]),
        List.last(files)
      ])

    assert Enum.zip_with(original, changed, &(&1["cache_key"] != &2["cache_key"])) == [true, true]
    assert original == HoldLedger.ProofCase.cache_files(files)
  end

  test "native anchors resolve full theorem identities and reject source injection" do
    [anchor] =
      HoldLedger.ProofCase.native_anchors([
        %{"module" => "HoldLedgerProof.Example", "theorems" => ["HoldLedgerProof.Example.claim"]}
      ])

    assert hd(anchor["preludes"])["source"] =~
             "abbrev checked_0 := @HoldLedgerProof.Example.claim"

    assert anchor["imports"] == ["HoldLedgerProof.Example"]

    assert_raise ArgumentError, fn ->
      HoldLedger.ProofCase.native_anchors([
        %{"module" => "HoldLedgerProof.Example", "theorems" => ["Other.claim\nmalformed"]}
      ])
    end
  end
end
