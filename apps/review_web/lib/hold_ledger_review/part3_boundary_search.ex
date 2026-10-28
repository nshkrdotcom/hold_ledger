defmodule HoldLedgerReview.Part3BoundarySearch do
  @moduledoc """
  Small, deterministic change-directed boundary search. It proposes only
  supported *inputs*; actual A/B predicate results come exclusively from the
  isolated, source-derived runner after an explicit operator action.
  It does not assign a weakening label or claim exhaustion.
  """
  alias HoldLedgerReview.Adversarial

  @max_cases 3

  def cases(package, witness) do
    if Enum.any?(package["source_changes"], &relevant?/1) do
      with %{"event" => %{"type" => "request"} = event, "before" => before} <- witness,
           amount when is_integer(amount) <- before["amount_limit"] - before["used_amount"],
           true <- amount > 0 do
        [amount - 1, amount, amount + 1]
        |> Enum.filter(&(&1 > 0 and &1 <= 1_000_000))
        |> Enum.uniq()
        |> Enum.take(@max_cases)
        |> Enum.flat_map(fn value ->
          candidate = put_in(witness, ["event", "amount"], value)
          case Adversarial.decode(candidate) do
            {:ok, decoded} ->
              case Adversarial.encode(decoded) do
                {:ok, ^candidate} ->
                  [%{"label" => if(value == amount, do: "exact-fit remaining amount", else: "adjacent amount boundary"),
                    "requested_amount" => value, "witness" => candidate,
                    "method" => "deterministic_amount_limit_boundary; max 3 cases, not state-space coverage"}]
                _ -> []
              end
            _ -> []
          end
        end)
      else
        _ -> []
      end
    else
      []
    end
  end

  defp relevant?(%{"kind" => kind}), do: kind in ~w(claim called_definition_or_behavior)
end
