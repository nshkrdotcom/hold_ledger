defmodule HoldLedgerReviewWeb.LearningTest do
  use ExUnit.Case, async: false

  alias HoldLedgerReview.{Config, Trace}
  alias HoldLedgerReviewWeb.Learning

  test "the story starts empty and follows actual request, dispatch and timeout outputs" do
    before_files = trace_files()
    assert {:ok, [start, request, dispatch, timeout, refused]} = Learning.walkthrough()

    assert start.index == 0

    assert start.ledger == %{
             "amount_limit" => 100,
             "hold_limit" => 2,
             "used_amount" => 0,
             "used_holds" => 0,
             "entries" => []
           }

    assert start.output == nil
    assert request.before == start.ledger
    assert request.output["result"] == "admitted"
    assert request.ledger["used_amount"] == 100
    assert request.ledger["used_holds"] == 1
    assert request.ledger["entries"] == [%{"key" => 11, "amount" => 100, "status" => "reserved"}]

    assert dispatch.output["result"] == "dispatched"
    assert dispatch.output["effects"] == [%{"type" => "authorize", "key" => 11, "amount" => 100}]
    assert hd(dispatch.ledger["entries"])["status"] == "sent"
    assert timeout.before == dispatch.ledger
    assert timeout.output["result"] == "marked_unknown"
    assert timeout.ledger["used_amount"] == 100
    assert timeout.ledger["used_holds"] == 1
    assert timeout.ledger["entries"] == [%{"key" => 11, "amount" => 100, "status" => "unknown"}]
    assert refused.event == %{"type" => "request", "key" => 12, "amount" => 100}
    assert refused.output["result"] == "insufficient_amount"
    assert refused.ledger == timeout.ledger
    assert trace_files() == before_files
  end

  test "opening a moment saves only the selected prefix and leaves its last event selected" do
    assert {:ok, %{doc: doc, slug: "po_b2"}} = Learning.open_moment(3)
    assert length(doc["steps"]) == 3
    assert Enum.map(doc["steps"], & &1["event"]["type"]) == ["request", "dispatch", "timeout"]
    last = List.last(doc["steps"])
    assert last["event"] == %{"type" => "timeout", "key" => 11, "amount" => nil}
    assert last["output"]["result"] == "marked_unknown"
    assert last["after"]["used_amount"] == 100
    assert Enum.all?(doc["steps"], &(&1["origin"] == "computed"))
    assert {:ok, ^doc} = Trace.get(doc["id"])
  end

  test "every story prefix reopens with exactly its selected events and output" do
    assert {:ok, moments} = Learning.walkthrough()

    for moment <- moments do
      assert {:ok, %{doc: doc, slug: slug}} = Learning.open_moment(moment.index)
      assert slug == moment.claim
      assert length(doc["steps"]) == moment.index
      assert {:ok, ^doc} = Trace.get(doc["id"])

      expected = moments |> Enum.take(moment.index + 1) |> tl()
      assert Enum.map(doc["steps"], & &1["event"]) == Enum.map(expected, & &1.event)

      if moment.index > 0 do
        assert List.last(doc["steps"])["after"] == moment.ledger
        assert List.last(doc["steps"])["output"] == moment.output
      end
    end
  end

  test "the starting moment opens an empty account without inventing an event" do
    assert {:ok, %{doc: doc, slug: "po_i"}} = Learning.open_moment(0)
    assert doc["steps"] == []
    assert doc["initial"]["used_amount"] == 0
    assert doc["initial"]["used_holds"] == 0
  end

  test "an invalid moment cannot create a review session" do
    before_files = trace_files()
    assert {:error, :unknown_moment} = Learning.open_moment(-1)
    assert {:error, :unknown_moment} = Learning.open_moment(5)
    assert {:error, :unknown_moment} = Learning.open_moment("3")
    assert trace_files() == before_files
  end

  test "M7 shows its actual patch and keeps the effects claim as its target" do
    assert {:ok, selected} = Learning.mutation("M7")
    assert selected.example["target_slug"] == "po_b3"
    assert selected.example["before"] == "{1000, 3, 300, 1, [{11, 300, :authorized}]}"
    assert selected.patch.path == "mutants/07_void_effect/mutant.patch"
    assert selected.patch.text =~ "-         :voiding, [{:void, key}]}"
    assert selected.patch.text =~ "+         :voiding, []}"
    assert {:error, :unknown_mutation} = Learning.mutation("P08")
    assert {:error, :unknown_mutation} = Learning.mutation("../../source")
  end

  test "the translation reading separates an actual Elixir excerpt from a checked-in theorem" do
    assert {:ok, translation} = Learning.translation()
    assert translation.implementation.path == "lib/hold_ledger/ledger.ex"
    assert translation.implementation.text =~ "def request("
    assert translation.eligibility.path == "lib/hold_ledger/spec.ex"
    assert translation.eligibility.text =~ "amount <= amount_limit - used_amount"
    assert translation.reading["contract"]["requires"] =~ "request_eligible?"
    assert hd(translation.reading["declarations"])["path"] == "test/support/lean/Request.lean"

    assert hd(translation.reading["declarations"])["status"] ==
             "source_declaration_not_elaborated_evidence"

    assert translation.implementation.sha256 ==
             HoldLedgerReview.Anchor.sha(
               File.read!(Path.join(Config.root(), translation.implementation.path))
             )
  end

  test "missing generated artifacts are unavailable rather than replaced by supplied proof text" do
    assert Learning.generated_source(%{
             "slug" => "po_a2",
             "focused" => %{"status" => "missing_or_stale"},
             "declarations" => [%{"text" => "theorem source is not a generated definition"}]
           }) == nil
  end

  test "an unavailable checkout returns errors without fabricated story or translation data" do
    root = Config.root()

    Application.put_env(
      :hold_ledger_review_web,
      :ledger_root,
      Path.join(root, "missing-checkout")
    )

    on_exit(fn -> Application.put_env(:hold_ledger_review_web, :ledger_root, root) end)

    assert {:error, _} = Learning.walkthrough()
    assert {:error, _} = Learning.translation()
    assert {:error, _} = Learning.open_moment(1)
  end

  defp trace_files do
    :hold_ledger_review_web
    |> Application.fetch_env!(:review_store_dir)
    |> Path.join("trace-*.json")
    |> Path.wildcard()
    |> Enum.sort()
  end
end
