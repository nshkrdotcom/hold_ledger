defmodule HoldLedgerReview.Part3AIJobs do
  @moduledoc """
  Explicit one-shot versioned proposal dispatch. In-progress jobs persist
  before the task starts; restart interrupts, never resends. Stale completion
  remains attached to original context and human revision, never an answer.
  """
  alias HoldLedgerReview.{AI, Part3AI, Part3Store}

  def request(id, revision, consent, opts \\ []) do
    if consent != true do
      {:error, :consent_required}
    else
      with {:ok, package, :ok} <- Part3Store.get(id),
           true <- revision == package["human_revision"] and is_nil(package["conclusion"]),
           {:ok, packet} <- Part3AI.prepare(package),
           {:ok, _client} <- AI.available?(opts),
           {:ok, saved, job} <- Part3Store.begin_ai(id, revision, packet) do
        supervisor = Keyword.get(opts, :task_supervisor, HoldLedgerReview.AITaskSupervisor)
        case Task.Supervisor.start_child(supervisor, fn ->
          result = case Part3Store.get(id) do
            {:ok, original, :ok} ->
              with :ok <- Part3AI.fresh?(original, packet), do: Part3AI.run(packet, true, opts)
            _ -> {:error, :source_context_drift}
          end
          Part3Store.finish_ai(id, job["id"], result)
        end) do
          {:ok, _pid} -> {:ok, saved, job["id"]}
          _ ->
            Part3Store.finish_ai(id, job["id"], {:error, :task_start_failed})
            {:error, :task_start_failed}
        end
      else
        false -> {:error, :revision_or_review_closed}
        error -> error
      end
    end
  end
end
