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
      description: "Find entries, preserve identities and count held capacity.",
      question: "Can we find, replace and count holds correctly?",
      number: "01"
    },
    %{
      id: "Admission",
      description: "Admit eligible requests and recognize repeated keys.",
      question: "When must a new request be admitted?",
      number: "02"
    },
    %{
      id: "Single-step safety",
      description: "Keep the account valid as each event is handled.",
      question: "Does a valid state stay valid after an event?",
      number: "03"
    },
    %{
      id: "Identity & lifecycle",
      description: "Keep the right capacity through timeouts and final results.",
      question: "Can an old or uncertain hold be mishandled?",
      number: "04"
    },
    %{
      id: "Histories",
      description: "Follow a finite sequence of events or journal entries.",
      question: "Do safe steps compose into safe histories?",
      number: "05"
    },
    %{
      id: "Attempts",
      description: "Track active work and retire attempts without losing identity.",
      question: "Can late or concurrent attempts interfere?",
      number: "06"
    },
    %{
      id: "Processor & exposure",
      description: "Relate local holds to possible remote authorizations.",
      question: "What could still be live outside the ledger?",
      number: "07"
    },
    %{
      id: "Composite & recovery",
      description: "Recover both ledger state and unfinished void work.",
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
      safe: "With 100¢ free and an open slot, a new request for 100¢ is admitted.",
      unsafe:
        "Using < instead of <= rejects the exact fit. The remaining state can still be valid.",
      slugs: ~w(po_a2 po_a4_duplicate po_a4_conflict po_i)
    },
    %{
      id: "uncertainty",
      number: "02",
      title: "Treat silence as uncertainty",
      nutshell:
        "A missing reply leaves the authorization's outcome unknown. Its capacity stays held.",
      safe: "A 100¢ sent hold becomes unknown after a timeout and still uses 100¢ and one slot.",
      unsafe:
        "The timeout frees 100¢, allowing another request while the first authorization may still be live.",
      slugs: ~w(po_b1_timeout po_b2 po_b7 po_exposure_retain)
    },
    %{
      id: "identity",
      number: "03",
      title: "Remember who requested what",
      nutshell: "The same key keeps its original amount, including after the hold has finished.",
      safe:
        "Request 11 for 100¢ returns duplicate when repeated. The same key for 50¢ returns conflict.",
      unsafe:
        "A repeated request creates a second hold, or a conflicting amount replaces the first one.",
      slugs: ~w(l2_identity po_b6 po_a4_duplicate po_a4_conflict)
    },
    %{
      id: "terminal",
      number: "04",
      title: "Make final results final",
      nutshell:
        "The ledger keeps declined and voided records and ignores late results for those holds.",
      safe: "A late approval for a locally voided key leaves its terminal record unchanged.",
      unsafe:
        "The ledger revives the finished hold. Preventing revival at the processor also needs remote fencing.",
      slugs: ~w(po_b5_declined po_b5_voided po_terminal_fence)
    },
    %{
      id: "effects",
      number: "05",
      title: "Request the right outside work",
      nutshell: "Authorization and void effects must correspond to the correct key and amount.",
      safe: "Voiding authorized hold 11 requests a void for key 11 and keeps its capacity held.",
      unsafe: "The state changes to voiding, but the output omits the requested void effect.",
      slugs: ~w(po_b3 po_b1_void po_exposure_retain)
    },
    %{
      id: "recovery",
      number: "06",
      title: "Recover state with pending work",
      nutshell: "Recovery must restore the ledger together with the void work it still owes.",
      safe:
        "Replaying the committed prefix restores the corresponding ledger state and pending voids.",
      unsafe: "Recovery restores a voiding hold but loses the record of the void still owed.",
      slugs: ~w(po_c2 po_composite_recovery po_composite_open po_composite_recovery_valid)
    }
  ]

  @components [
    %{
      id: "policy",
      title: "Policy",
      role: "Sets the required behavior",
      path: "guides/specification.md",
      explanation:
        "The policy says when a request must be admitted and when held capacity may be released. Start here when deciding whether a claim asks the right question.",
      link: "/guarantees"
    },
    %{
      id: "ledger",
      title: "Ledger",
      role: "Handles one input event",
      path: "lib/hold_ledger/ledger.ex",
      explanation:
        "Ledger.step/2 takes the account state and an event. It returns the next state, a result and any requested effects. For a dispatch, that includes the authorization to request outside the ledger.",
      link: "/repository"
    },
    %{
      id: "spec",
      title: "Independent Spec",
      role: "Describes the expected result",
      path: "lib/hold_ledger/spec.ex",
      explanation:
        "Spec computes expected behavior separately from Ledger. Claims can compare the two, and reviewers can follow a named predicate such as request_eligible? to see which inputs it includes.",
      link: "/proofs"
    },
    %{
      id: "laws",
      title: "Claims",
      role: "State exactly what is checked",
      path: "test/laws/ and verification/laws.json",
      explanation:
        "An Elixir law states its input conditions in requires and its promised result in expects. Lean-only claims state properties directly about the repository's models and histories.",
      link: "/atlas"
    },
    %{
      id: "runtime",
      title: "Journal and runtime",
      role: "Record inputs and perform outside work",
      path: "lib/hold_ledger/",
      explanation:
        "The runtime syncs inputs to the journal before applying them and dispatching requested effects. Storage durability, crashes and network delivery need evidence beyond the pure transition.",
      link: "/assurance"
    },
    %{
      id: "processor",
      title: "External processor",
      role: "Owns the remote authorization",
      path: "guides/processors.md",
      explanation:
        "The processor can approve, decline or void an authorization. The model relies on properties such as permanent terminal fencing; a real adapter must establish that its processor honors them.",
      link: "/assurance"
    }
  ]

  @statuses [
    %{
      id: "reserved",
      label: "Reserved",
      description: "Accepted locally, not yet dispatched.",
      detail:
        "The amount and slot are held. A cancellation before dispatch releases both locally, with no remote void requested."
    },
    %{
      id: "sent",
      label: "Sent",
      description: "Dispatch is recorded; the remote outcome is pending.",
      detail:
        "The ledger has requested authorization and keeps the amount and slot held. This state alone does not establish delivery, approval or decline."
    },
    %{
      id: "unknown",
      label: "Unknown",
      description: "The authorization's outcome is unknown.",
      detail:
        "A timeout or restart can leave the outcome uncertain. The authorization may still be live, so the amount and slot stay held."
    },
    %{
      id: "authorized",
      label: "Authorized",
      description: "A trusted approval was received.",
      detail:
        "The processor approved the authorization. Its amount and slot stay held, including while an ensuing void is awaiting confirmation."
    },
    %{
      id: "voiding",
      label: "Voiding",
      description: "A void has been requested and is awaiting confirmation.",
      detail:
        "The authorized hold keeps its amount and slot. Requesting a void does not establish that it happened; release waits for trusted confirmation."
    },
    %{
      id: "declined",
      label: "Declined",
      description: "The processor declined the authorization.",
      detail:
        "The amount and slot are released. The ledger remembers the key and original amount, so a late reply cannot turn this record into a new hold."
    },
    %{
      id: "voided",
      label: "Voided",
      description: "The hold has been cancelled and uses no capacity.",
      detail:
        "Cancellation before dispatch is local. After an authorized hold enters voiding, cancellation must be confirmed. Both paths retain the key and original amount in a voided record."
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

  def search_terms(query) do
    needle = query |> String.slice(0, 100) |> String.trim() |> String.downcase()

    Enum.filter(@terms, fn term ->
      text =
        Enum.join(
          Enum.map(~w(id term short detail example), &(term[&1] || "")) ++
            (term["aliases"] || []),
          " "
        )

      String.contains?(String.downcase(text), needle)
    end)
  end

  def claim_summary(claim) do
    sources =
      [claim["education_source_path"] | Enum.map(claim["provenance"] || [], & &1["path"])]
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.join("\n")

    Enum.join(
      [
        "#{claim["title"]} (#{claim["slug"]})",
        "Scenario: #{claim["scenario"]}",
        "Must happen: #{claim["must_happen"]}",
        "Wrong behavior: #{claim["wrong_behavior"]}",
        "Why another check may miss it: #{claim["why_others_miss"]}",
        "Scope: #{claim["does_not_cover"]}",
        "Registered claim. Registration does not establish formal acceptance.",
        "Sources:\n#{sources}"
      ],
      "\n\n"
    )
  end

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
