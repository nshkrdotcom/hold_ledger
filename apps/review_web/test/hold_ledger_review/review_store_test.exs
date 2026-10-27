defmodule HoldLedgerReview.ReviewStoreTest do
  use ExUnit.Case, async: false
  alias HoldLedgerReview.{Canonical, ReviewReport, ReviewStore}

  setup do
    path =
      Path.join(
        System.tmp_dir!(),
        "hold-ledger-b-#{Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)}"
      )

    File.mkdir_p!(path)
    on_exit(fn -> File.rm_rf(path) end)
    {:ok, pid} = start_supervised({ReviewStore, name: nil, dir: path})
    {:ok, store: pid, dir: path}
  end

  defp token, do: Base.url_encode64(:crypto.strong_rand_bytes(18), padding: false)

  defp command(doc, witness, card \\ nil) do
    %{
      "request_id" => token(),
      "expected_human_revision" => doc["human_revision"],
      "card_id" => card || "core.#{String.downcase(doc["seed_id"])}.escape",
      "packet_digest" => doc["source"]["packet_digest"],
      "witness" => witness,
      "choice" => "unacceptable",
      "reason" => "Explicit policy review",
      "revealed_before_answer" => false
    }
  end

  test "atomic Escape answer binds the exact full witness, idempotency, CAS and no orphans", %{
    store: store,
    dir: dir
  } do
    {:ok, doc, witness} = ReviewStore.create("P01", store)
    assert doc["document_revision"] == 1 and doc["human_revision"] == 0
    assert doc["pinned_probes"] == [] and doc["answers"] == []
    cmd = command(doc, witness)

    assert {:ok, %{review: saved, probe_id: probe_id, answer_id: answer_id}} =
             ReviewStore.answer_escape(doc["id"], cmd, store)

    assert saved["human_revision"] == 1 and saved["document_revision"] == 2
    assert length(saved["pinned_probes"]) == 1 and length(saved["answers"]) == 1
    assert hd(saved["answers"])["probe_id"] == probe_id
    assert hd(saved["answers"])["answer_id"] == answer_id
    assert hd(saved["pinned_probes"])["id"] == probe_id
    assert probe_id == hd(saved["pinned_probes"])["fingerprint"]
    assert hd(saved["pinned_probes"])["source_digest"] == doc["source"]["packet_digest"]

    assert {:ok, %{review: ^saved, answer_id: ^answer_id}} =
             ReviewStore.answer_escape(doc["id"], cmd, store)

    assert {:error, :request_id_conflict} =
             ReviewStore.answer_escape(doc["id"], %{cmd | "reason" => "different"}, store)

    assert {:error, :human_revision_conflict} =
             ReviewStore.answer_escape(doc["id"], command(doc, witness), store)

    {:ok, from_disk} = ReviewStore.get(doc["id"], store)
    assert from_disk == saved
    assert length(Path.wildcard(Path.join(dir, "*.json"))) == 1
    assert ReviewReport.json(saved) =~ probe_id
    assert ReviewReport.markdown(saved) =~ "Unfinished review"
  end

  test "duplicate candidate fingerprint, answer supersession, and wrong submitted packet rejection",
       %{store: store} do
    {:ok, doc, witness} = ReviewStore.create("P05", store)

    assert {:error, :stale_source} =
             ReviewStore.answer_escape(
               doc["id"],
               %{command(doc, witness) | "packet_digest" => "forged"},
               store
             )

    assert {:ok, ^doc} = ReviewStore.get(doc["id"], store)

    {:ok, %{review: next, probe_id: id1}} =
      ReviewStore.answer_escape(doc["id"], command(doc, witness), store)

    second = %{command(next, witness) | "choice" => "acceptable"}

    assert {:ok, %{review: updated, probe_id: ^id1}} =
             ReviewStore.answer_escape(doc["id"], second, store)

    assert length(updated["pinned_probes"]) == 1
    assert length(updated["answers"]) == 2

    assert List.last(updated["answers"])["supersedes_answer_id"] ==
             hd(updated["answers"])["answer_id"]

    assert updated["human_revision"] == 2
  end

  test "invalid candidate or failed write leaves no probe or answer", %{store: store} do
    {:ok, doc, witness} = ReviewStore.create("P04", store)

    forged =
      put_in(witness, ["output", "after", "entries"], [
        %{"key" => 1, "amount" => -1, "status" => "sent"}
      ])

    assert {:error, :invalid_draft} =
             ReviewStore.answer_escape(doc["id"], command(doc, forged), store)

    assert {:ok, ^doc} = ReviewStore.get(doc["id"], store)
  end

  test "jobs advance document revision without stealing human CAS; stale challenge completion is discarded",
       %{store: store} do
    {:ok, doc, witness} = ReviewStore.create("P04", store)

    start = %{
      "request_id" => token(),
      "expected_human_revision" => 0,
      "job_id" => token(),
      "request_kind" => "challenge",
      "prompt_hash" => Canonical.digest(%{"p" => 1}),
      "input_digest" => Canonical.digest(%{"i" => 2}),
      "source_digest" => doc["source"]["compiled_source_digest"]
    }

    assert {:ok, %{review: started}} = ReviewStore.start_job(doc["id"], start, store)
    assert started["document_revision"] == 2 and started["human_revision"] == 1

    assert {:ok, %{review: answered}} =
             ReviewStore.answer_escape(doc["id"], command(started, witness), store)

    result = %{
      "job_id" => start["job_id"],
      "input_digest" => start["input_digest"],
      "source_digest" => start["source_digest"],
      "validated_output" => nil,
      "error_class" => nil
    }

    assert {:ok, completed} = ReviewStore.complete_job(doc["id"], result, store)
    assert List.last(completed["ai_jobs"])["status"] == "discarded_late"
    assert completed["human_revision"] == answered["human_revision"]
    assert completed["document_revision"] == answered["document_revision"] + 1

    assert {:ok, ^completed} =
             ReviewStore.complete_job(
               doc["id"],
               result,
               store
             )
  end

  test "positive conclusion requires all mandatory and critical answers and scoped evidence", %{
    store: store
  } do
    {:ok, doc, _witness} = ReviewStore.create("P03", store)

    finish = %{
      "request_id" => token(),
      "expected_human_revision" => 0,
      "outcome" => "meets_intent_in_reviewed_scope",
      "scope" => "policy.events.07",
      "rationale" => "Human reviewed bounds",
      "evidence_ids" => [],
      "confirmed" => true
    }

    assert {:error, :unanswered_mandatory_or_critical} =
             ReviewStore.finish_review(doc["id"], finish, store)

    assert {:ok, ^doc} = ReviewStore.get(doc["id"], store)
  end

  test "corrupt persisted job shape is rejected without a restart crash", %{
    store: store,
    dir: dir
  } do
    {:ok, doc, _} = ReviewStore.create("P01", store)
    path = Path.join(dir, doc["id"] <> ".json")
    broken = Map.put(doc, "ai_jobs", [42])
    File.write!(path, Jason.encode!(broken))
    assert {:error, :corrupt_review} = ReviewStore.get(doc["id"], store)
    assert {:ok, []} = ReviewStore.list(store)
    stop_supervised!(ReviewStore)
    restarted = start_supervised!({ReviewStore, name: nil, dir: dir})
    assert {:error, :corrupt_review} = ReviewStore.get(doc["id"], restarted)
    assert Jason.decode!(File.read!(path))["ai_jobs"] == [42]
  end

  test "Escape envelope must match command kind and review identity", %{store: store} do
    {:ok, doc, witness} = ReviewStore.create("P01", store)
    forged = command(doc, witness) |> Map.put("review_id", "unrelated_document_id")
    assert {:error, _} = ReviewStore.answer_escape(doc["id"], forged, store)
    assert {:ok, ^doc} = ReviewStore.get(doc["id"], store)
    forged_kind = command(doc, witness) |> Map.put("command", "another_action")
    assert {:error, _} = ReviewStore.answer_escape(doc["id"], forged_kind, store)
    assert {:ok, ^doc} = ReviewStore.get(doc["id"], store)
  end

  test "writer failure on the answer is fail-closed and leaves the previous JSON untouched" do
    path = Path.join(System.tmp_dir!(), "hold-ledger-writer-#{token()}")
    File.mkdir_p!(path)
    on_exit(fn -> File.rm_rf(path) end)
    counter = start_supervised!({Agent, fn -> 0 end})

    writer = fn file, bytes ->
      n = Agent.get_and_update(counter, &{&1, &1 + 1})
      if n == 0, do: ReviewStore.atomic_write(file, bytes), else: {:error, :disk_full}
    end

    {:ok, pid} =
      start_supervised(
        Supervisor.child_spec({ReviewStore, name: nil, dir: path, writer: writer},
          id: :writer_store
        )
      )

    {:ok, doc, witness} = ReviewStore.create("P01", pid)

    assert {:error, :write_failed} =
             ReviewStore.answer_escape(doc["id"], command(doc, witness), pid)

    assert {:ok, ^doc} = ReviewStore.get(doc["id"], pid)
    assert Path.wildcard(Path.join(path, "*.tmp")) == []
  end

  defp card_command(doc, kind, choice, reason \\ "Named source evidence") do
    card = Enum.find(doc["core_cards"], &(&1["kind"] == kind))

    %{
      "request_id" => token(),
      "expected_human_revision" => doc["human_revision"],
      "card_id" => card["id"],
      "choice" => choice,
      "reason" => reason,
      "evidence_ids" => card["source_ids"],
      "revealed_before_answer" => false
    }
  end

  defp start_job(doc, kind, store) do
    command = %{
      "request_id" => token(),
      "expected_human_revision" => doc["human_revision"],
      "job_id" => token(),
      "request_kind" => kind,
      "prompt_hash" => token(),
      "input_digest" => token(),
      "source_digest" => doc["source"]["compiled_source_digest"]
    }

    {:ok, %{review: started}} = ReviewStore.start_job(doc["id"], command, store)

    completion =
      Map.take(command, ~w(job_id input_digest source_digest))
      |> Map.merge(%{"validated_output" => nil, "error_class" => nil})

    {started, completion}
  end

  test "background completion preserves a waiting human revision and exact retry", %{store: store} do
    {:ok, doc, witness} = ReviewStore.create("P04", store)
    {started, completion} = start_job(doc, "challenge", store)
    waiting = command(started, witness)
    {:ok, completed} = ReviewStore.complete_job(doc["id"], completion, store)
    assert hd(completed["ai_jobs"])["status"] == "complete"
    assert completed["human_revision"] == started["human_revision"]
    assert completed["document_revision"] == started["document_revision"] + 1
    assert {:ok, ^completed} = ReviewStore.complete_job(doc["id"], completion, store)

    assert {:error, :job_already_completed} =
             ReviewStore.complete_job(
               doc["id"],
               Map.put(completion, "error_class", "conflict"),
               store
             )

    {:ok, %{review: answered}} = ReviewStore.answer_escape(doc["id"], waiting, store)
    assert answered["human_revision"] == started["human_revision"] + 1
    assert answered["document_revision"] == completed["document_revision"] + 1

    assert {:error, :human_revision_conflict} =
             ReviewStore.answer_escape(doc["id"], Map.put(waiting, "request_id", token()), store)
  end

  test "restart interrupts pending jobs without resend and restores answers", %{
    store: store,
    dir: dir
  } do
    {:ok, doc, witness} = ReviewStore.create("P03", store)

    {:ok, %{review: answered}} =
      ReviewStore.answer_escape(doc["id"], command(doc, witness), store)

    {started, completion} = start_job(answered, "followup", store)
    stop_supervised!(ReviewStore)
    restarted = start_supervised!({ReviewStore, name: nil, dir: dir})
    {:ok, restored} = ReviewStore.get(doc["id"], restarted)
    assert hd(restored["ai_jobs"])["status"] == "interrupted"
    assert restored["human_revision"] == started["human_revision"]
    assert restored["document_revision"] == started["document_revision"] + 1
    assert restored["answers"] == answered["answers"]

    assert {:error, :job_already_completed} =
             ReviewStore.complete_job(doc["id"], completion, restarted)
  end

  test "all card vocabularies, supersession, deferral and positive conflict gates", %{
    store: store
  } do
    {:ok, doc, witness} = ReviewStore.create("P01", store)
    {:ok, %{review: escaped}} = ReviewStore.answer_escape(doc["id"], command(doc, witness), store)

    accepted =
      Enum.reduce(
        [
          {"reading", "accurate"},
          {"trace", "sufficient_for_review"},
          {"silence", "intentionally_excluded"},
          {"assumption", "supported"}
        ],
        escaped,
        fn {kind, choice}, d ->
          {:ok, %{review: next}} =
            ReviewStore.answer_card(d["id"], card_command(d, kind, choice), store)

          next
        end
      )

    finish = %{
      "request_id" => token(),
      "expected_human_revision" => accepted["human_revision"],
      "outcome" => "meets_intent_in_reviewed_scope",
      "scope" => "Named pending-void example only",
      "rationale" => "Source-backed rejection reviewed",
      "evidence_ids" => [hd(accepted["pinned_probes"])["id"]],
      "confirmed" => true
    }

    accepted =
      Enum.reduce(
        [
          {"assumption", "disputed"},
          {"assumption", "unknown"},
          {"reading", "inaccurate"},
          {"silence", "should_cover"},
          {"trace", "gap_suspected"},
          {"trace", "deferred"}
        ],
        accepted,
        fn {kind, choice}, accepted ->
          {:ok, %{review: changed}} =
            ReviewStore.answer_card(doc["id"], card_command(accepted, kind, choice), store)

          assert {:error, :unresolved_critical_conflict} =
                   ReviewStore.finish_review(
                     doc["id"],
                     %{finish | "expected_human_revision" => changed["human_revision"]},
                     store
                   )

          assert ReviewReport.markdown(changed) =~ choice

          original =
            Enum.find(
              Enum.reverse(accepted["answers"]),
              &(&1["card_id"] == List.last(changed["answers"])["card_id"])
            )

          assert List.last(changed["answers"])["supersedes_answer_id"] == original["answer_id"]
          # Restore the original source-owned judgment for the next independent challenge.
          {:ok, %{review: restored}} =
            ReviewStore.answer_card(
              doc["id"],
              card_command(changed, kind, original["choice"]),
              store
            )

          assert restored["human_revision"] == changed["human_revision"] + 1
          restored
        end
      )

    finish = %{finish | "expected_human_revision" => accepted["human_revision"]}

    assert {:error, :invalid_conclusion} =
             ReviewStore.finish_review(doc["id"], %{finish | "confirmed" => false}, store)

    assert {:ok, %{review: concluded}} = ReviewStore.finish_review(doc["id"], finish, store)
    assert concluded["status"] == "review_concluded"
  end

  test "malformed nested documents and symlinks remain read-only without implicit repair", %{
    store: store,
    dir: dir
  } do
    {:ok, doc, _} = ReviewStore.create("P01", store)
    path = Path.join(dir, doc["id"] <> ".json")

    for bad <- [
          "{",
          Jason.encode!(%{doc | "core_cards" => [%{}]}),
          Jason.encode!(%{doc | "pinned_probes" => [%{}]}),
          Jason.encode!(%{doc | "answers" => [%{}]}),
          Jason.encode!(put_in(doc, ["graph_snapshot", "excerpts"], [%{}]))
        ] do
      File.write!(path, bad)
      assert {:error, :corrupt_review} = ReviewStore.get(doc["id"], store)
      assert {:ok, []} = ReviewStore.list(store)
      assert File.read!(path) == bad
    end

    File.rm!(path)
    target = Path.join(dir, "external")
    File.write!(target, ReviewReport.json(doc))
    File.ln_s!(target, path)
    assert {:error, :corrupt_review} = ReviewStore.get(doc["id"], store)
    assert {:error, _} = ReviewStore.get("../external", store)
  end

  test "source and independent report drift refuse writes and never recompute history", %{
    store: store,
    dir: dir
  } do
    alias HoldLedgerReview.{Claims, Config}
    {:ok, doc, witness} = ReviewStore.create("P01", store)
    {:ok, %{review: saved}} = ReviewStore.answer_escape(doc["id"], command(doc, witness), store)
    root = Config.root()
    copy = Path.join(dir, "checkout")

    paths =
      Map.keys(Claims.snapshot().source.file_sha256) ++ Map.keys(doc["source"]["source_manifest"])

    for relative <- Enum.uniq(paths) do
      destination = Path.join(copy, relative)
      File.mkdir_p!(Path.dirname(destination))
      File.cp!(Path.join(root, relative), destination)
    end

    on_exit(fn -> Application.put_env(:hold_ledger_review_web, :ledger_root, root) end)
    Application.put_env(:hold_ledger_review_web, :ledger_root, copy)
    File.write!(Path.join(copy, "test/laws/po_b1_void_test.exs"), "\n# source drift", [:append])
    assert Config.source_matches?(copy)
    assert {:ok, stale} = ReviewStore.get(doc["id"], store)
    assert stale["status"] == "stale_read_only"
    assert stale["pinned_probes"] == saved["pinned_probes"]

    assert {:error, :stale_source} =
             ReviewStore.answer_escape(doc["id"], command(saved, witness), store)

    Application.put_env(:hold_ledger_review_web, :ledger_root, root)
    old_report = Application.get_env(:hold_ledger_review_web, :proof_report)
    on_exit(fn -> Application.put_env(:hold_ledger_review_web, :proof_report, old_report) end)

    Application.put_env(
      :hold_ledger_review_web,
      :proof_report,
      Path.join(dir, "missing-report.json")
    )

    assert {:ok, %{"status" => "stale_read_only"}} = ReviewStore.get(doc["id"], store)

    assert {:error, :stale_source} =
             ReviewStore.answer_escape(doc["id"], command(saved, witness), store)
  end

  test "multiple reviews keep their own card identities and exact witnesses", %{store: store} do
    {:ok, a, witness} = ReviewStore.create("P01", store)
    {:ok, %{review: answered}} = ReviewStore.answer_escape(a["id"], command(a, witness), store)
    {:ok, b, _} = ReviewStore.create("P04", store)
    assert b["answers"] == [] and b["pinned_probes"] == []
    assert Enum.all?(b["core_cards"], &String.starts_with?(&1["id"], "core.p04."))
    assert {:ok, ^answered} = ReviewStore.get(a["id"], store)
  end

  test "forged authority, unknown evidence, wrong card kind and ungrounded support never write",
       %{store: store} do
    {:ok, doc, witness} = ReviewStore.create("P01", store)
    forged = Map.put(command(doc, witness), "actor", "human")
    assert {:error, :invalid_command} = ReviewStore.answer_escape(doc["id"], forged, store)
    forged = Map.put(command(doc, witness), "evaluation", %{})
    assert {:error, :invalid_command} = ReviewStore.answer_escape(doc["id"], forged, store)

    assert {:error, :invalid_card} =
             ReviewStore.answer_escape(
               doc["id"],
               command(doc, witness, "core.p01.reading"),
               store
             )

    unknown =
      Map.put(card_command(doc, "reading", "accurate"), "evidence_ids", ["unknown-source"])

    assert {:error, :unknown_evidence} = ReviewStore.answer_card(doc["id"], unknown, store)
    unsupported = Map.put(card_command(doc, "assumption", "supported"), "evidence_ids", [])

    assert {:error, :supporting_evidence_required} =
             ReviewStore.answer_card(doc["id"], unsupported, store)

    assert {:error, :correction_required} =
             ReviewStore.answer_card(
               doc["id"],
               card_command(doc, "reading", "inaccurate", ""),
               store
             )

    assert {:ok, ^doc} = ReviewStore.get(doc["id"], store)
  end

  test "wrong job identity/source cannot change a pending job", %{store: store} do
    {:ok, doc, _} = ReviewStore.create("P03", store)
    {started, completion} = start_job(doc, "followup", store)

    for field <- ~w(job_id input_digest source_digest) do
      assert {:error, :invalid_job_completion} =
               ReviewStore.complete_job(doc["id"], Map.put(completion, field, "unrelated"), store)

      assert {:ok, ^started} = ReviewStore.get(doc["id"], store)
    end
  end

  test "corrupt enums and dangling answer references cannot become a positive review", %{
    store: store,
    dir: dir
  } do
    {:ok, doc, witness} = ReviewStore.create("P01", store)
    {:ok, %{review: saved}} = ReviewStore.answer_escape(doc["id"], command(doc, witness), store)
    path = Path.join(dir, doc["id"] <> ".json")
    answer = hd(saved["answers"])

    for corrupted <- [
          put_in(saved, ["source", "proof_report_snapshot", "status"], "verified_by_model"),
          Map.put(saved, "answers", [%{answer | "choice" => "approved_by_model"}]),
          Map.put(saved, "answers", [%{answer | "card_id" => "another_review_card"}]),
          Map.put(saved, "answers", [%{answer | "probe_id" => "unbound_probe"}]),
          Map.put(saved, "core_cards", [])
        ] do
      bytes = Jason.encode!(corrupted)
      File.write!(path, bytes)
      assert {:error, :corrupt_review} = ReviewStore.get(doc["id"], store)
      assert File.read!(path) == bytes
    end
  end
end
