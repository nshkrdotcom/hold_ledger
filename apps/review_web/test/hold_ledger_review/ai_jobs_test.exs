defmodule HoldLedgerReview.AIJobsTest do
  use ExUnit.Case, async: false
  alias HoldLedgerReview.{AI, AIJobs, AIPacket, ReviewStore}
  alias HoldLedgerReview.TestSupport.ControlledAdapter

  setup do
    dir = Path.join(System.tmp_dir!(), "hold-ledger-c-jobs-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, store} = start_supervised({ReviewStore, name: nil, dir: dir})
    {:ok, supervisor} = start_supervised(Task.Supervisor)
    ControlledAdapter.set_controller(self())
    on_exit(&ControlledAdapter.clear_controller/0)
    {:ok, doc, witness} = ReviewStore.create("P03", store)
    card = Enum.find(doc["core_cards"], &(&1["kind"] == "reading"))

    {:ok,
     store: store,
     supervisor: supervisor,
     review: doc,
     witness: witness,
     card: card,
     opts: [
       store: store,
       task_supervisor: supervisor,
       complete: &ControlledAdapter.complete/2,
       capability_check: &ControlledAdapter.capable?/1
     ]}
  end

  defp token, do: Base.url_encode64(:crypto.strong_rand_bytes(18), padding: false)

  defp deck(ctx) do
    %{
      "request_kind" => "deck",
      "target_node_id" => ctx.target_node_id,
      "intent_hypotheses" => [],
      "readings" => [],
      "uncertainties" => [],
      "card_suggestions" => [
        %{
          "proposal_id" => "candidate-1",
          "kind" => "assumption",
          "target_node_id" => ctx.target_node_id,
          "question" => "What would make the remote journal evidence reliable for this decision?",
          "selection_reason" => "Remote evidence is independently assumed.",
          "source_ids" => [hd(ctx.source_ids)],
          "probe_ids" => []
        }
      ]
    }
  end

  defp followup(card, ctx, question) do
    %{
      "request_kind" => "followup",
      "card_id" => card["id"],
      "question" => question,
      "possible_intent_revision" => nil,
      "explanation" => "A computed example can challenge an unsupported assumption.",
      "source_ids" => [hd(ctx.source_ids)],
      "uncertainty" => "No remote attestation"
    }
  end

  defp begin_job(data, kind, witness \\ nil) do
    AIJobs.request(
      data.review["id"],
      kind,
      data.card["id"],
      witness,
      data.review["human_revision"],
      true,
      data.opts
    )
  end

  defp reply(output) do
    assert_receive {:controlled_request, pid, request}, 5_000
    assert match?({:json_schema, _}, request.response_format)
    refute to_string(inspect(request)) =~ "R1: Validity"
    monitor = Process.monitor(pid)
    send(pid, {:controlled_reply, {:ok, output}})
    assert_receive {:DOWN, ^monitor, :process, ^pid, :normal}, 10_000
  end

  test "no opt-in or capability means no stored job and no request", data do
    assert {:error, :consent_or_revision_required} =
             AIJobs.request(data.review["id"], "deck", data.card["id"], nil, 0, false, data.opts)

    assert {:error, :ai_unavailable} =
             AIJobs.request(
               data.review["id"],
               "deck",
               data.card["id"],
               nil,
               0,
               true,
               Keyword.put(data.opts, :capability_check, &ControlledAdapter.unavailable?/1)
             )

    assert {:ok, reloaded} = ReviewStore.get(data.review["id"], data.store)
    assert reloaded == data.review
    refute_received {:controlled_request, _, _}
  end

  test "completed discovery is durable, human counter unchanged and exact retry idempotent",
       data do
    {:ok, packet} = AIPacket.build(data.review, "deck", data.card["id"])
    {:ok, started, job_id} = begin_job(data, "deck")
    assert started["human_revision"] == 1
    assert hd(started["ai_jobs"])["status"] == "pending"
    reply(deck(packet.context))
    {:ok, completed} = ReviewStore.get(data.review["id"], data.store)
    [job] = completed["ai_jobs"]
    assert job["job_id"] == job_id and job["status"] == "complete"
    assert completed["human_revision"] == started["human_revision"]
    assert length(completed["suggested_ai_cards"]) == 1
    assert completed["answers"] == []

    repeat = %{
      "job_id" => job_id,
      "input_digest" => job["input_digest"],
      "source_digest" => job["source_digest"],
      "validated_output" => job["validated_output"],
      "error_class" => nil
    }

    assert {:ok, ^completed} = ReviewStore.complete_job(completed["id"], repeat, data.store)

    assert {:error, :job_already_completed} =
             ReviewStore.complete_job(
               completed["id"],
               %{repeat | "error_class" => "changed"},
               data.store
             )

    assert completed["document_revision"] > started["document_revision"]
  end

  test "AI completion after a human answer is marked discarded_late, never overwrites CAS",
       data do
    {:ok, packet} = AIPacket.build(data.review, "challenge", data.card["id"], data.witness)
    {:ok, started, _} = begin_job(data, "challenge", data.witness)
    reading = data.card

    {:ok, %{review: answered}} =
      ReviewStore.answer_card(
        started["id"],
        %{
          "request_id" => token(),
          "expected_human_revision" => started["human_revision"],
          "card_id" => reading["id"],
          "choice" => "unsure",
          "reason" => "Need more evidence",
          "evidence_ids" => reading["source_ids"],
          "revealed_before_answer" => false
        },
        data.store
      )

    proposed = %{
      "request_kind" => "challenge",
      "target_card_id" => reading["id"],
      "witness" => data.witness,
      "selection_reason" => "Check this output.",
      "source_ids" => [hd(packet.context.source_ids)]
    }

    reply(proposed)
    {:ok, finished} = ReviewStore.get(started["id"], data.store)
    assert hd(finished["ai_jobs"])["status"] == "discarded_late"
    assert finished["human_revision"] == answered["human_revision"]
    assert finished["answers"] == answered["answers"]
    assert finished["pinned_probes"] == []
  end

  test "unknown source/status fields fail without publishing cards", data do
    {:ok, packet} = AIPacket.build(data.review, "deck", data.card["id"])
    {:ok, started, _} = begin_job(data, "deck")
    forged = Map.put(deck(packet.context), "approved", true)
    reply(forged)
    {:ok, failed} = ReviewStore.get(started["id"], data.store)
    assert hd(failed["ai_jobs"])["status"] == "failed"
    assert hd(failed["ai_jobs"])["error_class"] == "invalid_model_output"
    assert failed["suggested_ai_cards"] == []
  end

  test "two answer-aware followups preserve history and update context across reconnection",
       data do
    {:ok, %{review: answered}} =
      ReviewStore.answer_card(
        data.review["id"],
        %{
          "request_id" => token(),
          "expected_human_revision" => 0,
          "card_id" => data.card["id"],
          "choice" => "inaccurate",
          "reason" => "First challenge to this interpretation",
          "evidence_ids" => data.card["source_ids"],
          "revealed_before_answer" => false
        },
        data.store
      )

    {:ok, first_packet} = AI.prepare(answered, "followup", data.card["id"])
    assert first_packet.user =~ "First challenge to this interpretation"

    {:ok, waiting, _} =
      AIJobs.request(
        answered["id"],
        "followup",
        data.card["id"],
        nil,
        answered["human_revision"],
        true,
        data.opts
      )

    first_question = "Which binding would distinguish the requested human interpretation?"
    reply(followup(data.card, first_packet.context, first_question))
    {:ok, completed} = ReviewStore.get(waiting["id"], data.store)
    assert hd(completed["ai_jobs"])["status"] == "complete"

    {:ok, %{review: revised}} =
      ReviewStore.answer_card(
        completed["id"],
        %{
          "request_id" => token(),
          "expected_human_revision" => completed["human_revision"],
          "card_id" => data.card["id"],
          "choice" => "unsure",
          "reason" => "Revised after the first model question",
          "evidence_ids" => data.card["source_ids"],
          "revealed_before_answer" => true
        },
        data.store
      )

    # A reconnect reads the file, not the previous LiveView socket.
    {:ok, restored} = ReviewStore.get(revised["id"], data.store)
    {:ok, second_packet} = AI.prepare(restored, "followup", data.card["id"])
    assert second_packet.user =~ first_question
    assert second_packet.user =~ "Revised after the first model question"

    {:ok, second_waiting, _} =
      AIJobs.request(
        restored["id"],
        "followup",
        data.card["id"],
        nil,
        restored["human_revision"],
        true,
        data.opts
      )

    reply(
      followup(
        data.card,
        second_packet.context,
        "Does the revised answer handle the separate external premise?"
      )
    )

    {:ok, done} = ReviewStore.get(second_waiting["id"], data.store)
    assert Enum.map(done["ai_jobs"], & &1["status"]) == ["complete", "complete"]
    assert length(done["answers"]) == 2

    assert done["answers"] |> List.last() |> Map.fetch!("supersedes_answer_id") ==
             hd(done["answers"])["answer_id"]
  end

  test "controlled provider failure is durable and never invents an AI answer", data do
    {:ok, started, _} = begin_job(data, "deck")
    assert_receive {:controlled_request, pid, request}, 5_000
    assert match?({:json_schema, _}, request.response_format)
    monitor = Process.monitor(pid)
    send(pid, {:controlled_reply, {:error, :provider_failure}})
    assert_receive {:DOWN, ^monitor, :process, ^pid, :normal}, 10_000

    {:ok, failed} = ReviewStore.get(started["id"], data.store)
    assert hd(failed["ai_jobs"])["status"] == "failed"
    assert hd(failed["ai_jobs"])["error_class"] == "provider_failure"
    assert failed["suggested_ai_cards"] == [] and failed["answers"] == []
    assert failed["human_revision"] == started["human_revision"]
  end

  test "process restart records interrupted instead of resending pending work", data do
    dir =
      Path.join(System.tmp_dir!(), "hold-ledger-c-restart-#{System.unique_integer([:positive])}")

    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)

    {:ok, first} = ReviewStore.start_link(name: nil, dir: dir)
    {:ok, review, _} = ReviewStore.create("P03", first)
    card = hd(review["core_cards"])
    opts = Keyword.put(data.opts, :store, first)

    assert {:ok, _started, _id} =
             AIJobs.request(
               review["id"],
               "deck",
               card["id"],
               nil,
               review["human_revision"],
               true,
               opts
             )

    assert_receive {:controlled_request, pid, _request}, 5_000
    :ok = GenServer.stop(first)

    {:ok, recovered} = ReviewStore.start_link(name: nil, dir: dir)
    assert {:ok, interrupted} = ReviewStore.get(review["id"], recovered)
    assert hd(interrupted["ai_jobs"])["status"] == "interrupted"
    assert hd(interrupted["ai_jobs"])["error_class"] == "process_restart"
    assert interrupted["answers"] == [] and interrupted["suggested_ai_cards"] == []
    refute_receive {:controlled_request, _, _}, 100

    # A result from the stopped process cannot complete an interrupted job.
    monitor = Process.monitor(pid)
    send(pid, {:controlled_reply, {:error, :provider_failure}})
    assert_receive {:DOWN, ^monitor, :process, ^pid, :normal}, 10_000
    {:ok, still_interrupted} = ReviewStore.get(review["id"], recovered)
    assert still_interrupted["ai_jobs"] == interrupted["ai_jobs"]
    :ok = GenServer.stop(recovered)
  end
end
