defmodule HoldLedgerReview.Adversarial do
  @moduledoc """
  Bounded, pure hypothetical evaluations. Fixtures are explicitly synthetic and
  cannot be confused with outputs observed under isolated mutant patches.
  The sole TermCodec and source-derived ClaimProbe own decoding and semantics.
  """
  alias HoldLedger.{Ledger, Spec}
  alias HoldLedgerReview.{Canonical, ClaimProbe, Claims, TermCodec}

  @seeds ~w(P01 P02 P03 P04 P05 P06 P07 P08)
  def seeds, do: @seeds

  def seed(id) when id in @seeds do
    path = Application.app_dir(:hold_ledger_review_web, "priv/scenarios/#{id}.json")

    with {:ok, bytes} <- File.read(path),
         {:ok, json} <- Jason.decode(bytes),
         {:ok, _} <- decode(json) do
      {:ok, json}
    end
  end

  def seed(_), do: {:error, :unknown_seed}

  def decode(
        %{"before" => before, "event" => event, "output" => output, "follow_on" => follow_on} =
          json
      )
      when map_size(json) == 4 do
    with {:ok, b} <- TermCodec.decode_state(before),
         {:ok, e} <- TermCodec.decode_event(event),
         {:ok, o} <- TermCodec.decode_output(output),
         {:ok, f} <- optional_event(follow_on) do
      {:ok, %{before: b, event: e, output: o, follow_on: f}}
    else
      _ -> {:error, :invalid_draft}
    end
  end

  def decode(_), do: {:error, :invalid_draft}

  def encode(%{before: before, event: event, output: output, follow_on: follow_on}) do
    with {:ok, b} <- TermCodec.encode_state(before),
         {:ok, e} <- TermCodec.encode_event(event),
         {:ok, o} <- TermCodec.encode_output(output),
         {:ok, f} <- encode_optional_event(follow_on) do
      {:ok, %{"before" => b, "event" => e, "output" => o, "follow_on" => f}}
    end
  end

  def from_form(form) when is_map(form) do
    keys = ~w(before_json event_json output_json follow_on_json)

    with true <-
           Enum.all?(keys, fn key -> is_binary(form[key]) and byte_size(form[key]) <= 12_000 end),
         [{:ok, before}, {:ok, event}, {:ok, output}, {:ok, follow}] <-
           Enum.map(keys, &Jason.decode(form[&1])) do
      decode(%{"before" => before, "event" => event, "output" => output, "follow_on" => follow})
    else
      _ -> {:error, :invalid_draft}
    end
  end

  def from_form(_), do: {:error, :invalid_draft}

  def form(witness) do
    %{
      "before_json" => Jason.encode!(witness["before"], pretty: true),
      "event_json" => Jason.encode!(witness["event"]),
      "output_json" => Jason.encode!(witness["output"], pretty: true),
      "follow_on_json" => Jason.encode!(witness["follow_on"])
    }
  end

  def evaluate(witness) do
    with :ok <- Claims.freshness() do
      result =
        Claims.memoize(__MODULE__, witness, fn ->
          result = evaluate_current(witness)

          case Claims.freshness() do
            :ok -> result
            _ -> {:error, :stale_source}
          end
        end)

      case Claims.freshness() do
        :ok -> result
        _ -> {:error, :stale_source}
      end
    else
      _ -> {:error, :stale_source}
    end
  end

  defp evaluate_current(witness) do
    with {:ok, decoded} <- decode(witness),
         true <- Spec.valid?(decoded.before),
         actual = Ledger.step(decoded.before, decoded.event),
         oracle = Spec.expected_step(decoded.before, decoded.event),
         {:ok, actual_json} <- TermCodec.encode_output(actual),
         {:ok, oracle_json} <- TermCodec.encode_output(oracle),
         {:ok, _candidate_json} <- TermCodec.encode_output(decoded.output),
         {:ok, after_json} <- TermCodec.encode_state(elem(decoded.output, 0)) do
      slugs = active_slugs(decoded.event)
      checks = ClaimProbe.probe_all(decoded.before, decoded.event, decoded.output, slugs: slugs)
      follow = ClaimProbe.follow_on(actual, decoded.output, decoded.follow_on)

      with {:ok, follow_actual} <- optional_output(follow.actual),
           {:ok, follow_candidate} <- optional_output(follow.candidate) do
        rows =
          Enum.map(slugs, &law_row(&1, checks[&1]))

        {:ok,
         %{
           "candidate_hash" => Canonical.digest(witness["output"]),
           "actual" => actual_json,
           "oracle" => oracle_json,
           "law_rows" => rows,
           "follow_on_actual" => follow_actual,
           "follow_on_candidate" => follow_candidate,
           "scope" => "pointwise_pure_ledger"
         },
         %{
           checks: checks,
           candidate_after_valid?: Spec.valid?(elem(decoded.output, 0)),
           actual_equals_oracle?: actual == oracle,
           changed_fields: differences(actual_json, witness["output"]),
           follow_reason: follow.reason,
           after: after_json,
           request_eligible?: request_eligible(decoded.before, decoded.event)
         }}
      else
        {:error, :source_or_compiled_code_drift} -> {:error, :stale_source}
        error -> error
      end
    else
      false -> {:error, :invalid_before_state}
      {:error, :source_or_compiled_code_drift} -> {:error, :stale_source}
      _ -> {:error, :invalid_draft}
    end
  end

  defp law_row(slug, check) do
    %{
      "slug" => slug,
      "label" => label(check.status),
      "reason" => inspect(check.reason),
      "source_sha256" => Map.get(check, :source_sha256, ""),
      "bindings_tested" => check.bindings_tested,
      "exhaustive_for_source_domain" => check.exhaustive_for_source_domain
    }
  end

  def active_slugs(event) do
    operation =
      case event do
        {:request, _, _} -> :request
        {:void, _} -> :void
        {:timeout, _} -> :timeout
        {:dispatch, _} -> :dispatch
      end

    generation = Claims.snapshot()

    generation.claims
    |> Enum.filter(fn {_slug, law} -> law.operation in [:step, operation] end)
    |> Enum.map(&elem(&1, 0))
    |> Enum.sort()
  end

  defp request_eligible(before, {:request, key, amount}),
    do: Spec.request_eligible?(before, key, amount)

  defp request_eligible(_, _), do: nil

  def differences(actual, candidate) do
    for key <- ~w(after result effects),
        actual[key] != candidate[key],
        do: %{
          "field" => key,
          "actual" => actual[key],
          "hypothetical" => candidate[key]
        }
  end

  defp optional_event(nil), do: {:ok, nil}
  defp optional_event(x), do: TermCodec.decode_event(x)
  defp encode_optional_event(nil), do: {:ok, nil}
  defp encode_optional_event(x), do: TermCodec.encode_event(x)
  defp optional_output(nil), do: {:ok, nil}
  defp optional_output({:ok, output}), do: TermCodec.encode_output(output)
  # A non-Spec-valid but structurally valid candidate remains analyzable.
  # A follow-on step cannot be run from that state and is explicitly null.
  defp optional_output({:error, :invalid_state}), do: {:ok, nil}

  defp label(status) when status == :doesnt_apply, do: "does_not_apply"

  defp label(status) when status in [:catches, :allows_here, :cant_check],
    do: Atom.to_string(status)

  defp label(_), do: "cant_check"
end
