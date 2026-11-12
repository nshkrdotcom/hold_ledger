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

  test "batch postludes preserve source order and reject unsupported overrides" do
    first = %Lynx.Lean{
      source: "theorem first : True := by trivial",
      file: "first.lean",
      span: 1,
      indentation: 0
    }

    second = %Lynx.Lean{
      source: "theorem second : True := by trivial",
      file: "second.lean",
      span: {2, 1},
      indentation: 0
    }

    defaults = [
      termination_suffixes: %{},
      cutoffs: MapSet.new(),
      dynamic: MapSet.new(),
      preludes: [],
      postludes: []
    ]

    assert [^first, ^second] =
             HoldLedger.ProofCase.batch_postludes!([
               {First, Keyword.put(defaults, :postludes, [first])},
               {Second, Keyword.put(defaults, :postludes, [second])}
             ])

    for override <- [
          [unknown: []],
          [cutoffs: MapSet.new([{:erlang, :abs, 1}])],
          [termination_suffixes: %{{:foo, :bar, 0} => :bad}],
          [dynamic: MapSet.new([{:erlang, :apply, 2}])],
          [preludes: [first]],
          [postludes: ["not Lean"]],
          [postludes: [%Lynx.Lean{source: "", file: "first.lean", span: 1, indentation: 0}]]
        ] do
      assert_raise ArgumentError, fn ->
        HoldLedger.ProofCase.batch_postludes!([{Example, Keyword.merge(defaults, override)}])
      end
    end

    assert_raise ArgumentError, fn ->
      HoldLedger.ProofCase.batch_postludes!([{Example, [postludes: [], postludes: []]}])
    end

    assert_raise ArgumentError, fn ->
      HoldLedger.ProofCase.batch_postludes!([
        {Example,
         Keyword.put(defaults, :postludes, [
           %Lynx.Lean{first | source: "module\ntheorem bogus : True := by trivial"}
         ])}
      ])
    end
  end

  test "postlude imports shared support after translated definitions, before laws" do
    files = [
      %{"module" => "Elixir.Example", "imports" => []},
      %{"module" => "Erlang.postlude", "imports" => ["Elixir.Example"]},
      %{"module" => "Elixir.Example.laws", "imports" => ["Elixir.Example", "Erlang.postlude"]}
    ]

    support = [%{"module" => "HoldLedgerProof.Lookup", "imports" => ["Elixir.Example"]}]

    [generated, helper, postlude, laws] =
      HoldLedger.ProofCase.attach_support(files, support, %{
        "Erlang.postlude" => ["HoldLedgerProof.Lookup"],
        "Elixir.Example.laws" => ["HoldLedgerProof.Lookup"]
      })

    assert Enum.map([generated, helper, postlude, laws], & &1["module"]) == [
             "Elixir.Example",
             "HoldLedgerProof.Lookup",
             "Erlang.postlude",
             "Elixir.Example.laws"
           ]

    assert postlude["imports"] == ["Elixir.Example", "HoldLedgerProof.Lookup"]
    assert laws["imports"] == ["Elixir.Example", "Erlang.postlude", "HoldLedgerProof.Lookup"]

    assert_raise ArgumentError, fn ->
      HoldLedger.ProofCase.attach_support(
        files,
        [
          %{"module" => "HoldLedgerProof.Bad", "imports" => ["Erlang.postlude"]}
        ],
        %{}
      )
    end
  end

  test "postlude and support source changes invalidate transitive cache keys" do
    definitions = [%{"module" => "Elixir.Example", "imports" => [], "contents" => ["source"]}]

    support = [
      %{
        "module" => "HoldLedgerProof.Lookup",
        "imports" => ["Elixir.Example"],
        "contents" => ["lemma"]
      }
    ]

    postlude = %{
      "module" => "Erlang.postlude",
      "imports" => ["Elixir.Example"],
      "contents" => ["local theorem"]
    }

    law = %{
      "module" => "Elixir.Example.laws",
      "imports" => ["Elixir.Example", "Erlang.postlude"],
      "contents" => ["law"]
    }

    files = definitions ++ [postlude, law]

    assembled =
      HoldLedger.ProofCase.attach_support(files, support, %{
        "Erlang.postlude" => ["HoldLedgerProof.Lookup"],
        "Elixir.Example.laws" => ["HoldLedgerProof.Lookup"]
      })

    keys = fn fs -> Enum.map(HoldLedger.ProofCase.cache_files(fs), & &1["cache_key"]) end

    assert Enum.map(assembled, & &1["module"]) == [
             "Elixir.Example",
             "HoldLedgerProof.Lookup",
             "Erlang.postlude",
             "Elixir.Example.laws"
           ]

    assert keys.(assembled) == keys.(assembled)
    changed_support = List.update_at(assembled, 1, &Map.put(&1, "contents", ["changed lemma"]))

    [same_definition, changed_helper, changed_postlude, changed_law] =
      Enum.zip_with(keys.(assembled), keys.(changed_support), &(&1 != &2))

    refute same_definition
    assert changed_helper and changed_postlude and changed_law

    changed_postlude =
      List.update_at(assembled, 2, &Map.put(&1, "contents", ["changed local theorem"]))

    assert Enum.zip_with(keys.(assembled), keys.(changed_postlude), &(&1 != &2)) == [
             false,
             false,
             true,
             true
           ]
  end

  test "adapter rejects duplicate module identity, even if the source is different" do
    generated = [
      %{"module" => "Elixir.Example", "imports" => []},
      %{"module" => "Erlang.postlude", "imports" => []}
    ]

    for support <- [
          [%{"module" => "Elixir.Example", "imports" => []}],
          [
            %{"module" => "HoldLedgerProof.Dup", "imports" => []},
            %{"module" => "HoldLedgerProof.Dup", "imports" => []}
          ]
        ] do
      assert_raise ArgumentError, fn ->
        HoldLedger.ProofCase.attach_support(generated, support, %{})
      end
    end
  end

  test "L1 migrated proof has one postlude owner, unchanged contract" do
    lookup = File.read!("test/support/lean/Lookup.lean")
    group = File.read!("test/laws/l1_find_test.exs")

    refute lookup =~ "theorem «l1_find/2»"
    assert lookup =~ "theorem «po_a4_duplicate/4»"
    assert group =~ "theorem l1_contract (entries key : Lynx.Term)"
    assert group =~ "exact HoldLedgerProof.Postludes.L1Find.l1_contract entries key requires"
    assert group =~ "requires: Spec.proper_entries?(entries) and Spec.unique_keys?(entries)"
    assert group =~ "expects: Ledger.find(entries, key) == Spec.lookup(entries, key)"
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
