defmodule HoldLedgerReview.AIJobs do
  @moduledoc """
  Manual opt-in dispatch and detached supervised completion. The store writes
  pending *before* network work, owns every terminal state and never resends
  interrupted jobs automatically. A second human tab retains normal CAS.
  """
  alias HoldLedgerReview.{AI, ReviewStore}

  def request(id, kind, card_id, witness, expected_human_revision, consent, opts \\ []) do
    server = Keyword.get(opts, :store, ReviewStore)
    supervisor = Keyword.get(opts, :task_supervisor, HoldLedgerReview.AITaskSupervisor)

    with true <- consent == true,
         {:ok, review} <- ReviewStore.get(id, server),
         true <- review["human_revision"] == expected_human_revision,
         true <- review["status"] == "in_progress",
         {:ok, packet} <- AI.prepare(review, kind, card_id, witness),
         {:ok, _client} <- AI.available?(opts) do
      job_id = fresh_id()

      command = %{
        "request_id" => fresh_id(),
        "expected_human_revision" => expected_human_revision,
        "job_id" => job_id,
        "request_kind" => kind,
        "prompt_hash" => packet.prompt_hash,
        "input_digest" => packet.input_digest,
        "source_digest" => packet.source_digest
      }

      with {:ok, %{review: started}} <- ReviewStore.start_job(id, command, server) do
        dispatch(supervisor, server, id, command, packet, opts, started)
      end
    else
      false -> {:error, :consent_or_revision_required}
      error -> error
    end
  end

  defp dispatch(supervisor, server, id, command, packet, opts, started) do
    case Task.Supervisor.start_child(supervisor, fn ->
           result = AI.run(packet, true, opts)
           deliver_completion(id, completion(command, result), server)
         end) do
      {:ok, _pid} ->
        {:ok, started, command["job_id"]}

      {:error, _reason} ->
        ReviewStore.complete_job(id, completion(command, {:error, :task_start_failed}), server)
        {:error, :task_start_failed}
    end
  end

  defp deliver_completion(id, completion, server) do
    ReviewStore.complete_job(id, completion, server)
  catch
    :exit, {:noproc, _call} -> {:error, :store_unavailable}
  end

  defp completion(command, result) do
    fields = Map.take(command, ~w(job_id input_digest source_digest))

    case result do
      {:ok, output} ->
        Map.merge(fields, %{"validated_output" => output, "error_class" => nil})

      {:error, reason} ->
        Map.merge(fields, %{
          "validated_output" => nil,
          "error_class" => reason |> Atom.to_string() |> String.slice(0, 150)
        })
    end
  end

  defp fresh_id, do: Base.url_encode64(:crypto.strong_rand_bytes(18), padding: false)
end
