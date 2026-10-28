defmodule HoldLedgerReview.Part3Package do
  @moduledoc """
  Strict version-1 application package. The immutable context binds source bytes,
  governing policy and the parser/evaluator/codec; evidence and human commands
  append in separate revisions. An AST is only a derived source reference.
  """
  alias HoldLedgerReview.{Anchor, Canonical, Config, Part3ContractDelta, Part3Snapshots, TermCodec}

  @fields ~w(schema_version id context_digest baseline proposal policy_anchors source_changes evidence verification_attempts replay_attempts human_findings human_commands ai_history pinned_examples accepted_questions conclusion document_revision human_revision created_at_utc updated_at_utc)
  @hex ~r/\A[0-9a-f]{64}\z/
  @evidence_kinds ~w(lost_domain_input permitted_alternative_output observed_behavioral_difference pointwise_observation formal_artifact)
  @levels ~w(structural_edit concrete_computation independently_checked_artifact)
  @activity_kinds ~w(source_extraction pointwise_execution elaboration export checker acceptance)
  @statuses ~w(not_run queued running succeeded failed interrupted)
  @lenses ~w(reading alternative_behavior evidence_scope excluded_inputs outside_assumptions)

  def new(id, baseline_id, proposal_id) do
    with {:ok, a} <- Part3Snapshots.load(baseline_id),
         {:ok, b} <- Part3Snapshots.load(proposal_id),
         {:ok, changes} <- Part3ContractDelta.compare(a, b),
         true <- a["snapshot_id"] != b["snapshot_id"],
         {:ok, policy} <- policy(a) do
      now = now()
      context = %{"baseline" => a, "proposal" => b, "policy_anchors" => policy,
                  "source_changes" => changes}
      base = %{
        "schema_version" => 1, "id" => id, "context_digest" => Canonical.digest(context),
        "baseline" => a, "proposal" => b, "policy_anchors" => policy,
        "source_changes" => changes, "evidence" => [], "verification_attempts" => [],
        "replay_attempts" => [], "human_findings" => [], "human_commands" => [],
        "ai_history" => [], "pinned_examples" => [], "accepted_questions" => [], "conclusion" => nil, "document_revision" => 1,
        "human_revision" => 0, "created_at_utc" => now, "updated_at_utc" => now
      }
      if valid?(base, id), do: {:ok, base}, else: {:error, :invalid_package}
    else
      false -> {:error, :identical_snapshot}
      {:error, _} = err -> err
    end
  end

  defp policy(a) do
    path = "guides/specification.md"
    with sha when is_binary(sha) <- a["manifest"][path],
         {:ok, policy} <- Anchor.read_under(Config.root(), path),
         true <- Anchor.sha(policy) == sha do
      {:ok, [%{"id" => "policy.specification.v1", "authority" => "governing_repository_policy",
                "path" => path, "sha256" => sha,
                "passage" => "State and validity; Events; Uncertain outcomes and identities; Replay",
                "authorized_change_id" => nil}]}
    else
      _ -> {:error, :policy_authority_changed_or_unavailable}
    end
  end

  def valid?(p, id) when is_map(p) do
    Enum.sort(Map.keys(p)) == Enum.sort(@fields) and
      p["schema_version"] == 1 and p["id"] == id and id?(id) and
      is_integer(p["document_revision"]) and p["document_revision"] >= 1 and
      is_integer(p["human_revision"]) and p["human_revision"] >= 0 and
      p["document_revision"] > p["human_revision"] and
      text?(p["created_at_utc"], 40) and text?(p["updated_at_utc"], 40) and
      snapshot?(p["baseline"]) and snapshot?(p["proposal"]) and
      p["baseline"]["snapshot_id"] != p["proposal"]["snapshot_id"] and
      Part3Snapshots.compatible?(p["baseline"], p["proposal"]) and
      anchors?(p["policy_anchors"]) and changes?(p["source_changes"]) and
      p["context_digest"] == Canonical.digest(Map.take(p, ~w(baseline proposal policy_anchors source_changes))) and
      many?(p["evidence"], 500, &evidence?/1) and
      many?(p["verification_attempts"], 150, &attempt?/1) and
      many?(p["replay_attempts"], 150, &attempt?/1) and
      many?(p["human_findings"], 500, &finding?/1) and
      many?(p["human_commands"], 500, &command?/1) and
      many?(p["ai_history"], 100, &ai_record?/1) and
      many?(p["pinned_examples"], 150, &pinned?/1) and
      many?(p["accepted_questions"], 100, &accepted_question?/1) and
      conclusion?(p["conclusion"]) and
      references?(p)
  rescue
    _ -> false
  end

  def valid?(_, _), do: false
  def id?(s), do: is_binary(s) and Regex.match?(~r/\A[A-Za-z0-9_-]{16,80}\z/, s)
  def sha?(s), do: is_binary(s) and Regex.match?(@hex, s)
  def now, do: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()

  defp snapshot?(s) do
    is_map(s) and Enum.sort(Map.keys(s)) == Enum.sort(~w(schema_version snapshot_id commit dirty manifest dependency_id toolchain_id evaluator_id codec_id)) and
      s["schema_version"] == 1 and sha?(s["snapshot_id"]) and
      is_boolean(s["dirty"]) and (is_nil(s["commit"]) or text?(s["commit"], 40)) and
      is_map(s["manifest"]) and map_size(s["manifest"]) in 1..1500 and
      Enum.all?(s["manifest"], fn {p, digest} -> text?(p, 240) and sha?(digest) end) and
      Enum.all?(~w(dependency_id toolchain_id evaluator_id codec_id), &sha?(s[&1]))
  end

  defp anchors?([%{"id" => "policy.specification.v1", "authority" => "governing_repository_policy", "path" => "guides/specification.md", "sha256" => sha, "passage" => passage, "authorized_change_id" => nil} = a]) do
    map_size(a) == 6 and sha?(sha) and text?(passage, 500)
  end

  defp anchors?(_), do: false

  defp changes?(list) do
    many?(list, 300, fn c ->
      keys?(c, ~w(id path kind evidence_level baseline_sha256 proposal_sha256 baseline_excerpt proposal_excerpt claim semantic_relation)) and
        text?(c["id"], 100) and text?(c["path"], 240) and text?(c["kind"], 100) and
        c["evidence_level"] == "structural_edit" and c["semantic_relation"] == "unresolved" and
        Enum.all?(~w(baseline_sha256 proposal_sha256), &(is_nil(c[&1]) or sha?(c[&1]))) and
        Enum.all?(~w(baseline_excerpt proposal_excerpt), &text?(c[&1], 2000)) and is_map(c["claim"])
    end)
  end

  defp evidence?(e) do
    keys?(e, ~w(id kind level baseline_id proposal_id context_digest method bounds input output baseline_result proposal_result source_ids note)) and
      id?(e["id"]) and e["kind"] in @evidence_kinds and e["level"] in @levels and
      sha?(e["baseline_id"]) and sha?(e["proposal_id"]) and sha?(e["context_digest"]) and
      text?(e["method"], 200) and is_map(e["bounds"]) and
      (is_nil(e["input"]) or witness?(e["input"])) and
      (is_nil(e["output"]) or output?(e["output"])) and
      Enum.all?(["baseline_result", "proposal_result"], &(is_nil(e[&1]) or is_map(e[&1]))) and
      many?(e["source_ids"], 30, &text?(&1, 100)) and text_or_empty?(e["note"], 600)
  end

  defp witness?(w) do
    keys?(w, ~w(before event output follow_on)) and
      match?({:ok, _}, TermCodec.decode_state(w["before"])) and
      match?({:ok, _}, TermCodec.decode_event(w["event"])) and
      output?(w["output"]) and
      (is_nil(w["follow_on"]) or match?({:ok, _}, TermCodec.decode_event(w["follow_on"])))
  end

  defp output?(o), do: match?({:ok, _}, TermCodec.decode_output(o))

  defp attempt?(a) do
    keys?(a, ~w(id kind snapshot_id context_digest scope status producer queued_at started_at finished_at input_digest completion_digest artifacts diagnostics dependencies witness result)) and
      id?(a["id"]) and a["kind"] in @activity_kinds ++ ["replay"] and
      sha?(a["snapshot_id"]) and sha?(a["context_digest"]) and text?(a["scope"], 180) and
      a["status"] in @statuses and text?(a["producer"], 200) and
      text?(a["queued_at"], 40) and optional_text?(a["started_at"], 40) and
      optional_text?(a["finished_at"], 40) and sha?(a["input_digest"]) and
      (is_nil(a["completion_digest"]) or sha?(a["completion_digest"])) and
      many?(a["artifacts"], 40, fn artifact -> keys?(artifact, ~w(path sha256 bytes)) and text?(artifact["path"], 240) and sha?(artifact["sha256"]) and is_integer(artifact["bytes"]) and artifact["bytes"] >= 0 end) and
      text_or_empty?(a["diagnostics"], 1200) and many?(a["dependencies"], 12, &text?(&1, 100)) and
      (is_nil(a["witness"]) or witness?(a["witness"])) and
      (is_nil(a["result"]) or is_map(a["result"]))
  end

  defp finding?(f) do
    keys?(f, ~w(id lens status rationale scope evidence_ids change_ids human_revision created_at presentation revealed_before_answer)) and
      id?(f["id"]) and f["lens"] in @lenses and
      f["status"] in ~w(addressed not_applicable unresolved) and
      text?(f["rationale"], 1200) and text?(f["scope"], 600) and
      is_integer(f["human_revision"]) and f["human_revision"] >= 1 and
      many?(f["evidence_ids"], 30, &id?/1) and
      many?(f["change_ids"], 100, &text?(&1, 100)) and text?(f["created_at"], 40) and
      f["presentation"] in ~w(expert learning) and is_boolean(f["revealed_before_answer"]) and
      (f["status"] != "not_applicable" or byte_size(f["rationale"]) >= 5)
  end

  defp command?(c), do: keys?(c, ~w(request_id digest human_revision kind)) and id?(c["request_id"]) and sha?(c["digest"]) and is_integer(c["human_revision"]) and c["kind"] in ~w(finding conclude accept_question)
  defp ai_record?(a) do
    keys?(a, ~w(id status context_digest human_revision_at_request prompt_sha256 input_digest result error created_at finished_at)) and
      id?(a["id"]) and a["status"] in ~w(running succeeded failed interrupted stale) and
      Enum.all?(~w(context_digest prompt_sha256 input_digest), &sha?(a[&1])) and
      is_integer(a["human_revision_at_request"]) and a["human_revision_at_request"] >= 0 and
      text?(a["created_at"], 40) and optional_text?(a["finished_at"], 40) and
      text_or_empty?(a["error"], 180) and
      (is_nil(a["result"]) or (is_map(a["result"]) and byte_size(Jason.encode!(a["result"])) <= 18_000))
  end
  defp pinned?(v), do: keys?(v, ~w(id witness input_digest pinned_at context_digest)) and id?(v["id"]) and witness?(v["witness"]) and sha?(v["input_digest"]) and v["input_digest"] == Canonical.digest(v["witness"]) and sha?(v["context_digest"]) and text?(v["pinned_at"], 40)
  defp accepted_question?(q), do: keys?(q, ~w(id source_job_id source_proposal_id question kind human_revision accepted_at)) and id?(q["id"]) and id?(q["source_job_id"]) and text?(q["source_proposal_id"], 64) and text?(q["question"], 500) and q["kind"] in ~w(lost_domain_input permitted_alternative_output observed_behavioral_difference review_question) and is_integer(q["human_revision"]) and text?(q["accepted_at"], 40)
  defp conclusion?(nil), do: true
  defp conclusion?(c), do: keys?(c, ~w(outcome scope rationale evidence_ids confirmed_at human_revision)) and c["outcome"] in ~w(meets_intent_in_reviewed_scope needs_design_change needs_policy_or_evidence) and text?(c["scope"], 600) and text?(c["rationale"], 1200) and many?(c["evidence_ids"], 30, &id?/1) and text?(c["confirmed_at"], 40) and is_integer(c["human_revision"])

  defp references?(p) do
    ids = MapSet.new(p["evidence"], & &1["id"])
    changes = MapSet.new(p["source_changes"], & &1["id"])
    Enum.all?(p["evidence"], fn e -> e["baseline_id"] == p["baseline"]["snapshot_id"] and e["proposal_id"] == p["proposal"]["snapshot_id"] and e["context_digest"] == p["context_digest"] end) and
      Enum.all?(p["human_findings"], fn f -> Enum.all?(f["evidence_ids"], &MapSet.member?(ids, &1)) and Enum.all?(f["change_ids"], &MapSet.member?(changes, &1)) end) and
      (is_nil(p["conclusion"]) or Enum.all?(p["conclusion"]["evidence_ids"], &MapSet.member?(ids, &1))) and
      Enum.all?(p["verification_attempts"] ++ p["replay_attempts"], fn a -> a["context_digest"] == p["context_digest"] and a["snapshot_id"] in [p["baseline"]["snapshot_id"], p["proposal"]["snapshot_id"] end) and
      Enum.all?(p["pinned_examples"], &(&1["context_digest"] == p["context_digest"])) and
      Enum.all?(p["ai_history"], &(&1["context_digest"] == p["context_digest"])) and
      unique?(p["pinned_examples"], "id") and unique?(p["accepted_questions"], "id") and
      unique?(p["ai_history"], "id") and unique?(p["evidence"], "id") and unique?(p["human_findings"], "id") and unique?(p["human_commands"], "request_id") and unique?(p["verification_attempts"] ++ p["replay_attempts"], "id")
  end

  defp unique?(list, field), do: Enum.uniq_by(list, & &1[field]) == list
  defp keys?(m, fields), do: is_map(m) and Enum.sort(Map.keys(m)) == Enum.sort(fields)
  defp many?(m, max, pred), do: is_list(m) and length(m) <= max and Enum.all?(m, pred)
  defp text?(s, max), do: is_binary(s) and byte_size(s) in 1..max
  defp text_or_empty?(s, max), do: is_binary(s) and byte_size(s) <= max
  defp optional_text?(nil, _), do: true
  defp optional_text?(s, max), do: text?(s, max)
end
