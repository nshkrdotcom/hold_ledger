defmodule HoldLedgerReview.ProofReadingLinksTest do
  use ExUnit.Case, async: true
  alias HoldLedgerReview.ProofReading
  alias HoldLedgerReview.ProofReading.Links

  @source "defmodule Example do\n  def eligible(s), do: s > 0\nend\n"
  @link %{
    "id" => "test-condition",
    "phase" => "requires",
    "expression" => "s > 0",
    "source_path" => "law.ex",
    "steps" => [0],
    "relation" => "A reviewed source-reading relationship"
  }
  @declaration %{
    "status" => "source_declaration_not_elaborated_evidence",
    "sha256" => "lean-sha",
    "path" => "law.lean"
  }

  defp validate(link \\ @link, source_sha \\ "source-sha", steps \\ [%{"line" => 4}]) do
    Links.validate(
      [link],
      %{"law.ex" => @source},
      %{"law.ex" => source_sha, "law.lean" => "lean-sha"},
      @declaration,
      steps,
      %{"law.ex" => "source-sha"}
    )
  end

  test "source review binds structural clause and unique Lean anchor" do
    assert [%{"availability" => "available"} = link] = validate()

    reading = %{"connections" => [link], "source_generation" => "generation-A"}

    observed = %{
      "explanation" => %{
        "bindings" => [%{"requires" => %{"expression" => "s > 0", "children" => []}}]
      }
    }

    assert %{links: [%{"path" => "", "phase" => "requires", "binding" => 0}]} =
             Links.project(reading, observed, 0, "candidate")
  end

  test "stale Elixir digest, missing Lean passage and ambiguous anchors invalidate" do
    assert [%{"availability" => "Reviewed Elixir source missing or changed"}] =
             validate(@link, "stale-sha")

    assert [%{"availability" => "Lean anchor missing or ambiguous"}] =
             validate(@link, "source-sha", [%{"line" => nil}])

    assert [%{"availability" => "Elixir clause missing or ambiguous in reviewed AST"}] =
             validate(Map.put(@link, "expression", "s < 0"))
  end

  test "ambiguous observed correspondences are unavailable rather than guessed" do
    [%{"availability" => "available"} = link] = validate()

    reading = %{"connections" => [link], "source_generation" => "generation-A"}

    node = %{
      "expression" => "s > 0",
      "children" => [%{"expression" => "s > 0", "children" => []}]
    }

    observed = %{"explanation" => %{"bindings" => [%{"requires" => node}]}}
    assert %{links: [], unavailable: [_]} = Links.project(reading, observed, 0, "actual")
  end

  test "initial reviewed connections exist without altering unsupported catalog entries" do
    for slug <- ~w(po_a2 po_b1_timeout po_exposure_retain) do
      assert {:ok, reading} = ProofReading.document(slug)
      assert reading["connections"] != []
      assert Enum.any?(reading["connections"], &(&1["availability"] == "available"))
    end

    assert {:ok, other} = ProofReading.document("po_a4_duplicate")
    assert other["connections"] == []
  end
end
