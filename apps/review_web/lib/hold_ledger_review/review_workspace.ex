defmodule HoldLedgerReview.ReviewWorkspace do
  @moduledoc "Review-only projections. Illustrative proposals never grant formal acceptance."
  alias HoldLedger.{Environment, Ledger, Spec}
  alias HoldLedgerReview.{Canonical, TermCodec}

  def example(step) do
    with {:ok, state} <- TermCodec.decode_state(step["before"]),
         %{"type" => "request", "key" => key, "amount" => amount} <- step["event"] do
      eligible = Spec.request_eligible?(state, key, amount)

      %{
        baseline: eligible,
        proposal: eligible and amount < elem(state, 0) - elem(state, 2),
        amount: amount,
        remaining: elem(state, 0) - elem(state, 2),
        key: key,
        actual: Ledger.step(state, {:request, key, amount}) |> elem(1) |> Atom.to_string(),
        provenance: "illustrated proposal"
      }
    else
      _ -> %{provenance: "not_applicable", baseline: nil, proposal: nil, actual: nil}
    end
  end

  def replay_rows(package, data, slug) do
    witness = %{
      "before" => data["before"],
      "event" => data["event"],
      "output" => data["candidate"],
      "follow_on" => nil
    }

    digest = Canonical.digest(witness)

    Enum.map(~w(baseline proposal), fn side ->
      attempt =
        package["replay_attempts"]
        |> Enum.reverse()
        |> Enum.find(
          &(&1["snapshot_id"] == package[side]["snapshot_id"] and &1["input_digest"] == digest)
        )

      result = if attempt && attempt["status"] == "succeeded", do: attempt["result"]
      rows = get_in(result || %{}, ["claims", slug, "bindings"]) || []

      %{
        side: side,
        status: if(attempt, do: attempt["status"], else: "not run for this input"),
        requires: summarize(rows, "requires"),
        candidate: summarize(rows, "post_candidate"),
        actual: get_in(result || %{}, ["evaluation", "actual", "result"])
      }
    end)
  end

  defp summarize([], _), do: nil

  defp summarize(rows, key) do
    values = Enum.map(rows, & &1[key])

    cond do
      key == "requires" and true in values -> true
      key == "requires" and Enum.all?(values, &(&1 == false)) -> false
      key == "requires" -> nil
      false in values -> false
      Enum.all?(values, &(&1 == true)) -> true
      true -> nil
    end
  end

  def premise(json, key, fencing) do
    with {:ok, state} <- TermCodec.decode_state(json),
         {:ok, {^key, amount, status}} <- Spec.lookup(elem(state, 4), key),
         true <- status in [:authorized, :voiding] do
      voiding =
        if status == :authorized, do: Ledger.step(state, {:void, key}) |> elem(0), else: state

      released = Ledger.step(voiding, {:void_confirmed, key}) |> elem(0)
      remote = [{key, amount, if(fencing, do: :voided, else: :approved)}]

      %{
        status: "illustration",
        key: key,
        amount: amount,
        local: 0,
        total_after: elem(released, 2),
        remote: if(fencing, do: 0, else: amount),
        covered: Environment.covered?({[{key, amount, :issued}], remote}, released),
        provenance:
          "current-entry counterfactual; terminal confirmation followed by delayed authorization"
      }
    else
      _ -> %{status: "not_applicable"}
    end
  end
end
