defmodule HoldLedgerReview.ReviewWorkspaceTest do
  use ExUnit.Case, async: false
  alias HoldLedgerReview.{Contrast, ReviewWorkspace}

  test "example applicability is separate from real admission" do
    for {amount, baseline, proposal} <- [
          {99, true, true},
          {100, true, false},
          {101, false, false}
        ] do
      {:ok, doc} = Contrast.create("po_a2")
      step = List.last(doc["steps"])
      input = put_in(step, ["event", "amount"], amount)
      result = ReviewWorkspace.example(input)
      assert result.baseline == baseline and result.proposal == proposal
      assert result.provenance == "illustrated proposal"
    end
  end

  test "assumption contrast uses current amount and identity" do
    {:ok, doc} = Contrast.create("po_exposure_retain")
    step = List.last(doc["steps"])

    output =
      step["output"]
      |> put_in(["after", "entries", Access.at(0), "amount"], 37)
      |> put_in(["after", "used_amount"], 37)

    state = output["after"]
    comparison = ReviewWorkspace.premise(state, 1, false)
    assert comparison.amount == 37
    assert comparison.local == 0 and comparison.remote == 37
    refute comparison.covered
    assert ReviewWorkspace.premise(state, 77, false).status == "not_applicable"
  end

  test "pair rows require exact snapshot and complete input identity" do
    {:ok, doc} = Contrast.create("po_a2")
    step = List.last(doc["steps"])
    data = %{"before" => step["before"], "event" => step["event"], "candidate" => step["output"]}

    witness = %{
      "before" => data["before"],
      "event" => data["event"],
      "output" => data["candidate"],
      "follow_on" => nil
    }

    result = %{
      "claims" => %{
        "po_a2" => %{
          "bindings" => [
            %{"requires" => true, "post_candidate" => true},
            %{"requires" => false, "post_candidate" => nil}
          ]
        }
      },
      "evaluation" => %{"actual" => %{"result" => "admitted"}}
    }

    attempt = %{
      "snapshot_id" => "base",
      "input_digest" => HoldLedgerReview.Canonical.digest(witness),
      "status" => "succeeded",
      "result" => result
    }

    package = %{
      "baseline" => %{"snapshot_id" => "base"},
      "proposal" => %{"snapshot_id" => "other"},
      "replay_attempts" => [attempt]
    }

    [baseline, proposal] = ReviewWorkspace.replay_rows(package, data, "po_a2")
    assert baseline.requires and baseline.actual == "admitted"
    assert baseline.candidate == nil
    assert proposal.requires == nil and proposal.actual == nil
    changed = put_in(data, ["event", "amount"], 99)
    assert Enum.all?(ReviewWorkspace.replay_rows(package, changed, "po_a2"), &(&1.actual == nil))
  end
end
