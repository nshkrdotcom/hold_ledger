defmodule HoldLedgerReview.Part3Store do
  @moduledoc """
  Single JSON writer for versioned packages. Human edits are CAS-protected;
  source identity and immutable package context are never updated by a job.
  Every command has completion-digest idempotency and atomic file persistence.
  Unsupported prior schemas are refused, not migrated.
  """
  use GenServer

  alias HoldLedgerReview.{
    Adversarial,
    Canonical,
    Claims,
    Config,
    Part3AI,
    Part3Diagnostics,
    Part3Package,
    Part3Result,
    Part3Snapshots,
    Part3Verification,
    ReviewStore
  }

  @max_bytes 5_000_000
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, if(name, do: [name: name], else: []))
  end

  @impl true
  def init(opts) do
    dir = Keyword.get(opts, :dir, Path.join(Config.root(), "tmp/review_studio/packages"))

    with :ok <- File.mkdir_p(dir), {:ok, %{type: :directory}} <- File.lstat(dir) do
      {:ok, %{dir: dir, writer: Keyword.get(opts, :writer, &ReviewStore.atomic_write/2)},
       {:continue, :interrupt}}
    else
      _ -> {:stop, :unsafe_package_directory}
    end
  end

  @impl true
  def handle_continue(:interrupt, state) do
    for path <- Path.wildcard(Path.join(state.dir, "*.json")),
        {:ok, package} <- [read(state, Path.basename(path, ".json"))] do
      updated =
        package
        |> Map.update!("replay_attempts", &Enum.map(&1, fn a -> interrupt(a) end))
        |> Map.update!("verification_attempts", &Enum.map(&1, fn a -> interrupt(a) end))

      updated =
        Map.update!(
          updated,
          "ai_history",
          &Enum.map(&1, fn
            %{"status" => "running"} = job ->
              %{
                job
                | "status" => "interrupted",
                  "error" => "interrupted_on_restart",
                  "finished_at" => Part3Package.now()
              }

            job ->
              job
          end)
        )

      if updated != package, do: persist(state, bump(updated, false))
    end

    {:noreply, state}
  end

  defp interrupt(%{"status" => status} = a) when status in ~w(queued running),
    do: %{
      a
      | "status" => "interrupted",
        "finished_at" => Part3Package.now(),
        "diagnostics" => "worker_interrupted_on_restart"
    }

  defp interrupt(a), do: a

  def create(baseline, proposal, server \\ __MODULE__),
    do: GenServer.call(server, {:create, baseline, proposal}, 120_000)

  def get(id, server \\ __MODULE__), do: GenServer.call(server, {:get, id}, 60_000)
  def list(server \\ __MODULE__), do: GenServer.call(server, :list, 60_000)

  def finding(id, cmd, server \\ __MODULE__),
    do: GenServer.call(server, {:human, id, "finding", cmd}, 60_000)

  def conclude(id, cmd, server \\ __MODULE__),
    do: GenServer.call(server, {:human, id, "conclude", cmd}, 60_000)

  def queue_replay(id, witness, server \\ __MODULE__),
    do: GenServer.call(server, {:queue_replay, id, witness}, 120_000)

  def queue_verification(id, server \\ __MODULE__),
    do: GenServer.call(server, {:queue_verification, id}, 120_000)

  def running(id, attempt_id, server \\ __MODULE__),
    do: GenServer.call(server, {:running, id, attempt_id})

  def complete_replay(id, attempt_id, result, server \\ __MODULE__),
    do: GenServer.call(server, {:complete_replay, id, attempt_id, result}, 120_000)

  def complete_verification(id, attempt_id, report_path, server \\ __MODULE__),
    do: GenServer.call(server, {:complete_verification, id, attempt_id, report_path}, 120_000)

  def fail_attempt(id, attempt_id, reason, server \\ __MODULE__),
    do: GenServer.call(server, {:fail, id, attempt_id, reason})

  def pin(id, witness, server \\ __MODULE__), do: GenServer.call(server, {:pin, id, witness})

  def begin_ai(id, revision, packet, server \\ __MODULE__),
    do: GenServer.call(server, {:begin_ai, id, revision, packet})

  def finish_ai(id, job_id, result, server \\ __MODULE__),
    do: GenServer.call(server, {:finish_ai, id, job_id, result})

  def accept_question(id, cmd, server \\ __MODULE__),
    do: GenServer.call(server, {:human, id, "accept_question", cmd})

  def ingest_artifacts(id, relative, server \\ __MODULE__),
    do: GenServer.call(server, {:ingest_artifacts, id, relative}, 120_000)

  @impl true
  def handle_call({:ingest_artifacts, id, relative}, _from, state) do
    reply =
      with {:ok, p} <- read(state, id),
           :ok <- freshness(p),
           true <- is_nil(p["conclusion"]) and length(p["verification_attempts"]) < 149,
           {:ok, intake} <-
             Part3Verification.inspect_index(p["proposal"]["snapshot_id"], relative) do
        retain_intake(state, p, intake)
      else
        _ -> {:error, :artifact_intake_refused}
      end

    {:reply, reply, state}
  end

  @impl true
  def handle_call({:create, baseline, proposal}, _from, state) do
    id = fresh_id()

    reply =
      with {:ok, doc} <- Part3Package.new(id, baseline, proposal),
           :ok <- persist(state, doc),
           do: {:ok, doc}

    {:reply, reply, state}
  end

  def handle_call({:get, id}, _from, state) do
    reply = with {:ok, p} <- read(state, id), do: {:ok, p, freshness(p)}
    {:reply, reply, state}
  end

  def handle_call(:list, _from, state) do
    rows =
      for path <- Path.wildcard(Path.join(state.dir, "*.json")),
          {:ok, p} <- [read(state, Path.basename(path, ".json"))],
          do: %{
            "id" => p["id"],
            "updated_at" => p["updated_at_utc"],
            "baseline_id" => p["baseline"]["snapshot_id"],
            "proposal_id" => p["proposal"]["snapshot_id"],
            "human_revision" => p["human_revision"],
            "conclusion" => p["conclusion"]
          }

    {:reply, {:ok, Enum.sort_by(rows, & &1["updated_at"], :desc)}, state}
  end

  def handle_call({:human, id, kind, cmd}, _from, state) do
    reply = with {:ok, package} <- read(state, id), do: human(state, package, kind, cmd)
    {:reply, reply, state}
  end

  def handle_call({:pin, id, witness}, _from, state) do
    reply =
      with {:ok, p} <- read(state, id),
           :ok <- freshness(p),
           {:ok, decoded} <- Adversarial.decode(witness),
           {:ok, reencoded} <- Adversarial.encode(decoded),
           true <- reencoded == witness and HoldLedger.Spec.valid?(decoded.before),
           true <- is_nil(p["conclusion"]) do
        pin_witness(state, p, witness)
      else
        _ -> {:error, :invalid_or_stale_pin}
      end

    {:reply, reply, state}
  end

  def handle_call({:begin_ai, id, revision, packet}, _from, state) do
    reply =
      with {:ok, p} <- read(state, id),
           :ok <- freshness(p),
           true <- revision == p["human_revision"] and is_nil(p["conclusion"]),
           true <- not Enum.any?(p["ai_history"], &(&1["status"] == "running")),
           true <- length(p["ai_history"]) < 100,
           :ok <- Part3AI.fresh?(p, packet) do
        job = %{
          "id" => fresh_id(),
          "status" => "running",
          "context_digest" => p["context_digest"],
          "human_revision_at_request" => revision,
          "prompt_sha256" => packet.prompt_sha256,
          "followup_context" => packet.followup_context,
          "input_digest" => packet.input_digest,
          "result" => nil,
          "error" => "",
          "created_at" => Part3Package.now(),
          "finished_at" => nil
        }

        updated = Map.update!(p, "ai_history", &(&1 ++ [job])) |> bump(false)
        with :ok <- persist(state, updated), do: {:ok, updated, job}
      else
        _ -> {:error, :consent_context_or_ai_busy}
      end

    {:reply, reply, state}
  end

  def handle_call({:finish_ai, id, job_id, result}, _from, state) do
    reply =
      with {:ok, p} <- read(state, id),
           job when is_map(job) <- Enum.find(p["ai_history"], &(&1["id"] == job_id)),
           true <- job["status"] == "running" do
        finish_model_job(state, p, job, result, job_id)
      else
        _ -> {:error, :late_or_unknown_model_completion}
      end

    {:reply, reply, state}
  end

  def handle_call({:queue_replay, id, witness}, _from, state) do
    reply =
      with {:ok, p} <- read(state, id),
           :ok <- freshness(p),
           {:ok, decoded} <- Adversarial.decode(witness),
           {:ok, canonical} <- Adversarial.encode(decoded),
           true <- canonical == witness and HoldLedger.Spec.valid?(decoded.before),
           true <- is_nil(p["conclusion"]),
           true <- not Enum.any?(p["replay_attempts"], &(&1["status"] in ~w(queued running))) do
        queue_pair(state, p, witness)
      else
        false -> {:error, :invalid_or_busy_replay}
        error -> error
      end

    {:reply, reply, state}
  end

  def handle_call({:queue_verification, id}, _from, state) do
    reply =
      with {:ok, p} <- read(state, id),
           :ok <- freshness(p),
           true <- is_nil(p["conclusion"]),
           true <-
             not Enum.any?(p["verification_attempts"], &(&1["status"] in ~w(queued running))),
           true <- length(p["verification_attempts"]) < 130 do
        digest =
          Canonical.digest(%{
            "context" => p["context_digest"],
            "scope" => "full_required_catalog"
          })

        a =
          attempt(
            "acceptance",
            p["proposal"]["snapshot_id"],
            p["context_digest"],
            digest,
            "full_required_catalog",
            nil
          )

        updated = Map.update!(p, "verification_attempts", &(&1 ++ [a])) |> bump(false)
        with :ok <- persist(state, updated), do: {:ok, updated, a}
      else
        false -> {:error, :verification_busy_or_closed}
        err -> err
      end

    {:reply, reply, state}
  end

  def handle_call({:running, id, aid}, _from, state) do
    {:reply,
     update_attempt(state, id, aid, fn a ->
       if a["status"] == "queued",
         do: {:ok, %{a | "status" => "running", "started_at" => Part3Package.now()}},
         else: {:error, :attempt_not_queued}
     end), state}
  end

  def handle_call({:complete_replay, id, aid, result}, _from, state) do
    reply =
      with {:ok, p} <- read(state, id),
           :ok <- freshness(p),
           a when is_map(a) <- Enum.find(p["replay_attempts"], &(&1["id"] == aid)),
           true <- a["status"] == "running",
           :ok <- Part3Result.validate(result, p, a, a["witness"]) do
        done = %{
          a
          | "status" => "succeeded",
            "finished_at" => Part3Package.now(),
            "result" => result,
            "completion_digest" => result["completion_digest"]
        }

        updated = Map.update!(p, "replay_attempts", &replace_record(&1, aid, done))
        updated = add_diagnostics(updated, a["input_digest"])
        updated = bump(updated, false)
        with :ok <- persist(state, updated), do: {:ok, updated}
      else
        false -> {:error, :late_or_terminal_completion}
        _ -> {:error, :invalid_or_late_replay_completion}
      end

    {:reply, reply, state}
  end

  def handle_call({:complete_verification, id, aid, report_path}, _from, state) do
    reply =
      with {:ok, p} <- read(state, id),
           :ok <- freshness(p),
           a when is_map(a) <- Enum.find(p["verification_attempts"], &(&1["id"] == aid)),
           true <- a["status"] == "running",
           true <- a["kind"] == "acceptance",
           {:ok, activities} <- Part3Verification.inspect_report(a["snapshot_id"], report_path) do
        acceptance = hd(activities)["acceptance_status"]
        success = acceptance == "full_catalog_checked"
        completion = Canonical.digest(%{"report" => activities, "context" => p["context_digest"]})

        done = %{
          a
          | "status" => if(success, do: "succeeded", else: "failed"),
            "finished_at" => Part3Package.now(),
            "completion_digest" => completion,
            "diagnostics" => "existing_gate_status:" <> acceptance,
            "artifacts" => [hd(activities)["report"]],
            "result" => %{"acceptance_status" => acceptance}
        }

        sub =
          Enum.map(activities, &activity_attempt(&1, a, p, completion, acceptance))

        updated =
          p
          |> Map.update!(
            "verification_attempts",
            &(replace_record(&1, aid, done) ++ sub)
          )
          |> bump(false)

        with :ok <- persist(state, updated), do: {:ok, updated}
      else
        false -> {:error, :late_or_terminal_completion}
        _ -> {:error, :verification_evidence_unavailable}
      end

    {:reply, reply, state}
  end

  def handle_call({:fail, id, aid, reason}, _from, state) do
    {:reply, update_attempt(state, id, aid, &failed_attempt(&1, reason)), state}
  end

  defp dependencies("source_extraction"), do: []
  defp dependencies("pointwise_execution"), do: ["source_extraction"]
  defp dependencies("elaboration"), do: ["source_extraction"]
  defp dependencies("export"), do: ["elaboration"]
  defp dependencies("checker"), do: ["export"]
  defp dependencies("acceptance"), do: ["checker"]
  defp dependencies(_), do: []

  defp attempt(kind, sid, context, input, scope, witness) do
    %{
      "id" => fresh_id(),
      "kind" => kind,
      "snapshot_id" => sid,
      "context_digest" => context,
      "scope" => scope,
      "status" => "queued",
      "producer" =>
        if(kind == "replay",
          do: "local_isolated_mix_runner_v1",
          else: "existing_run_laws_full_gate_v1"
        ),
      "queued_at" => Part3Package.now(),
      "started_at" => nil,
      "finished_at" => nil,
      "input_digest" => input,
      "completion_digest" => nil,
      "artifacts" => [],
      "diagnostics" => "",
      "dependencies" => dependencies(kind),
      "witness" => witness,
      "result" => nil
    }
  end

  defp add_diagnostics(p, input_id) do
    pairs =
      Enum.filter(
        p["replay_attempts"],
        &(&1["input_digest"] == input_id and &1["status"] == "succeeded")
      )

    a = Enum.find(pairs, &(&1["snapshot_id"] == p["baseline"]["snapshot_id"]))
    b = Enum.find(pairs, &(&1["snapshot_id"] == p["proposal"]["snapshot_id"]))

    if a && b do
      findings = Part3Diagnostics.compare(p, a["witness"], a["result"], b["result"])

      Map.update!(p, "evidence", &merge_evidence(&1, findings))
    else
      p
    end
  end

  defp update_attempt(state, id, aid, fun) do
    with {:ok, p} <- read(state, id),
         :ok <- freshness(p),
         {kind, attempt} when is_map(attempt) <- locate(p, aid),
         {:ok, updated} <- fun.(attempt) do
      p =
        Map.update!(p, kind, &replace_record(&1, aid, updated))
        |> bump(false)

      with :ok <- persist(state, p), do: {:ok, p}
    else
      _ -> {:error, :attempt_unavailable_or_stale}
    end
  end

  defp locate(p, aid) do
    case Enum.find(p["replay_attempts"], &(&1["id"] == aid)) do
      nil -> {"verification_attempts", Enum.find(p["verification_attempts"], &(&1["id"] == aid))}
      a -> {"replay_attempts", a}
    end
  end

  defp human(state, p, kind, cmd) do
    with true <- is_map(cmd) and Enum.all?(Map.keys(cmd), &is_binary/1),
         true <- Part3Package.id?(cmd["request_id"]) do
      digest = Canonical.digest(%{"kind" => kind, "command" => cmd})

      case Enum.find(p["human_commands"], &(&1["request_id"] == cmd["request_id"])) do
        nil -> new_human(state, p, kind, cmd, digest)
        %{"digest" => ^digest} -> {:ok, p}
        _ -> {:error, :request_id_conflict}
      end
    else
      _ -> {:error, :invalid_human_command}
    end
  rescue
    _ -> {:error, :invalid_human_command}
  end

  defp new_human(state, p, kind, cmd, digest) do
    with true <- cmd["expected_human_revision"] == p["human_revision"],
         :ok <- freshness(p),
         true <- is_nil(p["conclusion"]),
         {:ok, updated} <- apply_human(p, kind, cmd) do
      record = %{
        "request_id" => cmd["request_id"],
        "digest" => digest,
        "human_revision" => p["human_revision"] + 1,
        "kind" => kind
      }

      updated = Map.update!(updated, "human_commands", &(&1 ++ [record])) |> bump(true)
      with :ok <- persist(state, updated), do: {:ok, updated}
    else
      false -> {:error, :human_revision_conflict_or_closed}
      other -> other
    end
  end

  defp apply_human(p, "finding", cmd) do
    required =
      ~w(request_id expected_human_revision lens status rationale scope evidence_ids change_ids presentation revealed_before_answer)

    with true <- Enum.sort(Map.keys(cmd)) == Enum.sort(required),
         true <-
           cmd["lens"] in ~w(reading alternative_behavior evidence_scope excluded_inputs outside_assumptions),
         true <- cmd["status"] in ~w(addressed not_applicable unresolved),
         true <-
           cmd["presentation"] in ~w(expert learning) and
             is_boolean(cmd["revealed_before_answer"]),
         true <- is_binary(cmd["rationale"]) and byte_size(cmd["rationale"]) in 5..1200,
         true <- is_binary(cmd["scope"]) and byte_size(cmd["scope"]) in 1..600,
         true <-
           Enum.all?(cmd["evidence_ids"], &Enum.any?(p["evidence"], fn e -> e["id"] == &1 end)),
         true <-
           Enum.all?(
             cmd["change_ids"],
             &Enum.any?(p["source_changes"], fn e -> e["id"] == &1 end)
           ) do
      finding = %{
        "id" => fresh_id(),
        "lens" => cmd["lens"],
        "status" => cmd["status"],
        "rationale" => cmd["rationale"],
        "scope" => cmd["scope"],
        "evidence_ids" => cmd["evidence_ids"],
        "change_ids" => cmd["change_ids"],
        "human_revision" => p["human_revision"] + 1,
        "created_at" => Part3Package.now(),
        "presentation" => cmd["presentation"],
        "revealed_before_answer" => cmd["revealed_before_answer"]
      }

      {:ok, Map.update!(p, "human_findings", &(&1 ++ [finding]))}
    else
      _ -> {:error, :invalid_finding}
    end
  end

  defp apply_human(p, "conclude", cmd) do
    required =
      ~w(request_id expected_human_revision outcome scope rationale evidence_ids confirmed)

    with true <- Enum.sort(Map.keys(cmd)) == Enum.sort(required) and cmd["confirmed"] == true,
         true <-
           cmd["outcome"] in ~w(meets_intent_in_reviewed_scope needs_design_change needs_policy_or_evidence),
         true <- is_binary(cmd["scope"]) and byte_size(cmd["scope"]) in 1..600,
         true <- is_binary(cmd["rationale"]) and byte_size(cmd["rationale"]) in 5..1200,
         true <-
           is_list(cmd["evidence_ids"]) and
             Enum.all?(cmd["evidence_ids"], &Enum.any?(p["evidence"], fn e -> e["id"] == &1 end)),
         true <- cmd["outcome"] != "meets_intent_in_reviewed_scope" or positive_ready?(p, cmd) do
      conclusion = %{
        "outcome" => cmd["outcome"],
        "scope" => cmd["scope"],
        "rationale" => cmd["rationale"],
        "evidence_ids" => cmd["evidence_ids"],
        "confirmed_at" => Part3Package.now(),
        "human_revision" => p["human_revision"] + 1
      }

      {:ok, Map.put(p, "conclusion", conclusion)}
    else
      _ -> {:error, :unresolved_or_invalid_conclusion}
    end
  end

  defp apply_human(p, "accept_question", cmd) do
    required = ~w(request_id expected_human_revision job_id proposal_id)

    with true <- Enum.sort(Map.keys(cmd)) == Enum.sort(required),
         job when is_map(job) <-
           Enum.find(
             p["ai_history"],
             &(&1["id"] == cmd["job_id"] and &1["status"] == "succeeded")
           ),
         proposal when is_map(proposal) <-
           Enum.find(job["result"]["proposals"], &(&1["proposal_id"] == cmd["proposal_id"])) do
      accepted = %{
        "id" => fresh_id(),
        "source_job_id" => job["id"],
        "source_proposal_id" => proposal["proposal_id"],
        "question" => proposal["question"],
        "kind" => proposal["kind"],
        "human_revision" => p["human_revision"] + 1,
        "accepted_at" => Part3Package.now()
      }

      {:ok, Map.update!(p, "accepted_questions", &(&1 ++ [accepted]))}
    else
      _ -> {:error, :invalid_or_stale_proposed_question}
    end
  end

  defp apply_human(_, _, _), do: {:error, :unknown_human_command}

  defp positive_ready?(p, cmd) do
    # Previous failed attempts remain immutable historical evidence. A
    # genuinely newer successful retry for the identical snapshot/activity/
    # input can resolve that outstanding attempt; it must not erase history.
    latest =
      (p["replay_attempts"] ++ p["verification_attempts"])
      |> Enum.group_by(&{&1["kind"], &1["snapshot_id"], &1["input_digest"]})
      |> Map.values()
      |> Enum.map(&List.last/1)

    Enum.all?(Part3Diagnostics.triage(p), &(&1["status"] in ~w(addressed not_applicable))) and
      cmd["evidence_ids"] != [] and
      not Enum.any?(latest, &(&1["status"] in ~w(queued running failed interrupted)))
  end

  defp freshness(p) do
    with :ok <- Claims.freshness(),
         {:ok, a} <- Part3Snapshots.load(p["baseline"]["snapshot_id"]),
         {:ok, b} <- Part3Snapshots.load(p["proposal"]["snapshot_id"]),
         true <- a == p["baseline"] and b == p["proposal"],
         true <- Part3Snapshots.trusted_analysis?(a) and Part3Snapshots.trusted_analysis?(b) do
      :ok
    else
      _ -> {:error, :snapshot_or_environment_drift}
    end
  end

  defp read(state, id) do
    with true <- Part3Package.id?(id),
         path = Path.join(state.dir, id <> ".json"),
         {:ok, %{type: :regular, size: bytes}} <- File.lstat(path),
         true <- bytes <= @max_bytes,
         {:ok, raw} <- File.read(path),
         {:ok, doc} <- Jason.decode(raw),
         true <- Part3Package.valid?(doc, id) do
      {:ok, doc}
    else
      {:error, :enoent} -> {:error, :not_found}
      _ -> {:error, :corrupt_or_unsupported_package}
    end
  end

  defp persist(state, p) do
    if Part3Package.valid?(p, p["id"]),
      do: persist_bytes(state, p),
      else: {:error, :invalid_package}
  end

  defp persist_bytes(state, p) do
    raw = Canonical.json(p) <> "\n"

    if byte_size(raw) > @max_bytes,
      do: {:error, :package_limit},
      else: write_package(state, p, raw)
  end

  defp write_package(state, p, raw) do
    path = Path.join(state.dir, p["id"] <> ".json")

    with valid_file <- File.lstat(path),
         true <- match?({:ok, %{type: :regular}}, valid_file) or valid_file == {:error, :enoent},
         :ok <- state.writer.(path, raw) do
      broadcast(p["id"])
      :ok
    else
      _ -> {:error, :write_failed}
    end
  end

  defp broadcast(id) do
    if Process.whereis(HoldLedgerReview.PubSub),
      do: Phoenix.PubSub.broadcast(HoldLedgerReview.PubSub, "part3:" <> id, {:part3_updated, id})
  end

  defp bump(p, human?) do
    p
    |> Map.update!("document_revision", &(&1 + 1))
    |> Map.update!("human_revision", &(&1 + if(human?, do: 1, else: 0)))
    |> Map.put("updated_at_utc", Part3Package.now())
  end

  defp fresh_id, do: Base.url_encode64(:crypto.strong_rand_bytes(18), padding: false)

  defp retain_intake(state, p, intake) do
    digest = Canonical.digest(intake)
    existing = Enum.find(p["verification_attempts"], &(&1["completion_digest"] == digest))

    if existing do
      {:ok, p}
    else
      a =
        attempt(
          "source_extraction",
          p["proposal"]["snapshot_id"],
          p["context_digest"],
          digest,
          "full_required_catalog",
          nil
        )

      artifacts =
        [intake["index"]] ++
          List.wrap(intake["report"]) ++
          Enum.map(intake["artifacts"], &Map.take(&1, ~w(path sha256 bytes)))

      done = %{
        a
        | "status" => "succeeded",
          "producer" => intake["producer"],
          "started_at" => Part3Package.now(),
          "finished_at" => Part3Package.now(),
          "completion_digest" => digest,
          "artifacts" => artifacts,
          "result" => intake,
          "diagnostics" => "artifact_intake_only:" <> intake["acceptance_status"]
      }

      updated = Map.update!(p, "verification_attempts", &(&1 ++ [done])) |> bump(false)
      with :ok <- persist(state, updated), do: {:ok, updated}
    end
  end

  defp pin_witness(state, p, witness) do
    digest = Canonical.digest(witness)
    existing = Enum.find(p["pinned_examples"], &(&1["input_digest"] == digest))

    if existing do
      {:ok, p, existing}
    else
      pin = %{
        "id" => fresh_id(),
        "witness" => witness,
        "input_digest" => digest,
        "context_digest" => p["context_digest"],
        "pinned_at" => Part3Package.now()
      }

      updated = Map.update!(p, "pinned_examples", &(&1 ++ [pin])) |> bump(false)
      with :ok <- persist(state, updated), do: {:ok, updated, pin}
    end
  end

  defp finish_model_job(state, p, job, result, job_id) do
    stale =
      p["human_revision"] != job["human_revision_at_request"] or
        freshness(p) != :ok or not is_nil(p["conclusion"])

    checked = validate_model_result(result, p, job)

    done =
      case checked do
        {:ok, output} ->
          %{
            job
            | "status" => if(stale, do: "stale", else: "succeeded"),
              "result" => output,
              "finished_at" => Part3Package.now()
          }

        {:error, reason} ->
          %{
            job
            | "status" => "failed",
              "error" => inspect(reason) |> String.slice(0, 180),
              "finished_at" => Part3Package.now()
          }
      end

    updated =
      Map.update!(
        p,
        "ai_history",
        &Enum.map(&1, fn a -> if a["id"] == job_id, do: done, else: a end)
      )
      |> bump(false)

    with :ok <- persist(state, updated), do: {:ok, updated}
  end

  defp validate_model_result(result, p, job) do
    case result do
      {:ok, output} when is_map(output) ->
        with {:ok, packet} <- Part3AI.prepare(p, job["followup_context"]),
             true <-
               packet.input_digest == job["input_digest"] and
                 packet.prompt_sha256 == job["prompt_sha256"],
             :ok <- Part3AI.validate(output, packet) do
          {:ok, output}
        else
          _ -> {:error, :unvalidated_or_stale_model_proposal}
        end

      {:error, reason} ->
        {:error, reason}

      _ ->
        {:error, :invalid_model_completion}
    end
  end

  defp queue_pair(state, p, witness) do
    digest = Canonical.digest(witness)
    # Successful, previously validated evidence for the *complete* immutable
    # package and typed input may be reused. No failure or stale context is
    # cached, and no duplicate worker is launched for a completed pair.
    cached = Enum.all?(~w(baseline proposal), &cached_role?(p, &1, digest))

    if cached do
      {:ok, p, []}
    else
      new_pair(state, p, witness, digest)
    end
  end

  defp new_pair(state, p, witness, digest) do
    if length(p["replay_attempts"]) <= 146 do
      attempts =
        for role <- ~w(baseline proposal) do
          attempt(
            "replay",
            p[role]["snapshot_id"],
            p["context_digest"],
            digest,
            "example:" <> String.slice(digest, 0, 20),
            witness
          )
        end

      updated = Map.update!(p, "replay_attempts", &(&1 ++ attempts)) |> bump(false)
      with :ok <- persist(state, updated), do: {:ok, updated, attempts}
    else
      {:error, :replay_history_limit}
    end
  end

  defp cached_role?(p, role, digest) do
    sid = p[role]["snapshot_id"]

    Enum.any?(p["replay_attempts"], fn a ->
      a["snapshot_id"] == sid and a["input_digest"] == digest and a["status"] == "succeeded"
    end)
  end

  defp activity_attempt(activity, a, p, completion, acceptance) do
    child =
      attempt(
        activity["kind"],
        a["snapshot_id"],
        p["context_digest"],
        a["input_digest"],
        "full_required_catalog",
        nil
      )

    %{
      child
      | "status" => activity["status"],
        "started_at" => a["started_at"],
        "finished_at" => Part3Package.now(),
        "completion_digest" => completion,
        "artifacts" => [activity["report"]],
        "diagnostics" => "existing_gate_status:" <> acceptance,
        "result" => %{"acceptance_status" => acceptance},
        "dependencies" => dependencies(activity["kind"])
    }
  end

  defp failed_attempt(a, reason) do
    if a["status"] in ~w(queued running) do
      status =
        if reason in [:cancelled, :timeout, :worker_crash, :port_closed],
          do: "interrupted",
          else: "failed"

      {:ok,
       %{
         a
         | "status" => status,
           "finished_at" => Part3Package.now(),
           "diagnostics" => to_string(reason) |> String.slice(0, 1200)
       }}
    else
      {:error, :late_or_terminal_completion}
    end
  end

  defp merge_evidence(existing, findings) do
    Enum.reduce(findings, existing, fn item, all ->
      if Enum.any?(all, &(&1["id"] == item["id"])), do: all, else: all ++ [item]
    end)
  end

  defp replace_record(records, id, updated) do
    Enum.map(records, fn record -> if record["id"] == id, do: updated, else: record end)
  end
end
