defmodule HoldLedgerReviewWeb.Experiment do
  @moduledoc false
  alias HoldLedgerReview.Trace

  def new(doc, cursor), do: %{doc: doc, cursor: cursor, pending: []}
  def cursor(exp), do: exp.cursor

  def run(exp, %{"kind" => kind} = action) when kind in ~w(append candidate) do
    token = Trace.token()

    case Trace.apply_command(exp.doc, exp.doc["revision"], token, action) do
      {:ok, updated} ->
        step = Enum.find(updated["steps"], &matches_action?(&1, action))

        {:ok,
         %{exp | doc: updated, cursor: step["id"], pending: exp.pending ++ [{token, action}]}}

      error ->
        error
    end
  end

  def run(_, _), do: {:error, :unsupported_experiment_action}

  defp matches_action?(step, %{"kind" => "append", "parent" => parent, "event" => event}),
    do: step["parent"] == parent && step["event"] == event && !Map.has_key?(step, "challenge_of")

  defp matches_action?(step, %{"kind" => "candidate", "parent" => parent, "output" => output}),
    do: step["challenge_of"] == parent && step["output"] == output

  def save(doc, exp, writer \\ &Trace.command/4), do: save_pending(doc, exp, exp.pending, writer)

  defp save_pending(doc, _exp, [], _writer), do: {:ok, doc}

  defp save_pending(doc, exp, [{token, action} | rest] = pending, writer) do
    case writer.(doc["id"], doc["revision"], token, action) do
      {:ok, updated} -> save_pending(updated, exp, rest, writer)
      {:error, reason} -> {:error, reason, doc, %{exp | pending: pending}}
    end
  end
end
