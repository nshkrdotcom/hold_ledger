defmodule HoldLedgerReview.ClaimLens do
  @moduledoc """
  Small, curated *illustrations* of semantic changes to two real obligations.

  The baseline result is always the unmodified, source-bound `ClaimProbe`.
  Proposed preconditions are deliberately transparent, hand-authored pointwise
  models, never rewritten law AST, compiled Lean, or a source comparison.
  Policy expectations are independently curated from `guides/specification.md`;
  no rule evaluator supplies the policy judgment.
  """

  alias HoldLedger.{Ledger, Spec}
  alias HoldLedgerReview.{Anchor, ClaimProbe, Claims, Config, ProofReading, TermCodec}

  @studies [
    %{
      slug: "po_a2",
      title: "Exact-fit admission",
      question: "Does this claim cover a request for all available capacity?",
      summary: "Check which requests the claim covers before deciding what it guarantees.",
      policy: "An exact amount fit is admitted.",
      policy_section: "Events · request eligibility",
      clause: "Spec.request_eligible?(s, key, amount)",
      changed_clause: "Spec.request_eligible?(s, key, amount) and amount < remaining",
      connection: "capacity-amount",
      mutant: "mutants/04_exact_fit",
      variations: [
        %{
          id: "original",
          title: "Authored claim",
          short: "No edit",
          detail: "Use the claim’s original starting condition."
        },
        %{
          id: "strict",
          title: "Exclude exact fit",
          short: "Tighten requires",
          detail:
            "Add amount < remaining to requires. The claim then leaves out an exact-fit request."
        },
        %{
          id: "proof_only",
          title: "Proof-body-only control",
          short: "No contract delta",
          detail:
            "Only the proof body’s formatting changes in this example. The claim stays the same; the revised proof has not been checked."
        }
      ],
      witnesses: [
        %{
          id: "below",
          title: "99¢ · below capacity",
          description: "One cent remains",
          policy: :forbidden,
          reason: "An eligible fresh request must be admitted."
        },
        %{
          id: "exact",
          title: "100¢ · exact fit",
          description: "Uses every available cent",
          policy: :forbidden,
          reason: "The specification explicitly requires exact-fit admission."
        },
        %{
          id: "above",
          title: "101¢ · over capacity",
          description: "Exceeds available amount",
          policy: :allowed,
          reason: "Rejection is required when the amount exceeds capacity."
        }
      ],
      default_witness: "exact",
      default_variation: "strict"
    },
    %{
      slug: "po_exposure_retain",
      title: "Retention before terminal evidence",
      question: "When must the ledger keep a hold reserved?",
      summary: "Compare a request to cancel with confirmation that cancellation is complete.",
      policy:
        "An issued or potentially issued authorization continues consuming local capacity until reliable terminal evidence allows release.",
      policy_section: "Uncertain outcomes and identities",
      clause: "not Spec.release_evidence?(event, key)",
      changed_clause: "true (omit the release-evidence exclusion)",
      connection: "retain-release",
      mutant: "mutants/10_premature_void_release",
      variations: [
        %{
          id: "original",
          title: "Authored claim",
          short: "No edit",
          detail: "The original claim excludes events that provide evidence for releasing the hold."
        },
        %{
          id: "drop_release",
          title: "Remove the release exclusion",
          short: "Broaden requires",
          detail:
            "Remove the release-evidence condition. The claim would then require money to stay held even after a valid release."
        },
        %{
          id: "proof_only",
          title: "Proof-body-only control",
          short: "No contract delta",
          detail:
            "Only the proof body’s formatting changes in this example. The claim stays the same; the revised proof has not been checked."
        }
      ],
      witnesses: [
        %{
          id: "void",
          title: "Authorized → void requested",
          description: "No terminal confirmation",
          policy: :forbidden,
          reason: "A local void request cannot free an authorized hold."
        },
        %{
          id: "confirmed",
          title: "Voiding → confirmed",
          description: "Terminal confirmation received",
          policy: :allowed,
          reason: "Trusted terminal confirmation is sufficient to release capacity."
        },
        %{
          id: "timeout",
          title: "Sent → timeout",
          description: "Processor outcome still unknown",
          policy: :forbidden,
          reason: "Timeout alone is not terminal release evidence."
        }
      ],
      default_witness: "confirmed",
      default_variation: "drop_release"
    }
  ]

  @doc "Curated study metadata; no user-generated law or policy expressions."
  def studies, do: @studies

  def study(slug) when is_binary(slug) do
    case Enum.find(@studies, &(&1.slug == slug)) do
      nil -> {:error, :unknown_study}
      found -> {:ok, found}
    end
  end

  def study(_), do: {:error, :unknown_study}

  @doc "Find an exact independently curated policy quote in current registered bytes."
  def policy_line(study, reading) do
    policy_source = Enum.find(reading["sources"], &(&1["path"] == "guides/specification.md"))

    with %{"sha256" => expected} <- policy_source,
         {:ok, bytes} <- Anchor.read_under(Config.root(), "guides/specification.md"),
         true <- Anchor.sha(bytes) == expected,
         line when is_integer(line) <-
           Enum.find_index(String.split(bytes, "\n"), &String.contains?(&1, study.policy)) do
      {:ok, line + 1}
    else
      _ -> {:error, :policy_quote_unavailable}
    end
  end

  @doc "A small pointwise witness, using the original evaluator for its baseline."
  def observe(slug, witness_id, variation_id) do
    with {:ok, study} <- study(slug),
         {:ok, reading} <- ProofReading.document(slug),
         true <- reading["reading_current"],
         {:ok, _line} <- policy_line(study, reading),
         %{id: ^witness_id} = witness <- Enum.find(study.witnesses, &(&1.id == witness_id)),
         %{id: ^variation_id} = variation <-
           Enum.find(study.variations, &(&1.id == variation_id)),
         {:ok, values} <- witness_values(slug, witness_id),
         {:ok, before_json} <- TermCodec.encode_state(values.before),
         {:ok, event_json} <- TermCodec.encode_event(values.event),
         {:ok, candidate_json} <- TermCodec.encode_output(values.candidate),
         {:ok, actual_json} <- TermCodec.encode_output(values.actual),
         {:ok, explanation} <-
           ProofReading.explain(slug, %{
             "before" => before_json,
             "event" => event_json,
             "output" => candidate_json
           }) do
      baseline = ClaimProbe.probe(slug, values.before, values.event, values.candidate)
      alternative = alternative(slug, variation_id, values, baseline)

      {:ok,
       %{
         study: study,
         witness: witness,
         variation: variation,
         before: before_json,
         event: event_json,
         actual: actual_json,
         candidate: candidate_json,
         baseline: baseline,
         alternative: alternative,
         explanation: explanation,
         source_path: values.source_path,
         changed?: variation_id not in ~w(original proof_only)
       }}
    else
      _ -> {:error, :observation_unavailable}
    end
  end

  @doc "Input applicability across the three curated witnesses, never proof acceptance."
  def coverage(slug, variation_id) do
    result =
      Claims.with_generation(Config.root(), fn _ -> current_coverage(slug, variation_id) end)

    case result do
      {:ok, rows} -> rows
      _ -> {:error, :coverage_unavailable}
    end
  end

  defp current_coverage(slug, variation_id) do
    with {:ok, study} <- study(slug),
         true <- Enum.any?(study.variations, &(&1.id == variation_id)),
         {:ok, reading} <- ProofReading.document(slug),
         true <- reading["reading_current"],
         {:ok, _line} <- policy_line(study, reading) do
      Claims.memoize(__MODULE__, {:coverage, slug, variation_id}, fn ->
        coverage_rows(study, variation_id)
      end)
    else
      _ -> {:error, :coverage_unavailable}
    end
  end

  defp coverage_rows(study, variation_id) do
    Enum.reduce_while(study.witnesses, {:ok, []}, fn witness, {:ok, rows} ->
      {:ok, values} = witness_values(study.slug, witness.id)
      baseline = ClaimProbe.probe(study.slug, values.before, values.event, values.candidate)
      hypothetical = alternative(study.slug, variation_id, values, baseline)

      if baseline.status == :cant_check or hypothetical.status == :cant_check do
        {:halt, {:error, :coverage_unavailable}}
      else
        row = %{
          id: witness.id,
          title: witness.title,
          original: baseline.status != :doesnt_apply,
          hypothetical: hypothetical.status != :doesnt_apply
        }

        {:cont, {:ok, rows ++ [row]}}
      end
    end)
  end

  defp witness_values("po_a2", id) when id in ~w(below exact above) do
    amount = %{"below" => 99, "exact" => 100, "above" => 101}[id]
    before = {100, 2, 0, 0, []}
    event = {:request, 11, amount}

    {:ok,
     %{
       before: before,
       event: event,
       actual: Ledger.step(before, event),
       candidate: {before, :insufficient_amount, []},
       amount: amount,
       source_path: "test/laws/po_a2_test.exs"
     }}
  end

  defp witness_values("po_exposure_retain", id) when id in ~w(void confirmed timeout) do
    {status, event, wrong_status, wrong_result, wrong_effects} =
      case id do
        "void" -> {:authorized, {:void, 1}, :voided, :voided, [{:void, 1}]}
        "confirmed" -> {:voiding, {:void_confirmed, 1}, :voided, :voided, []}
        "timeout" -> {:sent, {:timeout, 1}, :voided, :marked_unknown, []}
      end

    before = {100, 2, 100, 1, [{1, 100, status}]}
    actual = Ledger.step(before, event)

    candidate =
      if id == "confirmed",
        do: actual,
        else: {{100, 2, 0, 0, [{1, 100, wrong_status}]}, wrong_result, wrong_effects}

    {:ok,
     %{
       before: before,
       event: event,
       actual: actual,
       candidate: candidate,
       source_path: "test/laws/po_exposure_retain_test.exs"
     }}
  end

  defp witness_values(_, _), do: {:error, :unsupported_witness}

  # This is NOT a source-compiled altered claim. We evaluate exactly the one
  # documented predicate edit on these fixed cases and leave expects unchanged.
  defp alternative(_, _, _, %{status: :cant_check} = probe),
    do: %{status: :cant_check, reason: probe.reason, applies?: nil}

  defp alternative("po_a2", "strict", %{amount: amount} = values, baseline) do
    remaining = elem(values.before, 0) - elem(values.before, 2)
    altered_baseline(baseline, amount < remaining)
  end

  defp alternative("po_exposure_retain", "drop_release", values, baseline) do
    {_, _, _, _, entries} = values.before
    [{key, amount, status}] = entries

    applies? = retention_domain?(values.before, entries, key, amount, status)

    status =
      cond do
        not applies? -> :doesnt_apply
        Spec.exposed_entry?(elem(values.candidate, 0), key, amount) -> :allows_here
        true -> :catches
      end

    # The original source binding must agree whenever it applies. If it does
    # not, do not publish a synthetic comparison as though it were evidence.
    if baseline.status != :doesnt_apply and baseline.status != status do
      %{status: :cant_check, reason: :baseline_mismatch, applies?: nil}
    else
      %{status: status, reason: :hand_modelled_precondition, applies?: applies?}
    end
  end

  defp alternative(_, _, _, baseline), do: altered_baseline(baseline, true)

  defp retention_domain?(before, entries, key, amount, status) do
    Spec.valid?(before) and is_integer(key) and is_integer(amount) and
      Spec.lookup(entries, key) === {:ok, {key, amount, status}} and
      status in [:sent, :unknown, :authorized, :voiding]
  end

  defp altered_baseline(baseline, extra_guard?) do
    applies? = baseline.status != :doesnt_apply and extra_guard?

    %{
      status: if(applies?, do: baseline.status, else: :doesnt_apply),
      reason: :hand_modelled_precondition,
      applies?: applies?
    }
  end
end
