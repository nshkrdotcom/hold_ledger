defmodule HoldLedgerReview.ReviewStoreTest do
  use ExUnit.Case, async: false
  alias HoldLedgerReview.{Adversarial, Canonical, ReviewReport, ReviewStore}

  setup do
    path = Path.join(System.tmp_dir!(), "hold-ledger-b-#{Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)}")
    File.mkdir_p!(path)
    on_exit(fn -> File.rm_rf(path) end)
    name = String.to_atom("test_review_#{:erlang.unique_integer([:positive])}")
    {:ok, pid} = start_supervised({ReviewStore, name: name, dir: path})
    {:ok, store: pid, dir: path}
  end

  defp token, do: Base.url_encode64(:crypto.strong_rand_bytes(18), padding: false)

  defp command(doc, witness, card \\ nil) do
    %{"request_id" => token(), "expected_human_revision" => doc["human_revision"],
      "card_id" => card || "core.#{String.downcase(doc["seed_id"])}.escape",
      "packet_digest" => doc["source"]["packet_digest"], "witness" => witness,
      "choice" => "unacceptable", "reason" => "Explicit policy review", "revealed_before_answer" => false}
  end

  test "atomic Escape answer binds the exact full witness, idempotency, CAS and no orphans", %{store: store, dir: dir} do
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
    assert {:ok, %{review: ^saved, answer_id: ^answer_id}} = ReviewStore.answer_escape(doc["id"], cmd, store)
    assert {:error, :request_id_conflict} = ReviewStore.answer_escape(doc["id"], %{cmd | "reason" => "different"}, store)
    assert {:error, :human_revision_conflict} = ReviewStore.answer_escape(doc["id"], command(doc, witness), store)
    {:ok, from_disk} = ReviewStore.get(doc["id"], store)
    assert from_disk == saved
    assert length(Path.wildcard(Path.join(dir, "*.json"))) == 1
    assert ReviewReport.json(saved) =~ probe_id
    assert ReviewReport.markdown(saved) =~ "Unfinished review"
  end

  test "duplicate candidate fingerprint, answer supersession, and wrong submitted packet rejection", %{store: store} do
    {:ok, doc, witness} = ReviewStore.create("P05", store)
    assert {:error, :stale_source} = ReviewStore.answer_escape(doc["id"],
      %{command(doc, witness) | "packet_digest" => "forged"}, store)
    assert {:ok, ^doc} = ReviewStore.get(doc["id"], store)
    {:ok, %{review: next, probe_id: id1}} = ReviewStore.answer_escape(doc["id"], command(doc, witness), store)
    second = %{command(next, witness) | "choice" => "acceptable"}
    assert {:ok, %{review: updated, probe_id: ^id1}} = ReviewStore.answer_escape(doc["id"], second, store)
    assert length(updated["pinned_probes"]) == 1
    assert length(updated["answers"]) == 2
    assert List.last(updated["answers"])["supersedes_answer_id"] == hd(updated["answers"])["answer_id"]
    assert updated["human_revision"] == 2
  end

  test "invalid candidate or failed write leaves no probe or answer", %{store: store} do
    {:ok, doc, witness} = ReviewStore.create("P04", store)
    forged = put_in(witness, ["output", "after", "entries"], [%{"key" => 1, "amount" => -1, "status" => "sent"}])
    assert {:error, :invalid_draft} = ReviewStore.answer_escape(doc["id"], command(doc, forged), store)
    assert {:ok, ^doc} = ReviewStore.get(doc["id"], store)
  end

  test "jobs advance document revision without stealing human CAS; stale challenge completion is discarded", %{store: store} do
    {:ok, doc, witness} = ReviewStore.create("P04", store)
    start = %{"request_id" => token(), "expected_human_revision" => 0, "job_id" => token(),
      "request_kind" => "challenge", "prompt_hash" => Canonical.digest(%{"p" => 1}),
      "input_digest" => Canonical.digest(%{"i" => 2}),
      "source_digest" => doc["source"]["compiled_source_digest"]}
    assert {:ok, %{review: started}} = ReviewStore.start_job(doc["id"], start, store)
    assert started["document_revision"] == 2 and started["human_revision"] == 1
    assert {:ok, %{review: answered}} = ReviewStore.answer_escape(doc["id"], command(started, witness), store)
    result = %{"job_id" => start["job_id"], "input_digest" => start["input_digest"],
      "source_digest" => start["source_digest"], "validated_output" => nil, "error_class" => nil}
    assert {:ok, completed} = ReviewStore.complete_job(doc["id"], result, store)
    assert List.last(completed["ai_jobs"])["status"] == "discarded_late"
    assert completed["human_revision"] == answered["human_revision"]
    assert completed["document_revision"] == answered["document_revision"] + 1
    assert {:ok, ^completed} = ReviewStore.complete_job(doc["id"],
      %{result | "error_class" => "stale_job_context"}, store)
  end

  test "positive conclusion requires all mandatory and critical answers and scoped evidence", %{store: store} do
    {:ok, doc, _witness} = ReviewStore.create("P03", store)
    finish = %{"request_id" => token(), "expected_human_revision" => 0,
      "outcome" => "meets_intent_in_reviewed_scope", "scope" => "policy.events.07",
      "rationale" => "Human reviewed bounds", "evidence_ids" => [], "confirmed" => true}
    assert {:error, :unanswered_mandatory_or_critical} = ReviewStore.finish_review(doc["id"], finish, store)
    assert {:ok, ^doc} = ReviewStore.get(doc["id"], store)
  end

  test "corrupt persisted job shape is rejected without a restart crash", %{store: store, dir: dir} do
    {:ok, doc, _} = ReviewStore.create("P01", store)
    path = Path.join(dir, doc["id"] <> ".json")
    broken = Map.put(doc, "ai_jobs", [42])
    File.write!(path, Jason.encode!(broken))
    assert {:error, :corrupt_review} = ReviewStore.get(doc["id"], store)
    assert {:ok, []} = ReviewStore.list(store)
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
    {:ok, counter} = Agent.start_link(fn -> 0 end)
    writer = fn file, bytes ->
      n = Agent.get_and_update(counter, &{&1, &1 + 1})
      if n == 0, do: ReviewStore.atomic_write(file, bytes), else: {:error, :disk_full}
    end
    {:ok, pid} = start_supervised(Supervisor.child_spec({ReviewStore, name: nil, dir: path, writer: writer}, id: :writer_store))
    {:ok, doc, witness} = ReviewStore.create("P01", pid)
    assert {:error, :write_failed} = ReviewStore.answer_escape(doc["id"], command(doc, witness), pid)
    assert {:ok, ^doc} = ReviewStore.get(doc["id"], pid)
    assert length(Path.wildcard(Path.join(path, "*.tmp"))) == 0
  end
end
