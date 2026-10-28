defmodule HoldLedgerReview.Contrast do
  @moduledoc "Typed actual/reference/hypothetical cases over the original evaluator."
  alias HoldLedger.{Ledger, Spec}
  alias HoldLedgerReview.{Adversarial, ClaimProbe, Claims, ProofReading, TermCodec, Trace}

  @seeds %{
    "po_a2" => "P04",
    "po_a4_duplicate" => "P08",
    "po_a4_conflict" => "P08",
    "po_b1_void" => "P05",
    "po_b1_timeout" => "P06",
    "po_exposure_retain" => "P05",
    "po_b2" => "P06",
    "po_b3" => "P05",
    "po_s" => "P05"
  }

  def create(slug) do
    with {:ok, doc} <- Trace.create_from(seed(slug)["before"]) do
      Trace.command(doc["id"], 0, Trace.token(), %{
        "kind" => "append",
        "parent" => "start",
        "event" => seed(slug)["event"]
      })
    end
  end

  def seed(slug) do
    {:ok, seed} = Adversarial.seed(Map.get(@seeds, slug, "P04"))

    if slug == "po_a4_duplicate" do
      seed |> put_in(["before", "entries", Access.at(0), "status"], "reserved")
    else
      seed
    end
  end

  def case_for(doc, cursor, slug, candidate \\ nil) do
    with true <- Trace.current?(doc),
         step when is_map(step) <- Trace.step(doc, cursor),
         true <- doc["mode"] == "ledger",
         {:ok, before} <- TermCodec.decode_state(step["before"]),
         {:ok, event} <- TermCodec.decode_event(step["event"]),
         {:ok, _receipt} <- TermCodec.decode_output(step["output"]) do
      actual = Ledger.step(before, event)

      output =
        candidate ||
          if(step["origin"] == "computed",
            do: default_candidate(slug, step),
            else: step["output"]
          )

      with {:ok, native} <- TermCodec.decode_output(output),
           {:ok, actual_json} <- TermCodec.encode_output(Ledger.step(before, event)),
           true <- step["origin"] != "computed" or actual_json == step["output"],
           :ok <- Claims.freshness() do
        row = ClaimProbe.probe(slug, before, event, native)

        explanation = explain(slug, step, output)

        comparison_slug = comparison_law(event)

        comparison = ClaimProbe.probe(comparison_slug, before, event, native)

        {:ok,
         %{
           "before" => step["before"],
           "event" => step["event"],
           "actual" => actual_json,
           "reference" => step["oracle"],
           "candidate" => output,
           "actual_valid" => Spec.valid?(elem(Ledger.step(before, event), 0)),
           "candidate_valid" => Spec.valid?(elem(native, 0)),
           "law_status" => Atom.to_string(row.status),
           "law_reason" => inspect(row.reason),
           "comparison_law" => comparison_slug,
           "comparison_status" => Atom.to_string(comparison.status),
           "comparison_actual" => comparison_actual(comparison_slug, before, event, actual),
           "explanation" => explanation,
           "origin" => step["origin"],
           "step_id" => step["id"]
         }}
      else
        _ -> {:error, :invalid_or_stale_case}
      end
    else
      _ -> {:error, :case_not_available}
    end
  end

  defp comparison_law(event),
    do: if(TermCodec.operation(event) == :void, do: "po_b1_void", else: "po_b1_timeout")

  defp explain(slug, step, output) do
    case ProofReading.explain(slug, %{
           "before" => step["before"],
           "event" => step["event"],
           "output" => output
         }) do
      {:ok, view} -> view
      {:error, reason} -> %{"bindings" => [], "complete" => false, "reason" => inspect(reason)}
    end
  end

  defp comparison_actual(slug, before, event, actual) do
    case ClaimProbe.explain(slug, before, event, actual) do
      {:ok, view} -> Enum.any?(view["bindings"], &(get_in(&1, ["actual", "value"]) == true))
      _ -> nil
    end
  end

  def default_candidate(slug, step) when slug in ~w(po_a2 po_a4_duplicate po_a4_conflict) do
    %{"after" => step["before"], "result" => "insufficient_amount", "effects" => []}
  end

  def default_candidate(_slug, step), do: early_release(step)

  def early_release(step) do
    output = step["output"]
    key = step["event"]["key"]

    entries =
      Enum.map(output["after"]["entries"], fn entry ->
        if entry["key"] == key, do: Map.put(entry, "status", "voided"), else: entry
      end)

    json = put_in(output, ["after", "entries"], entries)
    {:ok, state} = TermCodec.decode_state(json["after"])

    json
    |> put_in(["after", "used_amount"], Spec.hold_amount(elem(state, 4)))
    |> put_in(["after", "used_holds"], Spec.hold_count(elem(state, 4)))
    |> Map.put("result", "voided")
  end

  def parse_output(params) do
    with {:ok, state} <- parse_state(params),
         {:ok, effects} <- parse_effects(params["effects"] || %{}),
         output = %{"after" => state, "result" => params["result"], "effects" => effects},
         {:ok, _} <- TermCodec.decode_output(output),
         do: {:ok, output}
  end

  def parse_state(params) do
    state =
      Map.new(
        ~w(amount_limit hold_limit used_amount used_holds),
        &{&1, String.to_integer(to_string(params[&1]))}
      )

    entries = params["entries"] || %{}

    entries =
      entries
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map(fn {_, entry} ->
        %{
          "key" => String.to_integer(to_string(entry["key"])),
          "amount" => String.to_integer(to_string(entry["amount"])),
          "status" => entry["status"]
        }
      end)

    json = Map.put(state, "entries", entries)
    with {:ok, _} <- TermCodec.decode_state(json), do: {:ok, json}
  rescue
    _ -> {:error, :invalid_state_fields}
  end

  defp parse_effects(params) do
    effects =
      params
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map(fn {_, effect} ->
        %{
          "type" => effect["type"],
          "key" => String.to_integer(to_string(effect["key"])),
          "amount" =>
            if(effect["type"] == "authorize",
              do: String.to_integer(to_string(effect["amount"])),
              else: nil
            )
        }
      end)

    if Enum.all?(effects, &match?({:ok, _}, TermCodec.decode_effect(&1))),
      do: {:ok, effects},
      else: {:error, :invalid_effects}
  rescue
    _ -> {:error, :invalid_effects}
  end

  def output_form(output) do
    output["after"]
    |> Map.put("result", output["result"])
    |> Map.update!("entries", &indexed/1)
    |> Map.put("effects", indexed(output["effects"]))
  end

  def indexed(list),
    do: list |> Enum.with_index() |> Map.new(fn {value, i} -> {to_string(i), value} end)
end
