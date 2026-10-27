defmodule HoldLedgerReview.ReviewStore do
  @moduledoc """
  A single writer for one current JSON document per localhost review.
  Human commands CAS on human_revision, not document_revision. The original
  document is not touched until a fully encoded replacement is synced and
  atomically renamed. There is no old-format reader or migration.
  """
  use GenServer
  alias HoldLedgerReview.{Adversarial, Anchor, Canonical, Claims, Config, DesignGraph, Dossier, ProofEvidence}

  @id_pattern ~r/\A[A-Za-z0-9_-]{16,80}\z/
  @max_bytes 4_000_000
  @allowed_answers ~w(command review_id request_id expected_human_revision card_id packet_digest witness choice reason revealed_before_answer)
  @allowed_card_answers ~w(request_id expected_human_revision card_id choice reason evidence_ids revealed_before_answer)
  @allowed_pin ~w(request_id expected_human_revision packet_digest witness)
  @allowed_finish ~w(request_id expected_human_revision outcome scope rationale evidence_ids confirmed)
  @allowed_start_job ~w(request_id expected_human_revision job_id request_kind prompt_hash input_digest source_digest)

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, if(name, do: [name: name], else: []))
  end

  @impl true
  def init(opts) do
    dir = Keyword.get(opts, :dir, Application.get_env(:hold_ledger_review_web, :review_store_dir,
      Path.join(Config.root(), "tmp/review_studio/reviews")))
    with :ok <- File.mkdir_p(dir),
         {:ok, %{type: :directory}} <- File.lstat(dir) do
      state = %{dir: Path.expand(dir), writer: Keyword.get(opts, :writer, &atomic_write/2)}
      {:ok, state, {:continue, :interrupt_pending}}
    else
      _ -> {:stop, :unsafe_review_directory}
    end
  end

  @impl true
  def handle_continue(:interrupt_pending, state) do
    # Jobs are never implicitly re-sent after a process restart.
    for path <- Path.wildcard(Path.join(state.dir, "*.json")) do
      case File.lstat(path) do
        {:ok, %{type: :regular}} ->
          id = path |> Path.basename(".json")
          case read(state, id) do
            {:ok, doc} ->
              if Enum.any?(doc["ai_jobs"], &(&1["status"] == "pending")) and current?(doc) do
                jobs = Enum.map(doc["ai_jobs"], fn j ->
                  if j["status"] == "pending", do: %{j | "status" => "interrupted", "error_class" => "process_restart"}, else: j
                end)
                updated = doc |> Map.put("ai_jobs", jobs) |> bump(false)
                _ = persist(state, updated)
              end
            _ -> :ok
          end
        _ -> :ok
      end
    end
    {:noreply, state}
  end

  def create(seed_id, server \\ __MODULE__), do: GenServer.call(server, {:create, seed_id}, 60_000)
  def get(id, server \\ __MODULE__), do: GenServer.call(server, {:get, id})
  def list(server \\ __MODULE__), do: GenServer.call(server, :list)
  def answer_escape(id, command, server \\ __MODULE__)
  def answer_escape(id, command, server) when is_map(command) do
    # Public Escape commands carry the exact current answer_escape schema envelope.
    # The LiveView passes only trusted server-constructed fields; callers cannot
    # replace either the command kind or the review being mutated.
    enriched = command |> Map.put_new("command", "answer_escape") |> Map.put_new("review_id", id)
    human(server, id, "answer_escape", enriched)
  end
  def answer_escape(_id, _command, _server), do: {:error, :invalid_command}
  def answer_card(id, command, server \\ __MODULE__), do: human(server, id, "answer_card", command)
  def pin_candidate(id, command, server \\ __MODULE__), do: human(server, id, "pin_candidate", command)
  def finish_review(id, command, server \\ __MODULE__), do: human(server, id, "finish_review", command)
  def start_job(id, command, server \\ __MODULE__), do: human(server, id, "start_job", command)
  def accept_ai_card(id, command, server \\ __MODULE__), do: human(server, id, "accept_ai_card", command)
  def add_human_card(id, command, server \\ __MODULE__), do: human(server, id, "add_human_card", command)
  def complete_job(id, completion, server \\ __MODULE__), do: GenServer.call(server, {:complete_job, id, completion}, 60_000)

  defp human(server, id, kind, command), do: GenServer.call(server, {:human, id, kind, command}, 60_000)

  @impl true
  def handle_call({:create, seed}, _from, state) do
    reply = with {:ok, witness} <- Adversarial.seed(seed),
                 {:ok, graph} <- DesignGraph.build(),
                 :ok <- Claims.freshness() do
      id = fresh_id()
      generation = Claims.snapshot()
      cards = Dossier.for_seed(seed, graph)
      packet = Canonical.digest(%{"seed_id" => seed,
        "source_digest" => generation.source.sha256,
        "policy_nodes" => Enum.map(cards, & &1["target_node_id"]) |> Enum.uniq()})
      manifest = graph["excerpts"] |> Map.new(&{&1["path"], &1["sha256"]})
      proof = ProofEvidence.load(Config.root(), Application.get_env(:hold_ledger_review_web, :proof_report),
        Enum.map(generation.source.catalog, & &1["slug"]))
      doc = %{
        "id" => id, "seed_id" => seed, "document_revision" => 1, "human_revision" => 0,
        "target_policy_nodes" => Enum.uniq(Enum.map(cards, & &1["target_node_id"])),
        "status" => "in_progress",
        "source" => %{"packet_digest" => packet,
          "compiled_source_digest" => generation.source.sha256,
          "evaluator_id" => generation.evaluator_id,
          "source_manifest" => manifest, "prompt_digests" => %{},
          "proof_report_snapshot" => %{"status" => Atom.to_string(proof.status),
            "detail" => String.slice(proof.detail, 0, 300),
            "report_sha256" => Map.get(proof, :report_sha256)}},
        "graph_snapshot" => graph, "core_cards" => cards,
        "accepted_ai_cards" => [], "suggested_ai_cards" => [],
        "pinned_probes" => [], "answers" => [], "human_commands" => [], "ai_jobs" => [],
        "review_conclusion" => nil,
        "created_at_utc" => now(), "updated_at_utc" => now()
      }
      # A seed is merely a starting hypothetical, not an automatically pinned observation.
      case persist(state, doc) do
        :ok -> {:ok, doc, witness}
        err -> err
      end
    end
    {:reply, reply, state}
  end

  def handle_call({:get, id}, _from, state) do
    reply = case read(state, id) do
      {:ok, doc} ->
        if current?(doc), do: {:ok, doc}, else: {:ok, %{doc | "status" => "stale_read_only"}}
      error -> error
    end
    {:reply, reply, state}
  end

  def handle_call(:list, _from, state) do
    docs = for path <- Path.wildcard(Path.join(state.dir, "*.json")),
      id = Path.basename(path, ".json"),
      {:ok, doc} <- [read(state, id)], do: %{
        "id" => id, "status" => if(current?(doc), do: doc["status"], else: "stale_read_only"),
        "updated_at_utc" => doc["updated_at_utc"],
        "target_policy_nodes" => doc["target_policy_nodes"]}
    {:reply, {:ok, Enum.sort_by(docs, & &1["updated_at_utc"], :desc)}, state}
  end

  def handle_call({:human, id, kind, input}, _from, state) do
    reply = with {:ok, command} <- canonical_command(input),
                 {:ok, doc} <- read(state, id),
                 {:ok, outcome} <- human_transaction(state, doc, kind, command) do
      {:ok, outcome}
    end
    {:reply, reply, state}
  end

  def handle_call({:complete_job, id, completion}, _from, state) do
    reply = with {:ok, doc} <- read(state, id),
                 {:ok, command} <- canonical_command(completion) do
      case complete(doc, command) do
        {:ok, ^doc} -> {:ok, doc}
        {:ok, updated} ->
          with :ok <- persist(state, updated), do: {:ok, updated}
        error -> error
      end
    end
    {:reply, reply, state}
  end

  defp human_transaction(state, doc, kind, command) do
    digest = Canonical.digest(%{"kind" => kind, "command" => command})
    id = command["request_id"]
    existing = Enum.find(doc["human_commands"], &(&1["request_id"] == id))
    cond do
      not valid_request_id?(id) -> {:error, :invalid_request_id}
      existing != nil and existing["command_digest"] != digest -> {:error, :request_id_conflict}
      existing != nil -> {:ok, %{review: doc, probe_id: existing["probe_id"], answer_id: existing["answer_id"]}}
      command["expected_human_revision"] != doc["human_revision"] -> {:error, :human_revision_conflict}
      not current?(doc) or doc["status"] == "stale_read_only" -> {:error, :stale_source}
      doc["status"] != "in_progress" -> {:error, :review_closed}
      length(doc["human_commands"]) >= 500 -> {:error, :review_limit}
      true ->
        case apply_command(doc, kind, command) do
          {:ok, updated, probe_id, answer_id} ->
            history = %{"request_id" => id, "command_digest" => digest,
              "kind" => kind, "probe_id" => probe_id, "answer_id" => answer_id}
            updated = updated |> Map.update!("human_commands", &(&1 ++ [history])) |> bump(true)
            with :ok <- persist(state, updated) do
              {:ok, %{review: updated, probe_id: probe_id, answer_id: answer_id}}
            end
          error -> error
        end
    end
  end

  defp apply_command(doc, "answer_escape", command) do
    with :ok <- exact_keys(command, @allowed_answers),
         true <- command["command"] == "answer_escape" and command["review_id"] == doc["id"],
         {:ok, card} <- card_of_kind(doc, command["card_id"], "escape"),
         :ok <- valid_answer_fields(command, card),
         :ok <- packet_matches(doc, command),
         {:ok, pinned, probe} <- compute_probe(doc, command["witness"], "human"),
         {:ok, answer} <- answer_record(doc, command, card, probe["id"], [probe["id"]]) do
      updated = doc |> Map.put("pinned_probes", pinned) |> Map.update!("answers", &(&1 ++ [answer]))
      {:ok, updated, probe["id"], answer["answer_id"]}
    end
  end

  defp apply_command(doc, "pin_candidate", command) do
    with :ok <- exact_keys(command, @allowed_pin),
         :ok <- packet_matches(doc, command),
         {:ok, pinned, probe} <- compute_probe(doc, command["witness"], "human") do
      {:ok, %{doc | "pinned_probes" => pinned}, probe["id"], nil}
    end
  end

  defp apply_command(doc, "answer_card", command) do
    with :ok <- exact_keys(command, @allowed_card_answers),
         {:ok, card} <- card_of_kind(doc, command["card_id"], :not_escape),
         :ok <- valid_answer_fields(command, card),
         :ok <- valid_evidence(doc, command["evidence_ids"]),
         {:ok, answer} <- answer_record(doc, command, card, nil, command["evidence_ids"]) do
      {:ok, Map.update!(doc, "answers", &(&1 ++ [answer])), nil, answer["answer_id"]}
    end
  end

  defp apply_command(doc, "finish_review", command) do
    with :ok <- exact_keys(command, @allowed_finish),
         true <- command["confirmed"] == true,
         true <- command["outcome"] in ~w(meets_intent_in_reviewed_scope needs_design_change needs_policy_or_evidence),
         true <- is_binary(command["scope"]) and byte_size(command["scope"]) in 1..600,
         true <- is_binary(command["rationale"]) and byte_size(command["rationale"]) in 1..600,
         :ok <- valid_evidence(doc, command["evidence_ids"]),
         :ok <- conclusion_ready?(doc, command) do
      unresolved = unresolved_cards(doc)
      conclusion = %{"outcome" => command["outcome"], "scope" => command["scope"],
        "rationale" => command["rationale"], "evidence_ids" => command["evidence_ids"],
        "unresolved_ids" => Enum.map(unresolved, & &1["id"]) |> Enum.take(10),
        "confirmed_at_utc" => now()}
      {:ok, %{doc | "review_conclusion" => conclusion, "status" => "review_concluded"}, nil, nil}
    else
      false -> {:error, :invalid_conclusion}
      err -> err
    end
  end

  defp apply_command(doc, "start_job", command) do
    with :ok <- exact_keys(command, @allowed_start_job),
         true <- command["request_kind"] in ~w(deck challenge followup),
         true <- bounded_token?(command["job_id"]) and bounded_token?(command["prompt_hash"]) and bounded_token?(command["input_digest"]),
         true <- command["source_digest"] == doc["source"]["compiled_source_digest"],
         true <- length(doc["ai_jobs"]) < 100,
         true <- not Enum.any?(doc["ai_jobs"], &(&1["status"] == "pending")),
         true <- not Enum.any?(doc["ai_jobs"], &(&1["job_id"] == command["job_id"])) do
      job = %{"job_id" => command["job_id"], "request_kind" => command["request_kind"],
        "status" => "pending", "prompt_hash" => command["prompt_hash"],
        "input_digest" => command["input_digest"], "source_digest" => command["source_digest"],
        "based_on_human_revision" => doc["human_revision"] + 1, "validated_output" => nil,
        "error_class" => nil, "at_utc" => now()}
      {:ok, Map.update!(doc, "ai_jobs", &(&1 ++ [job])), nil, nil}
    else
      false -> {:error, :invalid_job}
      err -> err
    end
  end

  defp apply_command(doc, "accept_ai_card", command) do
    with :ok <- exact_keys(command, ~w(request_id expected_human_revision card_id)),
         card when is_map(card) <- Enum.find(doc["suggested_ai_cards"], &(&1["id"] == command["card_id"])),
         true <- not Enum.any?(doc["accepted_ai_cards"], &(&1["id"] == card["id"])) do
      {:ok, doc |> Map.update!("suggested_ai_cards", &Enum.reject(&1, fn c -> c["id"] == card["id"] end))
        |> Map.update!("accepted_ai_cards", &(&1 ++ [card])), nil, nil}
    else
      _ -> {:error, :invalid_card}
    end
  end

  defp apply_command(doc, "add_human_card", command) do
    with :ok <- exact_keys(command, ~w(request_id expected_human_revision kind target_node_id question source_ids)),
         true <- command["kind"] in Map.keys(%{"reading" => 1, "escape" => 1, "silence" => 1, "assumption" => 1, "trace" => 1}),
         true <- is_binary(command["question"]) and byte_size(command["question"]) in 5..600,
         true <- node?(doc, command["target_node_id"]),
         :ok <- valid_evidence(doc, command["source_ids"]),
         true <- length(doc["accepted_ai_cards"]) < 100 do
      card = %{"id" => fresh_id(), "kind" => command["kind"],
        "target_node_id" => command["target_node_id"], "question" => command["question"],
        "source_ids" => command["source_ids"], "mandatory" => false, "critical" => false,
        "critical_reason" => "", "origin" => "human", "ai_proposal_id" => nil}
      {:ok, Map.update!(doc, "accepted_ai_cards", &(&1 ++ [card])), nil, nil}
    else
      false -> {:error, :invalid_card}
      err -> err
    end
  end

  defp apply_command(_, _, _), do: {:error, :unknown_command}

  defp complete(doc, command) do
    with :ok <- exact_keys(command, ~w(job_id input_digest source_digest validated_output error_class)),
         job when is_map(job) <- Enum.find(doc["ai_jobs"], &(&1["job_id"] == command["job_id"])),
         true <- command["input_digest"] == job["input_digest"],
         true <- command["source_digest"] == job["source_digest"],
         true <- job["status"] in ~w(pending complete failed interrupted discarded_late),
         true <- is_nil(command["validated_output"]) or (is_map(command["validated_output"]) and byte_size(Jason.encode!(command["validated_output"])) <= 32_768),
         true <- is_nil(command["error_class"]) or (is_binary(command["error_class"]) and byte_size(command["error_class"]) <= 150) do
      if job["status"] != "pending" do
        if job["validated_output"] == command["validated_output"] and job["error_class"] == command["error_class"] do
          {:ok, doc}
        else
          {:error, :job_already_completed}
        end
      else
        fresh = doc["status"] == "in_progress" and current?(doc) and job["source_digest"] == doc["source"]["compiled_source_digest"] and
        (job["request_kind"] == "deck" or job["based_on_human_revision"] == doc["human_revision"])
        status = cond do
        not fresh -> "discarded_late"
        not is_nil(command["error_class"]) -> "failed"
        true -> "complete"
      end
        # The B store accepts only already validated proposals; C supplies the
      # schema/semantic validator before calling this internal server boundary.
        new_job = %{job | "status" => status,
        "validated_output" => if(status == "complete", do: command["validated_output"], else: nil),
        "error_class" => if(status == "discarded_late", do: "stale_job_context", else: command["error_class"])}
        doc = Map.update!(doc, "ai_jobs", &Enum.map(&1, fn j -> if j["job_id"] == job["job_id"], do: new_job, else: j end))
        with {:ok, suggestions} <- validate_suggestions(doc, new_job) do
          {:ok, doc |> Map.update!("suggested_ai_cards", &(&1 ++ suggestions)) |> bump(false)}
        end
      end
    else
      %{"status" => status} when status != "pending" -> {:error, :job_already_completed}
      _ -> {:error, :invalid_job_completion}
    end
  end

  defp validate_suggestions(doc, %{"status" => "complete", "validated_output" => %{"suggested_cards" => cards}})
       when is_list(cards) and length(cards) <= 6 do
    existing = doc["core_cards"] ++ doc["accepted_ai_cards"] ++ doc["suggested_ai_cards"]
    if Enum.all?(cards, fn card ->
      is_map(card) and Enum.sort(Map.keys(card)) == Enum.sort(~w(id kind target_node_id question source_ids mandatory critical critical_reason origin ai_proposal_id)) and
        bounded_token?(card["id"]) and card["origin"] == "ai_proposed" and
        card["mandatory"] == false and card["critical"] == false and card["critical_reason"] == "" and
        card["kind"] in ~w(reading escape silence assumption trace) and
        is_binary(card["question"]) and byte_size(card["question"]) <= 600 and
        node?(doc, card["target_node_id"]) and valid_evidence(doc, card["source_ids"]) == :ok and
        not Enum.any?(existing, &(&1["id"] == card["id"]))
    end) and length(Enum.uniq_by(cards, & &1["id"])) == length(cards) and length(doc["suggested_ai_cards"]) + length(cards) <= 100 do
      {:ok, cards}
    else
      {:error, :invalid_suggestions}
    end
  end
  defp validate_suggestions(_, _), do: {:ok, []}

  defp compute_probe(doc, witness, origin) do
    with {:ok, decoded} <- Adversarial.decode(witness),
         {:ok, canonical} <- Adversarial.encode(decoded),
         true <- canonical == witness,
         {:ok, evaluation, _} <- Adversarial.evaluate(canonical) do
      source = doc["source"]
      payload = %{"packet_digest" => source["packet_digest"],
        "compiled_source_digest" => source["compiled_source_digest"],
        "evaluator_id" => source["evaluator_id"],
        "before" => canonical["before"], "event" => canonical["event"],
        "output" => canonical["output"], "follow_on" => canonical["follow_on"]}
      fingerprint = "sha256:" <> Canonical.digest(payload)
      probe_id = fingerprint
      existing = Enum.find(doc["pinned_probes"], &(&1["fingerprint"] == fingerprint))
      probe = existing || %{"id" => probe_id, "fingerprint" => fingerprint, "origin" => origin,
        "witness" => canonical, "evaluation" => evaluation,
        "source_digest" => source["packet_digest"]}
      cond do
        existing != nil -> {:ok, doc["pinned_probes"], probe}
        length(doc["pinned_probes"]) >= 100 -> {:error, :probe_limit}
        true -> {:ok, doc["pinned_probes"] ++ [probe], probe}
      end
    else
      {:error, :stale_source} -> {:error, :stale_source}
      _ -> {:error, :invalid_draft}
    end
  end

  defp answer_record(doc, command, card, probe_id, evidence) do
    prior = doc["answers"] |> Enum.reverse() |> Enum.find(&(&1["card_id"] == card["id"]))
    if length(doc["answers"]) < 500 do
      {:ok, %{"answer_id" => fresh_id(), "request_id" => command["request_id"],
        "card_id" => card["id"], "actor" => "human", "probe_id" => probe_id,
        "choice" => command["choice"], "reason" => command["reason"],
        "evidence_ids" => Enum.uniq(evidence),
        "revealed_before_answer" => command["revealed_before_answer"],
        "supersedes_answer_id" => if(prior, do: prior["answer_id"], else: nil),
        "at_utc" => now()}}
    else
      {:error, :answer_limit}
    end
  end

  defp valid_answer_fields(cmd, card) do
    cond do
      cmd["choice"] not in Dossier.choices(card["kind"]) -> {:error, :invalid_choice}
      not is_binary(cmd["reason"]) or byte_size(cmd["reason"]) > 600 -> {:error, :invalid_reason}
      not is_boolean(cmd["revealed_before_answer"]) -> {:error, :invalid_answer}
      cmd["choice"] == "deferred" and cmd["reason"] == "" -> {:error, :defer_reason_required}
      true -> :ok
    end
  end

  defp card_of_kind(doc, id, kind) do
    card = Enum.find(doc["core_cards"] ++ doc["accepted_ai_cards"], &(&1["id"] == id))
    cond do
      not is_map(card) -> {:error, :invalid_card}
      kind == :not_escape and card["kind"] == "escape" -> {:error, :invalid_card}
      kind != :not_escape and card["kind"] != kind -> {:error, :invalid_card}
      true -> {:ok, card}
    end
  end

  defp valid_evidence(doc, ids) when is_list(ids) and length(ids) <= 10 do
    known = Enum.map(doc["graph_snapshot"]["nodes"], & &1["id"]) ++
      Enum.map(doc["graph_snapshot"]["excerpts"], & &1["id"]) ++
      Enum.map(doc["pinned_probes"], & &1["id"])
    if Enum.all?(ids, &(is_binary(&1) and &1 in known)) and length(Enum.uniq(ids)) == length(ids),
      do: :ok, else: {:error, :unknown_evidence}
  end
  defp valid_evidence(_, _), do: {:error, :unknown_evidence}
  defp node?(doc, id), do: Enum.any?(doc["graph_snapshot"]["nodes"], &(&1["id"] == id))

  defp packet_matches(doc, %{"packet_digest" => digest}) do
    if digest == doc["source"]["packet_digest"], do: :ok, else: {:error, :stale_source}
  end
  defp packet_matches(_, _), do: {:error, :stale_source}

  defp conclusion_ready?(doc, command) do
    cards = doc["core_cards"] ++ doc["accepted_ai_cards"]
    latest = Enum.reduce(doc["answers"], %{}, &Map.put(&2, &1["card_id"], &1))
    missing = Enum.any?(cards, fn c ->
      (c["mandatory"] or c["critical"]) and not Map.has_key?(latest, c["id"])
    end)
    unresolved = unresolved_cards(doc)
    positive = command["outcome"] == "meets_intent_in_reviewed_scope"
    bad = Enum.any?(latest, fn {_id, a} -> a["choice"] in ~w(disputed gap_suspected) end) or
      Enum.any?(doc["pinned_probes"], fn p ->
        Enum.any?(p["evaluation"]["law_rows"], &(&1["reason"] == ":actual_contract_alarm")) or
        p["evaluation"]["actual"] != p["evaluation"]["oracle"]
      end)
    cond do
      missing -> {:error, :unanswered_mandatory_or_critical}
      positive and (bad or unresolved != [] or command["evidence_ids"] == []) -> {:error, :unresolved_critical_conflict}
      true -> :ok
    end
  end

  defp unresolved_cards(doc) do
    latest = Enum.reduce(doc["answers"], %{}, &Map.put(&2, &1["card_id"], &1))
    Enum.filter(doc["core_cards"] ++ doc["accepted_ai_cards"], fn c ->
      latest[c["id"]] == nil or latest[c["id"]]["choice"] in ~w(deferred disputed unknown gap_suspected unsure)
    end)
  end

  defp canonical_command(command) when is_map(command) do
    if Enum.all?(Map.keys(command), &(is_binary(&1) or is_atom(&1))) do
      normalized = Map.new(command, fn {k, v} -> {if(is_atom(k), do: Atom.to_string(k), else: k), v} end)
      try do
        _ = Canonical.json(normalized)
        {:ok, normalized}
      rescue
        _ -> {:error, :invalid_command}
      end
    else
      {:error, :invalid_command}
    end
  end
  defp canonical_command(_), do: {:error, :invalid_command}

  defp exact_keys(command, required) do
    if Enum.sort(Map.keys(command)) == Enum.sort(required), do: :ok, else: {:error, :invalid_command}
  end
  defp valid_request_id?(value), do: is_binary(value) and Regex.match?(@id_pattern, value)
  defp bounded_token?(value), do: is_binary(value) and byte_size(value) in 1..128
  defp fresh_id, do: :crypto.strong_rand_bytes(18) |> Base.url_encode64(padding: false)
  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()

  defp bump(doc, human?) do
    doc |> Map.update!("document_revision", &(&1 + 1))
    |> Map.update!("human_revision", &(&1 + (if(human?, do: 1, else: 0))))
    |> Map.put("updated_at_utc", now())
  end

  defp current?(doc) do
    with :ok <- Claims.freshness(),
         %{status: :ready} = generation <- Claims.snapshot(),
         true <- doc["source"]["compiled_source_digest"] == generation.source.sha256,
         true <- doc["source"]["evaluator_id"] == generation.evaluator_id,
         true <- proof_current?(doc, generation),
         true <- Enum.all?(doc["source"]["source_manifest"], fn {path, digest} ->
           match?({:ok, _}, Anchor.read_under(Config.root(), path)) and
             ProofEvidence.digest_file(Config.root(), path) == digest
         end) do
      true
    else
      _ -> false
    end
  end

  defp proof_current?(doc, generation) do
    saved = doc["source"]["proof_report_snapshot"]
    current = ProofEvidence.load(Config.root(), Application.get_env(:hold_ledger_review_web, :proof_report),
      Enum.map(generation.source.catalog, & &1["slug"]))
    is_map(saved) and saved["status"] == Atom.to_string(current.status) and
      saved["detail"] == String.slice(current.detail, 0, 300) and
      saved["report_sha256"] == Map.get(current, :report_sha256)
  end

  defp read(state, id) do
    with true <- valid_request_id?(id),
         path = Path.join(state.dir, id <> ".json"),
         {:ok, %{type: :regular, size: size}} <- File.lstat(path),
         true <- size <= @max_bytes,
         {:ok, bytes} <- File.read(path),
         {:ok, doc} <- Jason.decode(bytes),
         true <- valid_document?(doc, id) do
      {:ok, doc}
    else
      {:error, :enoent} -> {:error, :not_found}
      false -> {:error, :corrupt_review}
      _ -> {:error, :corrupt_review}
    end
  end

  defp valid_document?(doc, id) when is_map(doc) do
    Enum.sort(Map.keys(doc)) == Enum.sort(~w(id seed_id document_revision human_revision target_policy_nodes status source graph_snapshot core_cards accepted_ai_cards suggested_ai_cards pinned_probes answers human_commands ai_jobs review_conclusion created_at_utc updated_at_utc)) and
      doc["id"] == id and doc["seed_id"] in Adversarial.seeds() and is_integer(doc["document_revision"]) and doc["document_revision"] >= 1 and
      is_integer(doc["human_revision"]) and doc["human_revision"] >= 0 and
      doc["status"] in ~w(in_progress review_concluded stale_read_only corrupt_read_only) and
      is_binary(doc["created_at_utc"]) and is_binary(doc["updated_at_utc"]) and
      is_list(doc["target_policy_nodes"]) and Enum.all?(doc["target_policy_nodes"], &is_binary/1) and
      is_list(doc["human_commands"]) and Enum.all?(doc["human_commands"], &is_map/1) and
      is_list(doc["pinned_probes"]) and Enum.all?(doc["pinned_probes"], &is_map/1) and
      is_list(doc["answers"]) and Enum.all?(doc["answers"], &is_map/1) and
      is_list(doc["ai_jobs"]) and Enum.all?(doc["ai_jobs"], &(is_map(&1) and &1["status"] in ~w(pending complete failed interrupted discarded_late))) and
      is_list(doc["core_cards"]) and Enum.all?(doc["core_cards"], &is_map/1) and
      is_list(doc["accepted_ai_cards"]) and Enum.all?(doc["accepted_ai_cards"], &is_map/1) and
      is_list(doc["suggested_ai_cards"]) and Enum.all?(doc["suggested_ai_cards"], &is_map/1) and
      is_map(doc["graph_snapshot"]) and is_list(doc["graph_snapshot"]["nodes"]) and
      is_list(doc["graph_snapshot"]["edges"]) and is_list(doc["graph_snapshot"]["excerpts"]) and
      Enum.all?(doc["graph_snapshot"]["nodes"], &is_map/1) and
      Enum.all?(doc["graph_snapshot"]["edges"], &is_map/1) and
      Enum.all?(doc["graph_snapshot"]["excerpts"], &is_map/1) and
      is_map(doc["source"]) and is_map(doc["source"]["proof_report_snapshot"]) and
      is_map(doc["source"]["source_manifest"]) and map_size(doc["source"]["source_manifest"]) > 0 and
      is_binary(doc["source"]["compiled_source_digest"]) and
      is_binary(doc["source"]["packet_digest"]) and
      is_binary(doc["source"]["evaluator_id"])
  end
  defp valid_document?(_, _), do: false

  defp persist(state, doc) do
    try do
      bytes = Canonical.json(doc) <> "\n"
      if byte_size(bytes) > @max_bytes do
        {:error, :write_failed}
      else
        path = Path.join(state.dir, doc["id"] <> ".json")
        case File.lstat(path) do
          {:ok, %{type: :regular}} -> state.writer.(path, bytes)
          {:error, :enoent} -> state.writer.(path, bytes)
          _ -> {:error, :write_failed}
        end
        |> case do
          :ok -> :ok
          _ -> {:error, :write_failed}
        end
      end
    rescue
      _ -> {:error, :write_failed}
    end
  end

  def atomic_write(path, bytes) do
    tmp = path <> "." <> Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false) <> ".tmp"
    result = with {:ok, io} <- :file.open(String.to_charlist(tmp), [:write, :binary, :exclusive]),
      do: sync_and_close(io, bytes)
    case result do
      :ok ->
        case File.rename(tmp, path) do
          :ok -> :ok
          error -> File.rm(tmp); error
        end
      error -> File.rm(tmp); error
    end
  end

  defp sync_and_close(io, bytes) do
    try do
      with :ok <- :file.write(io, bytes), :ok <- :file.sync(io) do
        :ok
      end
    after
      :file.close(io)
    end
  end
end
