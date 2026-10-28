defmodule HoldLedgerReview.Part3AI do
  @moduledoc """
  Optional source-bounded proposer, never an evaluator, policy judge or checker.
  Only explicit consent may enter `request/4`; no application initialization,
  reconnect or render can dispatch it. Controlled complete/2 injection is only
  for tests, and never production evidence.
  """
  alias HoldLedgerReview.{AI, AIProtocol, Adversarial, Anchor, Canonical, Part3Package, Part3Snapshots}

  @source_budget 48_000
  @max_response 18_000
  @schema "priv/contracts/part3_review.schema.json"
  @prompt "priv/prompts/part3_review.md"
  @app :hold_ledger_review_web

  def prompt, do: Application.app_dir(@app, @prompt) |> File.read!()
  def schema, do: Application.app_dir(@app, @schema) |> File.read!() |> Jason.decode!()

  def prepare(package) do
    with true <- Part3Package.valid?(package, package["id"]),
         {:ok, a} <- Part3Snapshots.load(package["baseline"]["snapshot_id"]),
         {:ok, b} <- Part3Snapshots.load(package["proposal"]["snapshot_id"]),
         true <- a == package["baseline"] and b == package["proposal"],
         {:ok, policy} <- Part3Snapshots.source(a["snapshot_id"], "guides/specification.md"),
         true <- Anchor.sha(policy) == hd(package["policy_anchors"])["sha256"] do
      sources = Enum.reduce_while(package["source_changes"], {[], 0}, fn c, {rows, used} ->
        if used > @source_budget - 3_000 or length(rows) >= 12 do
          {:halt, {rows, used}}
        else
          row = Map.take(c, ~w(id path kind baseline_sha256 proposal_sha256 claim))
          row = Map.merge(row, %{"old_excerpt" => String.slice(c["baseline_excerpt"], 0, 900),
            "new_excerpt" => String.slice(c["proposal_excerpt"], 0, 900)})
          {:cont, {[row | rows], used + byte_size(Canonical.json(row))}}
        end
      end) |> elem(0) |> Enum.reverse()

      input = %{"schema_version" => 1, "context_digest" => package["context_digest"],
        "baseline_id" => a["snapshot_id"], "proposal_id" => b["snapshot_id"],
        "policy_anchor" => hd(package["policy_anchors"]),
        "policy_excerpt" => String.slice(policy, 0, 14_000), "source_changes" => sources,
        "unexamined_source_count" => length(package["source_changes"]) - length(sources),
        "proposer_explanations" => [], "available_evidence" => Enum.map(package["evidence"],
          &Map.take(&1, ~w(id kind method level bounds source_ids))),
        "human_answers_withheld" => true,
        "general_semantic_relations" => "unresolved"}
      system = prompt()
      user = Canonical.json(input)
      body = %{"system" => system, "user" => user}
      if byte_size(user) + byte_size(system) <= @source_budget and byte_size(Jason.encode!(schema())) < 28_000 do
        {:ok, %{system: system, user: user, input_digest: Canonical.digest(body),
          prompt_sha256: Anchor.sha(system), context_digest: package["context_digest"],
          baseline_id: a["snapshot_id"], proposal_id: b["snapshot_id"],
          source_digest: Canonical.digest(%{"a" => a["manifest"], "b" => b["manifest"]})}}
      else
        {:error, :packet_budget_exceeded}
      end
    else
      _ -> {:error, :stale_or_invalid_ai_context}
    end
  end

  def fresh?(package, packet) do
    with {:ok, current} <- prepare(package), true <- current == packet, do: :ok
  else
    _ -> {:error, :source_prompt_or_context_drift}
  end

  def run(packet, consent, opts \\ []) do
    if consent != true do
      {:error, :consent_required}
    else
      with {:ok, client} <- AI.available?(opts),
           {:ok, request} <- Inference.Request.from_messages(
             [%{role: :system, content: packet.system}, %{role: :user, content: packet.user}],
             response_format: {:json_schema, %{name: "hold_ledger_part3_review",
               schema: wire_schema(schema()), strict: true}}),
           {:ok, raw} <- complete(client, request, opts),
           {:ok, data} <- parse_response(raw),
           :ok <- validate(data, packet) do
        {:ok, data}
      else
        {:error, e} when is_atom(e) -> {:error, e}
        _ -> {:error, :invalid_model_completion}
      end
    end
  rescue
    _ -> {:error, :model_unavailable_or_invalid}
  catch
    _, _ -> {:error, :model_unavailable_or_invalid}
  end

  def validate(output, packet) when is_map(output) do
    with true <- byte_size(Jason.encode!(output)) <= @max_response,
         true <- AIProtocol.structure?(output, schema()),
         true <- output["request_kind"] == "part3_review" and output["context_digest"] == packet.context_digest,
         true <- Enum.uniq_by(output["proposals"], & &1["proposal_id"]) == output["proposals"],
         {:ok, data} <- Jason.decode(packet.user),
         true <- Enum.all?(output["proposals"], fn p ->
           p["source_change_ids"] != [] and
             Enum.uniq(p["source_change_ids"]) == p["source_change_ids"] and
             Enum.all?(p["source_change_ids"], fn id -> Enum.any?(data["source_changes"], &(&1["id"] == id)) end) and
             (is_nil(p["witness"]) or valid_witness?(p["witness"]))
         end) do
      :ok
    else
      _ -> {:error, :invalid_model_proposal}
    end
  rescue
    _ -> {:error, :invalid_model_proposal}
  end
  def validate(_, _), do: {:error, :invalid_model_proposal}

  defp valid_witness?(w) do
    with {:ok, decoded} <- Adversarial.decode(w),
         {:ok, encoded} <- Adversarial.encode(decoded),
         true <- encoded == w and HoldLedger.Spec.valid?(decoded.before), do: true
    else
      _ -> false
    end
  end

  defp complete(client, request, opts) do
    case Keyword.get(opts, :complete) do
      nil -> Inference.complete(client, request)
      adapter when is_function(adapter, 2) -> adapter.(client, request)
    end
  end

  defp parse_response(%{tool_calls: calls}) when is_list(calls) and calls != [], do: {:error, :unexpected_tool_call}
  defp parse_response(response) do
    if is_map(Map.get(response, :object)) do
      {:ok, response.object}
    else
      text = Inference.Response.text(response)
      if is_binary(text) and byte_size(text) <= @max_response, do: Jason.decode(text), else: {:error, :response_too_large}
    end
  end

  defp wire_schema(v) when is_list(v), do: Enum.map(v, &wire_schema/1)
  defp wire_schema(v) when is_map(v) do
    v |> Map.delete("uniqueItems") |> Map.new(fn
      {"oneOf", branches} -> {"anyOf", wire_schema(branches)}
      {key, val} -> {key, wire_schema(val)}
    end)
  end
  defp wire_schema(v), do: v
end
