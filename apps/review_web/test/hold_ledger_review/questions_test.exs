defmodule HoldLedgerReview.QuestionsTest do
  use ExUnit.Case, async: false
  alias HoldLedgerReview.{AI, Canonical, Contrast, QuestionContext, Questions}

  defp context do
    {:ok, trace} = Contrast.create("po_a2")
    {:ok, data} = Contrast.case_for(trace, List.last(trace["steps"])["id"], "po_a2")
    %{doc: trace, case: data, slug: "po_a2", basis: "candidate", binding_index: 0, selection: nil}
  end

  test "question packet binds actual source and alternative separately and remains strict JSON" do
    {:ok, packet} = QuestionContext.prepare("Why is this output rejected?", context(), "operator")
    assert packet["model"] == "gpt-6.1-terra"
    assert packet["effort"] == "medium"
    assert is_binary(Canonical.json(packet))
    assert Enum.any?(packet["context"]["sources"], &(&1["path"] == "lib/hold_ledger/spec.ex"))
    assert packet["context"]["case"]["actual"] != packet["context"]["case"]["candidate"]
    assert :ok == QuestionContext.freshness(packet)

    assert {:error, _} =
             QuestionContext.freshness(
               put_in(packet, ["identity", "source"], String.duplicate("0", 64))
             )

    assert {:error, _} = QuestionContext.prepare("", context(), "operator")
  end

  test "large Lean declarations fit the unchanged question budget with explicit source excerpts" do
    for slug <- ~w(po_b2 po_b3) do
      {:ok, doc} = Contrast.create(slug)
      {:ok, data} = Contrast.case_for(doc, List.last(doc["steps"])["id"], slug)

      context = %{
        doc: doc,
        case: data,
        slug: slug,
        basis: "candidate",
        binding_index: 0,
        selection: nil
      }

      assert {:ok, packet} = QuestionContext.prepare("Explain this rule", context, "operator")
      assert byte_size(Canonical.json(packet["context"])) <= 98_304
      assert :ok = QuestionContext.freshness(packet)
      {:ok, reading} = HoldLedgerReview.ProofReading.document(slug)
      declaration = hd(reading["declarations"])
      source = Enum.find(packet["context"]["sources"], &(&1["path"] == declaration["path"]))
      assert source["truncated"]
      assert String.starts_with?(declaration["text"], source["text"])
      assert source["excerpt_sha256"] == HoldLedgerReview.Anchor.sha(source["text"])
      assert source["full_excerpt_sha256"] == HoldLedgerReview.Anchor.sha(declaration["text"])
      refute Map.has_key?(hd(packet["context"]["declarations"]), "text")
      spec = Enum.find(packet["context"]["sources"], &(&1["path"] == "lib/hold_ledger/spec.ex"))
      assert spec["text"] == File.read!(Path.join(HoldLedgerReview.Config.root(), spec["path"]))
    end

    assert {:error, :empty_question} = QuestionContext.prepare(" ", context(), "operator")
  end

  test "question profile does not replace historical client defaults" do
    assert AI.question_client().model == "gpt-6.1-terra"
    assert AI.question_client().defaults[:reasoning_effort] == :medium
    assert AI.client().model == "gpt-6.1-sol"
  end

  setup do
    dir = Path.join(System.tmp_dir!(), "questions-#{System.unique_integer([:positive])}")
    owner = self()

    runner = fn packet ->
      send(owner, {:question_job, self(), packet})

      receive do
        {:complete, value} -> value
      end
    end

    {:ok, store} =
      start_supervised({Questions, name: nil, dir: dir, runner: runner, timeout: 5_000})

    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, store: store, dir: dir}
  end

  test "consent, one dispatch, durable response and local recall", %{store: store, dir: dir} do
    {:ok, packet} = QuestionContext.prepare("Explain the boundary", context(), "operator")
    {:ok, row} = Questions.prepare(packet, self(), store)
    assert {:error, :consent_required} = Questions.ask(row["id"], packet["digest"], false, store)
    refute_receive {:question_job, _, _}
    assert :ok = Questions.ask(row["id"], packet["digest"], true, store)
    assert {:error, :already_dispatched} = Questions.ask(row["id"], packet["digest"], true, store)
    assert_receive {:question_job, worker, ^packet}, 5_000

    answer = %{
      "summary" => "The exact capacity is covered.",
      "explanation" => "This is an example execution.",
      "source_ids" => [],
      "limits" => []
    }

    send(worker, {:complete, {:ok, answer}})
    assert_receive {:question_ready, id}, 5_000
    assert id == row["id"]
    assert Questions.get(id, store)["answer"] == answer
    assert length(Questions.list("capacity", store)) == 1
    [file] = Path.wildcard(Path.join(dir, "*/events.jsonl"))
    log = File.read!(file)
    assert log =~ "Explain the boundary"
    assert log =~ "The exact capacity is covered."
    assert Enum.all?(String.split(log, "\n", trim: true), &match?({:ok, _}, Jason.decode(&1)))
  end

  test "cancellation is terminal and cannot save a late answer as active", %{store: store} do
    {:ok, packet} = QuestionContext.prepare("Explain this case", context(), "operator")
    {:ok, row} = Questions.prepare(packet, self(), store)
    :ok = Questions.ask(row["id"], packet["digest"], true, store)
    assert_receive {:question_job, worker, _}, 5_000
    :ok = Questions.cancel(row["id"], store)
    assert Questions.get(row["id"], store)["status"] == "cancelled"
    ref = Process.monitor(worker)
    assert_receive {:DOWN, ^ref, :process, ^worker, _}, 5_000
    refute Questions.get(row["id"], store)["answer"]
  end

  test "answer references must resolve within the sent packet" do
    {:ok, packet} = QuestionContext.prepare("Explain", context(), "operator")

    forged = %{
      "summary" => "Fine",
      "explanation" => "",
      "source_ids" => ["invented"],
      "limits" => []
    }

    assert {:error, :invalid_answer} = QuestionContext.validate_answer(forged, packet)
  end

  test "restart preserves answers, interrupts unfinished work and refuses corrupt middle records",
       %{store: store, dir: dir} do
    {:ok, packet} = QuestionContext.prepare("Restart example", context(), "operator")
    {:ok, row} = Questions.prepare(packet, self(), store)
    :ok = Questions.ask(row["id"], packet["digest"], true, store)
    assert_receive {:question_job, worker, _}, 5_000
    stop_supervised(Questions)
    Process.exit(worker, :kill)
    {:ok, recovered} = start_supervised({Questions, name: nil, dir: dir})
    assert Questions.get(row["id"], recovered)["status"] == "interrupted"
    assert {:error, _} = Questions.ask(row["id"], packet["digest"], true, recovered)
    stop_supervised(Questions)
    [file] = Path.wildcard(Path.join(dir, "*/events.jsonl"))
    File.write!(file, "bad-record\n" <> File.read!(file))
    {:ok, broken} = start_supervised({Questions, name: nil, dir: dir})
    assert {:error, :corrupt_question_log} = Questions.health(broken)
    assert {:error, _} = Questions.prepare(packet, self(), broken)
  end

  test "timeout is a terminal recorded outcome, with no retry", %{dir: dir} do
    parent = self()

    {:ok, store} =
      start_supervised(
        {Questions,
         name: nil,
         dir: Path.join(dir, "deadline"),
         timeout: 1,
         runner: fn _ ->
           send(parent, :runner_started)

           receive do
             :never -> :ok
           end
         end},
        id: :deadline_store
      )

    {:ok, packet} = QuestionContext.prepare("Timeout example", context(), "operator")
    {:ok, row} = Questions.prepare(packet, self(), store)
    :ok = Questions.ask(row["id"], packet["digest"], true, store)
    assert_receive {:question_ready, id}, 5_000
    assert id == row["id"]
    assert Questions.get(id, store)["status"] == "timed_out"
    assert {:error, _} = Questions.ask(id, packet["digest"], true, store)
  end

  test "Inference receives the explicit profile and a strict source-checked answer schema" do
    {:ok, packet} = QuestionContext.prepare("Why?", context(), "operator")
    parent = self()

    complete = fn client, request ->
      send(
        parent,
        {:profile, client.model, client.defaults[:reasoning_effort], request.response_format}
      )

      {:ok,
       %{
         object: %{
           "summary" => "Held until confirmation.",
           "explanation" => "",
           "source_ids" => [],
           "limits" => []
         },
         tool_calls: []
       }}
    end

    assert {:ok, _, metadata} =
             AI.answer(packet, true, complete: complete, capability_check: fn _ -> true end)

    assert metadata["routing_evidence"] == "adapter_response_metadata"
    assert_receive {:profile, "gpt-6.1-terra", :medium, {:json_schema, _}}
    assert {:error, :consent_required} = AI.answer(packet, false, complete: complete)
  end

  test "comparison context keeps exact snapshot identities without duplicating full manifests" do
    manifest = Map.new(1..500, &{"source-#{&1}.ex", String.duplicate("a", 64)})

    pair = %{
      "baseline" => %{"snapshot_id" => String.duplicate("b", 64), "manifest" => manifest},
      "proposal" => %{"snapshot_id" => String.duplicate("c", 64), "manifest" => manifest},
      "source_changes" => [],
      "evidence" => []
    }

    {:ok, packet} =
      QuestionContext.prepare("What changed?", Map.put(context(), :package, pair), "operator")

    assert packet["context"]["comparison"]["baseline"]["snapshot_id"] == String.duplicate("b", 64)
    refute Map.has_key?(packet["context"]["comparison"]["baseline"], "manifest")
  end

  test "unwritable log prevents preparation and cannot dispatch", %{dir: dir} do
    blocked = Path.join(dir, "not-a-directory")
    File.mkdir_p!(dir)
    File.write!(blocked, "existing file")
    owner = self()

    {:ok, store} =
      start_supervised(
        {Questions,
         name: nil, dir: blocked, runner: fn _ -> send(owner, :unexpected_dispatch) end},
        id: :blocked_store
      )

    {:ok, packet} = QuestionContext.prepare("No unlogged sends", context(), "operator")
    assert {:error, :question_log_unavailable} = Questions.prepare(packet, self(), store)
    assert Questions.list("", store) == []
    refute_receive :unexpected_dispatch
  end

  test "torn tail is preserved privately and complete records remain recallable", %{
    store: store,
    dir: dir
  } do
    {:ok, packet} = QuestionContext.prepare("Preserve history", context(), "operator")
    {:ok, row} = Questions.prepare(packet, self(), store)
    [file] = Path.wildcard(Path.join(dir, "*/events.jsonl"))
    File.write!(file, "{broken", [:append])
    stop_supervised(Questions)
    {:ok, recovered} = start_supervised({Questions, name: nil, dir: dir})
    assert Questions.health(recovered) == :ok
    assert Questions.get(row["id"], recovered)["packet"] == packet
    [backup] = Path.wildcard(file <> ".torn-*")
    assert File.read!(backup) == "{broken"
    assert Bitwise.band(File.stat!(backup).mode, 0o777) == 0o600
    assert Bitwise.band(File.stat!(file).mode, 0o777) == 0o600
  end

  test "a completion-save failure preserves the in-memory answer and reports lost durability", %{
    store: store,
    dir: dir
  } do
    {:ok, packet} =
      QuestionContext.prepare("Keep this answer if storage fails", context(), "operator")

    {:ok, row} = Questions.prepare(packet, self(), store)
    :ok = Questions.ask(row["id"], packet["digest"], true, store)
    assert_receive {:question_job, worker, _}, 5_000
    conversation_dir = Path.join(dir, packet["conversation"])
    File.rename!(conversation_dir, conversation_dir <> "-preserved")
    File.write!(conversation_dir, "storage is unavailable")

    answer = %{
      "summary" => "Copy this answer.",
      "explanation" => "",
      "source_ids" => [],
      "limits" => []
    }

    send(worker, {:complete, {:ok, answer}})
    assert_receive {:question_ready, id}, 5_000
    assert Questions.get(id, store)["answer"] == answer
    assert Questions.get(id, store)["persistence_error"] == true
  end
end
