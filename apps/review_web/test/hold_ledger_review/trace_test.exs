defmodule HoldLedgerReview.TraceTest do
  use ExUnit.Case, async: false
  alias HoldLedger.{Exposure, Ledger, Spec}
  alias HoldLedgerReview.{Canonical, Claims, TermCodec, Trace}

  defp apply_event(doc, parent, event) do
    {:ok, json} =
      if doc["mode"] == "ledger",
        do: TermCodec.encode_event(event),
        else: TermCodec.encode_exposure_event(event)

    Trace.command(doc["id"], doc["revision"], Trace.token(), %{
      "kind" => "append",
      "parent" => parent,
      "event" => json
    })
  end

  defp walk(doc, events) do
    Enum.reduce(events, {doc, "start"}, fn event, {doc, parent} ->
      {:ok, updated} = apply_event(doc, parent, event)
      {updated, List.last(updated["steps"])["id"]}
    end)
  end

  test "exact fit and slot precedence execute the real independent implementations" do
    {:ok, doc} = Trace.create()
    {doc, id} = walk(doc, [{:request, 11, 100}])
    step = Trace.step(doc, id)
    assert step["output"]["result"] == "admitted"
    assert step["output"] == step["oracle"]
    assert Enum.find(step["checks"], &(&1["slug"] == "po_a2"))["status"] == "allows_here"
    {:ok, updated} = apply_event(doc, id, {:request, 12, 1})
    assert List.last(updated["steps"])["output"]["result"] == "insufficient_amount"
    {:ok, zero} = Trace.create("ledger", 0, 0)
    {zero, _} = walk(zero, [{:request, 1, 1}])
    assert List.last(zero["steps"])["output"]["result"] == "insufficient_holds"
  end

  test "full local lifecycle preserves uncertainty, retry identity and confirmation release" do
    {:ok, doc} = Trace.create()

    {doc, _} =
      walk(doc, [
        {:request, 11, 100},
        {:dispatch, 11},
        {:timeout, 11},
        {:retry, 11},
        :restart,
        {:processor_result, 11, :approved},
        {:transport_ack, 11},
        {:void, 11},
        {:void_confirmed, 11},
        {:void_confirmed, 11}
      ])

    assert Enum.at(doc["steps"], 2)["after"]["used_amount"] == 100

    assert Enum.at(doc["steps"], 3)["output"]["effects"] == [
             %{"type" => "authorize", "key" => 11, "amount" => 100}
           ]

    assert Enum.at(doc["steps"], 7)["after"]["used_amount"] == 100
    assert Enum.at(doc["steps"], 8)["after"]["used_amount"] == 0
    assert List.last(doc["steps"])["output"]["result"] == "stale"
    assert Enum.all?(doc["steps"], &(&1["output"] == &1["oracle"]))
  end

  test "branching and exact retry preserve parent history and receipts" do
    {:ok, doc} = Trace.create()
    {doc, parent} = walk(doc, [{:request, 1, 50}])
    {:ok, left} = apply_event(doc, parent, {:dispatch, 1})
    {:ok, right} = apply_event(left, parent, {:void, 1})
    assert length(right["steps"]) == 3
    assert length(Trace.path(right, List.last(right["steps"])["id"])) == 2
    assert hd(right["steps"]) == hd(doc["steps"])
    assert {:ok, loaded} = Trace.get(doc["id"])
    assert loaded["steps"] == right["steps"]
  end

  test "CAS, command idempotency and conflicting retry have distinct outcomes" do
    {:ok, doc} = Trace.create()
    {:ok, json} = TermCodec.encode_event({:request, 1, 50})
    cmd = %{"kind" => "append", "parent" => "start", "event" => json}
    request = Trace.token()
    assert {:ok, first} = Trace.command(doc["id"], 0, request, cmd)
    assert {:ok, same} = Trace.command(doc["id"], 0, request, cmd)
    assert same["steps"] == first["steps"]
    assert {:error, :revision_conflict} = Trace.command(doc["id"], 0, Trace.token(), cmd)

    assert {:error, :request_id_conflict} =
             Trace.command(doc["id"], 0, request, Map.put(cmd, "parent", "missing"))
  end

  test "inconsistent candidate totals are checked without correction or saving stale candidates" do
    {:ok, doc} = Trace.create()
    {doc, id} = walk(doc, [{:request, 1, 100}])
    output = Trace.step(doc, id)["output"] |> put_in(["after", "used_amount"], 0)
    assert {:ok, challenge} = Trace.candidate(doc, id, output)
    refute challenge["valid_after"]
    assert challenge["output"]["after"]["used_amount"] == 0
    assert Enum.any?(challenge["checks"], &(&1["status"] == "catches"))

    assert {:error, :candidate_continuation_requires_valid_state} =
             Trace.command(doc["id"], doc["revision"], Trace.token(), %{
               "kind" => "candidate",
               "parent" => id,
               "output" => output
             })

    assert {:error, :invalid_candidate} = Trace.candidate(doc, id, %{"arbitrary" => "shape"})
  end

  test "a valid hypothetical state and every continuation retain hypothetical origin" do
    {:ok, doc} = Trace.create()
    {doc, id} = walk(doc, [{:request, 1, 100}])
    {:ok, initial} = TermCodec.encode_state(Ledger.init(100, 2))
    output = %{"after" => initial, "result" => "insufficient_amount", "effects" => []}

    {:ok, doc} =
      Trace.command(doc["id"], doc["revision"], Trace.token(), %{
        "kind" => "candidate",
        "parent" => id,
        "output" => output
      })

    candidate = List.last(doc["steps"])
    assert candidate["origin"] == "hypothetical"
    {:ok, doc} = apply_event(doc, candidate["id"], {:request, 2, 100})
    assert List.last(doc["steps"])["origin"] == "hypothetical_continuation"
  end

  test "coupled execution distinguishes delivery and observation and permanently fences delayed authorization" do
    {:ok, doc} = Trace.create("exposure")

    events = [
      {:local, {:request, 11, 100}},
      {:local, {:dispatch, 11}},
      {:authorize, 11, :approved},
      {:local, {:timeout, 11}},
      {:observe, 11},
      {:local, {:void, 11}},
      {:void, 11},
      {:confirm, 11},
      {:authorize, 11, :approved}
    ]

    {doc, _} = walk(doc, events)

    assert Enum.at(doc["steps"], 2)["after"]["ledger"]["entries"] |> hd() |> Map.fetch!("status") ==
             "sent"

    assert Enum.at(doc["steps"], 3)["after"]["ledger"]["used_amount"] == 100
    assert Enum.at(doc["steps"], 6)["after"]["ledger"]["used_amount"] == 100
    assert Enum.at(doc["steps"], 7)["after"]["ledger"]["used_amount"] == 0
    final = List.last(doc["steps"])
    {:ok, native} = TermCodec.decode_exposure(final["after"])
    assert native == Exposure.run(Exposure.init(100, 2), events)
    assert Spec.exposure_valid?(native)
    assert hd(final["after"]["remote"])["status"] == "voided"
    assert final["checks"] == []
    assert final["oracle"] == nil
  end

  test "malformed requests and bounds fail before creating any trace step" do
    assert {:error, _} = Trace.create("ledger", -1, 2)
    assert {:error, _} = Trace.create("ledger", 1_000_001, 2)
    assert {:error, _} = Trace.create("invented")
    {:ok, doc} = Trace.create()

    assert {:error, _} =
             Trace.command(doc["id"], 0, Trace.token(), %{
               "kind" => "append",
               "parent" => "start",
               "event" => %{"type" => "eval"}
             })

    assert {:ok, loaded} = Trace.get(doc["id"])
    assert loaded["steps"] == []
    assert {:error, _} = Trace.get("../../secret")
    assert {:error, _} = Trace.source("../../secret")
  end

  test "malformed command values refuse without crashing the single writer" do
    {:ok, doc} = Trace.create()

    assert {:error, :invalid_command} =
             Trace.command(doc["id"], 0, Trace.token(), %{"kind" => "note", "float" => 1.5})

    assert {:error, :invalid_trace_command} = Trace.command(doc["id"], 0.5, Trace.token(), %{})
    assert {:ok, unchanged} = Trace.get(doc["id"])
    assert unchanged["revision"] == 0
  end

  test "identity drift refuses further work and changes cache identity" do
    {:ok, doc} = Trace.new("ledger", 100, 2)
    stale = put_in(doc, ["identity", "source"], String.duplicate("0", 64))
    refute Trace.current?(stale)
    assert Canonical.digest(stale["identity"]) != Canonical.digest(doc["identity"])

    assert {:error, :stale_source} =
             Trace.apply_command(stale, 0, Trace.token(), %{
               "kind" => "note",
               "step" => "start",
               "text" => "Concern",
               "disposition" => "concern"
             })

    assert Claims.freshness() == :ok
  end

  test "identity binds the documents and locked context used during review" do
    {:ok, identity} = Trace.identity()

    for path <-
          ~w(guides/specification.md guides/processors.md guides/runtime.md mix.lock apps/review_web/mix.lock .tool-versions lean-toolchain) do
      assert identity["context"][path] ==
               HoldLedgerReview.Anchor.sha(
                 File.read!(Path.join(HoldLedgerReview.Config.root(), path))
               )
    end

    {:ok, doc} = Trace.new("ledger", 100, 2)
    stale = put_in(doc, ["identity", "context", "mix.lock"], String.duplicate("0", 64))
    refute Trace.current?(stale)
  end

  test "create and command replies carry the same current digest as the durable record" do
    {:ok, doc} = Trace.create()
    assert doc["document_digest"] == Canonical.digest(Map.delete(doc, "document_digest"))
    {:ok, updated} = apply_event(doc, "start", {:request, 1, 10})
    assert updated["document_digest"] == Canonical.digest(Map.delete(updated, "document_digest"))
    assert {:ok, ^updated} = Trace.get(doc["id"])
  end

  test "human records preserve scoped reasons without changing proof or source authority" do
    {:ok, doc} = Trace.create()

    action = %{
      "kind" => "note",
      "step" => "start",
      "text" => "Need processor documentation.",
      "disposition" => "needs_evidence"
    }

    {:ok, updated} = Trace.command(doc["id"], 0, Trace.token(), action)
    assert hd(updated["notes"])["origin"] == "human"
    assert updated["identity"] == doc["identity"]
    refute Map.has_key?(updated, "formal_acceptance")
  end
end
