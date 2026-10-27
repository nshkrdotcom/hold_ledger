defmodule HoldLedger.ClaimSourceParityTest do
  use ExUnit.Case, async: true

  alias HoldLedger.ProofCase
  alias HoldLedgerReview.Claims.Source

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
      assert [{head, options}] = ProofCase.law_declarations(Path.join(root, file))
      assert {:ok, extracted} = Source.declaration(root, law)
      assert {name, _, args} = head
      assert Atom.to_string(name) == law["slug"]
      assert length(args) == law["arity"]
      assert extracted.formals == Enum.map(args, &elem(&1, 0))

      assert semantic_ast(extracted.requires) ==
               semantic_ast(Keyword.get(options, :requires, true))

      assert semantic_ast(extracted.expects) ==
               semantic_ast(Keyword.fetch!(options, :expects))

      assert extracted.source_sha256 ==
               Path.join(root, file) |> File.read!() |> HoldLedgerReview.Anchor.sha()
    end
  end

  # Source extraction retains token/column metadata; ProofCase does not.
  # Compare expression structure and literals without formatter metadata.
  defp semantic_ast(ast) do
    Macro.prewalk(ast, fn
      {name, meta, args} when is_list(meta) -> {name, [], args}
      node -> node
    end)
  end
end
