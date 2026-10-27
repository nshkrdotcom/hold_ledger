defmodule HoldLedger.ClaimSourceParityTest do
  use ExUnit.Case, async: true

  # Run this in the ROOT Mix project, whose test support loads ProofCase/Lynx.
  # The companion deliberately never imports ProofCase or Lynx at runtime.
  @companion Path.expand("../apps/review_web/lib/hold_ledger_review", __DIR__)
  Code.require_file(Path.join(@companion, "anchor.ex"))
  Code.require_file(Path.join(@companion, "claims/source.ex"))

  test "every registered Elixir DSL declaration has the same head, requires and expects as ProofCase" do
    root = File.cwd!()
    catalog = root |> Path.join("verification/laws.json") |> File.read!() |> :json.decode()

    for law <- catalog["laws"], law["kind"] != "lean" do
      file = law["file"]
      assert [{head, options}] = HoldLedger.ProofCase.law_declarations(Path.join(root, file))
      assert {:ok, extracted} = HoldLedgerReview.Claims.Source.declaration(root, law)
      assert {name, _, args} = head
      assert Atom.to_string(name) == law["slug"]
      assert length(args) == law["arity"]
      assert extracted.formals == Enum.map(args, &elem(&1, 0))
      assert Macro.to_string(extracted.requires) ==
               Macro.to_string(Keyword.get(options, :requires, true))
      assert Macro.to_string(extracted.expects) ==
               Macro.to_string(Keyword.fetch!(options, :expects))
      assert extracted.source_sha256 ==
               (Path.join(root, file) |> File.read!() |> HoldLedgerReview.Anchor.sha())
    end
  end
end
