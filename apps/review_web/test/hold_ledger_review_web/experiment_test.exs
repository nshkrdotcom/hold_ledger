defmodule HoldLedgerReviewWeb.ExperimentTest do
  use HoldLedgerReviewWeb.ConnCase, async: false
  alias HoldLedgerReview.Trace
  alias HoldLedgerReviewWeb.Experiment

  defp request(key), do: %{"type" => "request", "key" => key, "amount" => 100}

  defp run(exp, event) do
    Experiment.run(exp, %{
      "kind" => "append",
      "parent" => Experiment.cursor(exp),
      "event" => event
    })
  end

  test "multiple original-evaluator steps stay unsaved until explicitly saved" do
    {:ok, doc} = Trace.create("ledger", 100, 2)
    {:ok, exp} = run(Experiment.new(doc, "start"), request(11))
    {:ok, exp} = run(exp, %{"type" => "dispatch", "key" => 11, "amount" => nil})
    {:ok, exp} = run(exp, %{"type" => "timeout", "key" => 11, "amount" => nil})
    assert {:ok, ^doc} = Trace.get(doc["id"])

    assert List.last(exp.doc["steps"])["after"]["entries"] == [
             %{"key" => 11, "amount" => 100, "status" => "unknown"}
           ]

    assert {:ok, saved} = Experiment.save(doc, exp)
    assert length(saved["steps"]) == 3
    assert Enum.map(saved["steps"], & &1["id"]) == Enum.map(exp.doc["steps"], & &1["id"])
  end

  test "an alternative and its consequences retain original hypothetical lineage" do
    {:ok, doc} = Trace.create("ledger", 100, 2)
    {:ok, exp} = run(Experiment.new(doc, "start"), request(11))
    step = List.last(exp.doc["steps"])

    output =
      step["output"]
      |> put_in(["after", "entries"], [%{"key" => 11, "amount" => 100, "status" => "voided"}])
      |> put_in(["after", "used_amount"], 0)
      |> put_in(["after", "used_holds"], 0)

    {:ok, exp} =
      Experiment.run(exp, %{
        "kind" => "candidate",
        "parent" => Experiment.cursor(exp),
        "output" => output
      })

    {:ok, exp} = run(exp, request(12))
    assert List.last(exp.doc["steps"])["origin"] == "hypothetical_continuation"
    assert List.last(exp.doc["steps"])["output"]["result"] == "admitted"
    assert {:ok, ^doc} = Trace.get(doc["id"])
    assert {:ok, saved} = Experiment.save(doc, exp)
    assert Enum.at(saved["steps"], 1)["origin"] == "hypothetical"
  end

  test "a stale saved revision cannot overwrite another reviewer's note" do
    {:ok, doc} = Trace.create()
    {:ok, exp} = run(Experiment.new(doc, "start"), request(11))

    {:ok, newer} =
      Trace.command(doc["id"], doc["revision"], Trace.token(), %{
        "kind" => "note",
        "step" => "start",
        "text" => "Independent review",
        "disposition" => "concern"
      })

    assert {:error, :revision_conflict, ^doc, remaining} = Experiment.save(doc, exp)
    assert length(remaining.pending) == 1
    assert {:ok, ^newer} = Trace.get(doc["id"])
  end

  test "a partial save retains its unsaved suffix and can resume without duplicating steps" do
    {:ok, doc} = Trace.create()
    {:ok, exp} = run(Experiment.new(doc, "start"), request(11))
    {:ok, exp} = run(exp, %{"type" => "dispatch", "key" => 11, "amount" => nil})

    writer = fn id, revision, token, action ->
      if revision == doc["revision"],
        do: Trace.command(id, revision, token, action),
        else: {:error, :revision_conflict}
    end

    assert {:error, :revision_conflict, partial, remaining} = Experiment.save(doc, exp, writer)
    assert length(partial["steps"]) == 1
    assert length(remaining.pending) == 1
    assert {:ok, saved} = Experiment.save(partial, remaining)
    assert length(saved["steps"]) == 2
    assert List.last(saved["steps"])["output"]["result"] == "dispatched"
  end

  test "source drift and unsupported commands cannot enter an experiment" do
    {:ok, doc} = Trace.create()
    stale = put_in(doc, ["identity", "source"], String.duplicate("0", 64))
    assert {:error, :stale_source} = run(Experiment.new(stale, "start"), request(11))

    assert {:error, :unsupported_experiment_action} =
             Experiment.run(Experiment.new(doc, "start"), %{"kind" => "note"})

    assert {:ok, ^doc} = Trace.get(doc["id"])
  end
end
