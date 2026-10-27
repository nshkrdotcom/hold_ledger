defmodule HoldLedgerReview.Receipts do
  @moduledoc "Serialized, immutable local human judgments; never a proof certificate."
  use GenServer
  alias HoldLedgerReview.{Config, Session, TermCodec}
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  @impl true
  def init(_), do: {:ok, %{}}

  def directory,
    do:
      Application.get_env(
        :hold_ledger_review_web,
        :receipt_dir,
        Path.join(Config.root(), "tmp/review_studio/receipts")
      )

  def record(session, params), do: GenServer.call(__MODULE__, {:record, session, params})
  @impl true
  def handle_call({:record, s, params}, _from, state) do
    case Map.fetch(state, s.session_id) do
      {:ok, id} -> {:reply, {:ok, id}, state}
      :error -> record_new(s, params, state)
    end
  end

  defp record_new(s, params, state) do
    with {:ok, decision} <- Session.validate_decision(s, params),
         id = Base.url_encode64(:crypto.strong_rand_bytes(18), padding: false),
         receipt =
           Map.merge(decision, %{
             schema_version: 1,
             id: id,
             case_id: s.packet.case.id,
             packet_sha256: s.packet.packet_sha256,
             source_sha256: s.packet.source_sha256,
             git_head: s.packet.git_head,
             dirty?: s.packet.dirty?,
             policy_anchor_ids: [s.packet.case.id <> ".policy"],
             law_slugs: Enum.map(s.packet.case.laws, &elem(&1, 0)),
             actual_proof_status: s.packet.proof.status,
             proof_report: Map.drop(s.packet.proof, [:report]),
             prediction: s.prediction,
             prediction_note: s.note,
             examined_candidate_ids: s.examined,
             selected_claims: s.selected,
             actual: s.packet.facts.actual,
             oracle: s.packet.facts.oracle,
             active_candidate: s.candidate,
             follow_on: s.follow,
             explanation: s.explanation,
             explanation_feedback: s.feedback,
             created_at_utc: DateTime.utc_now() |> DateTime.to_iso8601()
           }),
         :ok <- write(id, receipt) do
      {:reply, {:ok, id}, Map.put(state, s.session_id, id)}
    else
      error -> {:reply, error, state}
    end
  end

  defp write(id, receipt) do
    dir = directory()
    tmp = Path.join(dir, "." <> id <> ".tmp")
    final = Path.join(dir, id <> ".json")

    with :ok <- File.mkdir_p(dir),
         {:ok, io} <- File.open(tmp, [:write, :binary, :exclusive]) do
      result =
        with :ok <- IO.binwrite(io, Jason.encode!(TermCodec.encode(receipt), pretty: true)),
             :ok <- :file.sync(io),
             :ok <- File.close(io),
             :ok <- File.ln(tmp, final),
             do: :ok

      File.close(io)
      File.rm(tmp)
      result
    end
  end

  def read(id) when is_binary(id) do
    if Regex.match?(~r/\A[A-Za-z0-9_-]{24}\z/, id) do
      with {:ok, b} <- File.read(Path.join(directory(), id <> ".json")),
           {:ok, r} <- Jason.decode(b),
           do: {:ok, r}
    else
      {:error, :invalid_id}
    end
  end

  def markdown(r) do
    fields = [
      "case_id",
      "review_mode",
      "reviewed_scope",
      "git_head",
      "packet_sha256",
      "actual_proof_status",
      "decision",
      "rationale",
      "selected_evidence_ids",
      "law_slugs",
      "stale_at_recording",
      "created_at_utc"
    ]

    "# Hold Ledger human review\n\nThis is a human judgment, not a proof certificate or deployment authorization.\n\n" <>
      Enum.map_join(fields, "\n\n", fn key ->
        "**" <> key <> "**\n\n" <> escape(Jason.encode!(r[key]))
      end) <>
      "\n\n## Complete receipt\n\n" <> escape(Jason.encode!(r, pretty: true)) <> "\n"
  end

  defp escape(s),
    do:
      String.replace(s, ["<", ">", "&"], fn
        "<" -> "&lt;"
        ">" -> "&gt;"
        "&" -> "&amp;"
      end)
end
