defmodule HoldLedgerReview.Part3BoundarySearch do
  @moduledoc """
  Deterministic bounded challenges directed by changed source categories.
  These are drafts, not findings. Only isolated replay of both identified
  snapshots can compute a distinction. No solver or history theorem is implied.
  """
  alias HoldLedgerReview.{Adversarial, Canonical, TermCodec}

  @max_cases 48
  @relevant ~w(claim called_definition_or_behavior obligation_or_inventory lean_declaration_or_dependency translation_or_elaboration)
  @holding ~w(reserved sent unknown authorized voiding)

  def cases(package, witness) do
    changes = Enum.filter(package["source_changes"], &(&1["kind"] in @relevant))

    if changes == [] do
      []
    else
      (amount_cases(witness) ++
         status_cases(witness) ++
         identity_cases(witness) ++
         output_cases(witness) ++ frame_cases(witness) ++ history_cases(witness))
      |> Enum.uniq_by(fn {_label, w} -> Canonical.digest(w) end)
      |> Enum.flat_map(&validated(&1, changes))
      |> Enum.take(@max_cases)
    end
  end

  def limits do
    %{
      "max_cases" => @max_cases,
      "history_depth" => 2,
      "general_relation" => "unresolved",
      "representation_mapping" => "not_inferred",
      "inventory_scope" =>
        "all source-supported bindings per replay; native-only obligations unresolved"
    }
  end

  defp amount_cases(%{"event" => %{"type" => "request"}, "before" => before} = w) do
    remaining = before["amount_limit"] - before["used_amount"]

    for amount <- Enum.uniq([remaining - 1, remaining, remaining + 1, 1]),
        amount > 0 and amount <= TermCodec.limits().number do
      {"request amount boundary #{amount}", put_in(w, ["event", "amount"], amount)}
    end
  end

  defp amount_cases(_), do: []

  defp status_cases(w) do
    # Fixed synthetic inputs cover each status, existing/absent keys and an
    # unrelated remembered identity. They do not assert reachability or policy.
    for status <- TermCodec.statuses(), type <- ~w(request dispatch timeout void) do
      holding = status in @holding

      before = %{
        "amount_limit" => 100,
        "hold_limit" => 2,
        "used_amount" => if(holding, do: 100, else: 0),
        "used_holds" => if(holding, do: 1, else: 0),
        "entries" => [
          %{"key" => 1, "amount" => 100, "status" => status},
          %{"key" => 7, "amount" => 1, "status" => "voided"}
        ]
      }

      event = %{"type" => type, "key" => 1, "amount" => if(type == "request", do: 100, else: nil)}
      {"#{status}: #{type} with unrelated identity", %{w | "before" => before, "event" => event}}
    end
  end

  defp identity_cases(w) do
    for key <- Enum.uniq([0, 1, 7, w["event"]["key"]]) do
      {"event identity #{key}", put_in(w, ["event", "key"], key)}
    end
  end

  defp output_cases(w) do
    output = w["output"]
    after_state = output["after"]

    candidates = [
      {"candidate frame: drop entries", put_in(w, ["output", "after", "entries"], [])},
      {"candidate accounting: zero totals",
       put_in(w, ["output", "after"], %{after_state | "used_amount" => 0, "used_holds" => 0})},
      {"candidate effects: omit intents", put_in(w, ["output", "effects"], [])},
      {"candidate effects: wrong identity",
       put_in(w, ["output", "effects"], [%{"type" => "authorize", "key" => 7, "amount" => 1}])},
      {"candidate result: stale", put_in(w, ["output", "result"], "stale")}
    ]

    candidates ++
      for {entry, index} <- Enum.with_index(after_state["entries"]) do
        {"candidate identity at entry #{index}",
         put_in(
           w,
           ["output", "after", "entries"],
           List.replace_at(after_state["entries"], index, %{entry | "key" => 7})
         )}
      end
  end

  defp frame_cases(w) do
    {_label, seed} = hd(status_cases(w))
    seed = put_in(seed, ["output", "after"], seed["before"])

    [
      {"candidate frame: remove unrelated remembered identity",
       put_in(seed, ["output", "after", "entries"], Enum.take(seed["before"]["entries"], 1))}
    ]
  end

  defp history_cases(w) do
    for event <- [
          %{"type" => "request", "key" => 7, "amount" => 1},
          %{"type" => "timeout", "key" => 1, "amount" => nil},
          %{"type" => "void", "key" => 1, "amount" => nil}
        ] do
      {"two-event consequence: #{event["type"]}", Map.put(w, "follow_on", event)}
    end
  end

  defp validated({label, candidate}, changes) do
    with {:ok, decoded} <- Adversarial.decode(candidate),
         {:ok, ^candidate} <- Adversarial.encode(decoded) do
      [
        %{
          "id" => Canonical.digest(candidate),
          "label" => label,
          "witness" => candidate,
          "requested_amount" => candidate["event"]["amount"],
          "source_change_ids" => Enum.map(changes, & &1["id"]),
          "method" => "deterministic bounded challenges; max 48; not state-space coverage"
        }
      ]
    else
      _ -> []
    end
  end
end
