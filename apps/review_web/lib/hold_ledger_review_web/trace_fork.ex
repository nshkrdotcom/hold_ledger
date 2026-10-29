defmodule HoldLedgerReviewWeb.TraceFork do
  @moduledoc """
  Read-only projection of a trace's recorded code and hypothetical paths.

  No events are synthesized or evaluated here. The selected fork is the one
  containing the cursor, or the most recently created alternative. Each lane
  follows a single recorded continuation, preferring the selected cursor path.
  """

  alias HoldLedgerReview.Trace

  @spec project(map(), String.t()) :: map() | nil
  def project(%{"steps" => steps} = doc, cursor) when is_list(steps) do
    alternatives = Enum.filter(steps, &is_binary(&1["challenge_of"]))
    cursor_ids = path_ids(doc, cursor)

    alternative =
      Enum.find(alternatives, &MapSet.member?(cursor_ids, &1["id"])) ||
        List.last(alternatives)

    with %{"challenge_of" => original_id} <- alternative,
         %{} = original <- Trace.step(doc, original_id) do
      %{
        shared: Trace.path(doc, original["parent"]),
        code: branch(doc, original, cursor_ids),
        alternative: branch(doc, alternative, cursor_ids),
        original_id: original_id,
        alternative_id: alternative["id"]
      }
    else
      _ -> nil
    end
  end

  def project(_, _), do: nil

  defp path_ids(doc, cursor) do
    doc
    |> Trace.path(cursor)
    |> Enum.map(& &1["id"])
    |> MapSet.new()
  end

  defp branch(doc, first, cursor_ids), do: branch(doc, [first], first["id"], cursor_ids)

  defp branch(%{"steps" => steps} = doc, acc, parent, cursor_ids) when length(acc) < 64 do
    children =
      Enum.filter(steps, &(&1["parent"] == parent && !Map.has_key?(&1, "challenge_of")))

    next =
      Enum.find(children, &MapSet.member?(cursor_ids, &1["id"])) || List.last(children)

    if next,
      do: branch(doc, acc ++ [next], next["id"], cursor_ids),
      else: acc
  end

  defp branch(_, acc, _, _), do: acc
end
