defmodule HoldLedgerReviewWeb.TraceForkTest do
  use ExUnit.Case, async: true
  alias HoldLedgerReviewWeb.TraceFork

  defp step(id, parent, attrs \\ %{}) do
    Map.merge(%{"id" => id, "parent" => parent, "event" => %{"type" => "request"}}, attrs)
  end

  defp trace do
    %{
      "steps" => [
        step("setup", "start"),
        step("code", "setup"),
        step("alternative", "setup", %{"challenge_of" => "code", "origin" => "hypothetical"}),
        step("code-next", "code"),
        step("alternative-next", "alternative"),
        step("code-other", "code")
      ]
    }
  end

  test "projects two real paths from their common history" do
    fork = TraceFork.project(trace(), "alternative-next")
    assert Enum.map(fork.shared, & &1["id"]) == ["setup"]
    assert Enum.map(fork.code, & &1["id"]) == ["code", "code-other"]
    assert Enum.map(fork.alternative, & &1["id"]) == ["alternative", "alternative-next"]
    assert fork.original_id == "code"
    assert fork.alternative_id == "alternative"
  end

  test "prefers a selected original continuation over a newer sibling" do
    fork = TraceFork.project(trace(), "code-next")
    assert Enum.map(fork.code, & &1["id"]) == ["code", "code-next"]
    assert Enum.map(fork.alternative, & &1["id"]) == ["alternative", "alternative-next"]
  end

  test "no fork is rendered without a recorded alternative" do
    assert TraceFork.project(%{"steps" => [step("code", "start")]}, "code") == nil
    assert TraceFork.project(%{"steps" => []}, "start") == nil
  end

  test "selects the fork containing the cursor when multiple alternatives exist" do
    doc =
      Map.update!(trace(), "steps", fn steps ->
        steps ++ [step("alternative-two", "setup", %{"challenge_of" => "code"})]
      end)

    # The latest branch is the default, but a selected path must remain visible.
    assert TraceFork.project(doc, "code").alternative_id == "alternative-two"
    assert TraceFork.project(doc, "alternative-next").alternative_id == "alternative"
  end
end
