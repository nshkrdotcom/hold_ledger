defmodule HoldLedgerReviewWeb.Education do
  @moduledoc """
  Source-catalog-backed educational navigation. This is editorial interpretation,
  never an independent specification, proof result, or kernel dependency graph.
  """
  alias HoldLedgerReview.ProofReading

  @metadata_path Path.expand("../../priv/education_claims.json", __DIR__)
  @glossary_path Path.expand("../../priv/education_glossary.json", __DIR__)
  @external_resource @metadata_path
  @external_resource @glossary_path
  @metadata Jason.decode!(File.read!(@metadata_path))["claims"]
  @terms Jason.decode!(File.read!(@glossary_path))["terms"]
  @meta_by_slug Map.new(@metadata, &{&1["slug"], &1})

  @families [
    %{
      id: "Foundations",
      description: "The bookkeeping pieces other statements use",
      question: "Can we find, replace and count holds correctly?",
      number: "01"
    },
    %{
      id: "Admission",
      description: "Starting states, requests, duplicate keys and exact fit",
      question: "When must a new request be admitted?",
      number: "02"
    },
    %{
      id: "Single-step safety",
      description: "What one modeled event may do",
      question: "Does a valid state stay valid after an event?",
      number: "03"
    },
    %{
      id: "Identity & lifecycle",
      description: "Timeouts, final decisions, request IDs and external effects",
      question: "Can an old or uncertain hold be mishandled?",
      number: "04"
    },
    %{
      id: "Histories",
      description: "Safety over finite event and journal sequences",
      question: "Do safe steps compose into safe histories?",
      number: "05"
    },
    %{
      id: "Attempts",
      description: "Runtime attempt slots, retirement and persistence models",
      question: "Can late or concurrent attempts interfere?",
      number: "06"
    },
    %{
      id: "Processor & exposure",
      description: "Modeled remote authorization, fencing and reserved capacity",
      question: "What could still be live outside the ledger?",
      number: "07"
    },
    %{
      id: "Composite & recovery",
      description: "Ledger state, pending voids and committed replay",
      question: "Can state and outstanding work recover together?",
      number: "08"
    }
  ]

  @guarantees [
    %{
      id: "admission",
      number: "01",
      title: "Respect available capacity",
      nutshell:
        "Fresh requests that fit the money and slot limits must be admitted, including an exact fit.",
      safe: "100 cents requested with 100 cents free and an open slot is admitted.",
      unsafe: "A strict less-than guard silently excludes the exact-fit request.",
      slugs: ~w(po_a2 po_a4_duplicate po_a4_conflict po_i)
    },
    %{
      id: "uncertainty",
      number: "02",
      title: "Treat silence as uncertainty",
      nutshell: "A timeout cannot release a possibly live remote authorization.",
      safe: "A sent hold becomes unknown and still consumes capacity.",
      unsafe: "The server treats a missing reply as a decline and frees the same capacity.",
      slugs: ~w(po_b1_timeout po_b2 po_b7 po_exposure_retain)
    },
    %{
      id: "identity",
      number: "03",
      title: "Remember who requested what",
      nutshell: "Repeated keys preserve their original amount and cannot be reused as new holds.",
      safe: "A retry uses the same identity and amount.",
      unsafe: "The retry creates another remotely live authorization ID.",
      slugs: ~w(l2_identity po_b6 po_a4_duplicate po_a4_conflict)
    },
    %{
      id: "terminal",
      number: "04",
      title: "Make final results final",
      nutshell: "Declined and voided holds cannot be revived by late events.",
      safe: "A terminal record remains remembered after capacity is released.",
      unsafe: "A delayed authorization resuscitates a voided request.",
      slugs: ~w(po_b5_declined po_b5_voided po_terminal_fence)
    },
    %{
      id: "effects",
      number: "05",
      title: "Request the right remote work",
      nutshell: "Authorization and void effects must correspond to the correct key and amount.",
      safe: "A void request emits the matching remote-void intent while retaining capacity.",
      unsafe: "The hold stays reserved but the required void effect is omitted.",
      slugs: ~w(po_b3 po_b1_void po_exposure_retain)
    },
    %{
      id: "recovery",
      number: "06",
      title: "Recover state with pending work",
      nutshell:
        "Journal replay and pending void work must remain consistent with the modeled composite state.",
      safe: "Committed operations reconstruct the modeled composite state.",
      unsafe: "Recovery loses a required pending void or forgets a held amount.",
      slugs: ~w(po_c2 po_composite_recovery po_composite_open po_composite_recovery_valid)
    }
  ]

  @components [
    %{
      id: "policy",
      title: "Independent policy",
      role: "Defines what the model should do",
      path: "guides/specification.md",
      explanation:
        "Human-authored policy is the anchor for judging whether a mathematically checked statement is the right statement.",
      link: "/guarantees"
    },
    %{
      id: "ledger",
      title: "Pure Ledger",
      role: "Computes a state transition",
      path: "lib/hold_ledger/ledger.ex",
      explanation:
        "Ledger.step/2 receives state and an event, then returns next state, a result and requested effects, without actually contacting a processor.",
      link: "/repository"
    },
    %{
      id: "spec",
      title: "Behavioral Spec",
      role: "An independent behavioral reference",
      path: "lib/hold_ledger/spec.ex",
      explanation:
        "The Spec is separately implemented so comparing Ledger against Spec is not simply asking Ledger to validate itself.",
      link: "/proofs"
    },
    %{
      id: "laws",
      title: "Laws and claims",
      role: "State exact verification obligations",
      path: "test/laws/ and verification/laws.json",
      explanation:
        "Elixir/Lynx law groups include requires and expects. Native Lean groups express properties of models and histories instead.",
      link: "/atlas"
    },
    %{
      id: "runtime",
      title: "Journal and runtime",
      role: "Persist and dispatch requested work",
      path: "lib/hold_ledger/",
      explanation:
        "Runtime manages durable input and external effects. A pure-state proof is not automatically a proof of disk persistence or networking.",
      link: "/assurance"
    },
    %{
      id: "processor",
      title: "External processor",
      role: "May accept, decline or void",
      path: "Modeled interface and external trust contract",
      explanation:
        "The model can assume processor properties such as terminal fencing; real processor compliance requires separate evidence.",
      link: "/assurance"
    }
  ]

  @statuses [
    %{
      id: "reserved",
      label: "Reserved",
      description: "Accepted locally, not yet dispatched.",
      detail:
        "The amount and slot are held. Because no remote request has been sent, a local cancellation can release them without a remote void effect."
    },
    %{
      id: "sent",
      label: "Sent",
      description: "The authorization may now be live remotely.",
      detail:
        "A sent request retains its reservation. A network acknowledgment is not an approval or decline."
    },
    %{
      id: "unknown",
      label: "Unknown",
      description: "The remote outcome is not established.",
      detail:
        "A timeout does not mean the processor declined. This hold still consumes amount and slot capacity."
    },
    %{
      id: "authorized",
      label: "Authorized",
      description: "A trusted approval was received.",
      detail:
        "Capacity stays reserved until a permitted terminal transition, such as confirmed cancellation."
    },
    %{
      id: "voiding",
      label: "Voiding",
      description: "Remote cancellation was requested.",
      detail:
        "The request to void is an effect intent. It is not terminal evidence. Keep the reservation in place."
    },
    %{
      id: "declined",
      label: "Declined",
      description: "A trusted negative result is final.",
      detail:
        "The capacity can be released, while the original identity and amount remain remembered."
    },
    %{
      id: "voided",
      label: "Voided",
      description: "Cancellation has been confirmed.",
      detail:
        "Release the reservation only after the modeled terminal condition. Retain the identity so late replay cannot create a new hold."
    }
  ]

  def families, do: @families
  def guarantees, do: @guarantees
  def components, do: @components
  def statuses, do: @statuses
  def glossary, do: @terms
  def title(slug), do: get_in(@meta_by_slug, [slug, "title"])
  def term(id), do: Enum.find(@terms, &(&1["id"] == id))
  def editorial_slugs, do: Map.keys(@meta_by_slug) |> Enum.sort()

  @doc "Returns the live registry combined with editorial titles. No checker status is inferred."
  def claims do
    with {:ok, registered} <- ProofReading.catalog() do
      {:ok, Enum.map(registered, &enrich/1)}
    end
  end

  def find_claim(slug) do
    with {:ok, list} <- claims(),
         item when not is_nil(item) <- Enum.find(list, &(&1["slug"] == slug)) do
      {:ok, item}
    else
      _ -> {:error, :not_registered}
    end
  end

  def inventory(claims) do
    %{
      total: length(claims),
      elixir: Enum.count(claims, &(&1["kind"] == "elixir_law")),
      lean: Enum.count(claims, &(&1["kind"] == "native_lean")),
      unmapped: Enum.reject(claims, &Map.has_key?(@meta_by_slug, &1["slug"]))
    }
  end

  def by_family(claims, family), do: Enum.filter(claims, &(&1["family"] == family))

  defp enrich(law) do
    meta = Map.get(@meta_by_slug, law["slug"], %{})

    law
    |> Map.merge(meta)
    |> Map.put("kind", if(law["kind"] == "lean", do: "native_lean", else: "elixir_law"))
    |> Map.put("education_source_path", educational_source(law))
    |> Map.put_new("family", "Unmapped")
  end

  defp educational_source(%{"kind" => "lean", "module" => module}) when is_binary(module) do
    name = module |> String.split(".") |> List.last()
    path = "test/support/lean/" <> name <> ".lean"

    if Regex.match?(~r/\A[A-Za-z0-9_]+\z/, name) and
         File.regular?(Path.join(HoldLedgerReview.Config.root(), path)), do: path, else: nil
  end

  defp educational_source(law), do: law["file"]
end
