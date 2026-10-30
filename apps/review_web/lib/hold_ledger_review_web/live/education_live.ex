defmodule HoldLedgerReviewWeb.EducationLive do
  @moduledoc "An educational map of the repository; not a proof evaluator."
  use HoldLedgerReviewWeb, :live_view
  alias HoldLedgerReviewWeb.Education

  @page_names %{
    overview: "Overview",
    start: "Why holds?",
    system: "System explorer",
    guarantees: "Safety guarantees",
    atlas: "Verification atlas",
    profile: "Claim profile",
    proofs: "How proofs work",
    assurance: "Evidence & boundaries",
    repository: "Repository map",
    glossary: "Glossary"
  }

  @pipeline [
    %{
      number: "01",
      name: "Policy",
      tag: "Human intent",
      headline: "What should happen?",
      explanation:
        "The independent specification defines desired behavior. It is not derived from what the current implementation happens to do.",
      illustration:
        "A fresh request exactly equal to available capacity must be admitted if a hold slot is free."
    },
    %{
      number: "02",
      name: "Elixir code + law",
      tag: "Source statement",
      headline: "What code and contract are we checking?",
      explanation:
        "Ledger is implementation; Spec is an independent reference. A law defines when it applies (requires) and what it expects. A too-narrow requires clause can omit a policy-required input.",
      illustration: "PO-A2: requires Spec.request_eligible?(s, key, amount)."
    },
    %{
      number: "03",
      name: "Lynx",
      tag: "Translation",
      headline: "How does supported Elixir reach Lean?",
      explanation:
        "The checked pipeline translates supported Elixir constructs and laws into a formal representation. Toolchain support and exact source identity matter.",
      illustration: "The actual law source references the translated PO-A2 contract."
    },
    %{
      number: "04",
      name: "Lean",
      tag: "Theorem and proof",
      headline: "What statement has a proof?",
      explanation:
        "Lean checks a proof term for a precise theorem. Helper lemmas and tactics support the argument; they cannot independently decide the right business requirement.",
      illustration:
        "PO-A2 contains: exact Elixir.HoldLedger.ProofContracts.«po_a2/3» s key amount requires"
    },
    %{
      number: "05",
      name: "Receipt",
      tag: "Source-matched evidence",
      headline: "What did the checker actually accept?",
      explanation:
        "A completed verification receipt must match the exact sources, proof exports, allowed axioms and required checkers. This teaching page does not run or assume such a receipt exists.",
      illustration: "Registered in the catalog ≠ accepted by six independent checkers."
    }
  ]

  @journeys [
    %{
      title: "I'm new to the project",
      tag: "START HERE",
      description: "Meet the payment-hold problem without learning Lean first.",
      path: "/start",
      icon: "◉",
      steps: "3 short stops · problem → system → guarantees"
    },
    %{
      title: "I know Elixir, not Lean",
      tag: "CODE TO PROOF",
      description: "See exactly where the implementation, law, translation and theorem diverge.",
      path: "/proofs",
      icon: "⌘",
      steps: "Proof pipeline · source bridge"
    },
    %{
      title: "I review formal claims",
      tag: "CLAIM MAP",
      description: "Find any of the registered groups and see what evidence means.",
      path: "/atlas",
      icon: "◇",
      steps: "49 source-linked groups · 8 teaching families"
    },
    %{
      title: "I want to challenge a case",
      tag: "WORKBENCH",
      description: "Use the existing interactive case analysis and Claim Lens.",
      path: "/lab",
      icon: "↗",
      steps: "Real review tools · not a tutorial sandbox"
    }
  ]

  @impl true
  def mount(_params, _session, socket) do
    {claims, catalog_issue} =
      case Education.claims() do
        {:ok, value} -> {value, nil}
        {:error, reason} -> {[], inspect(reason)}
      end

    {:ok,
     assign(socket,
       page_title: "Hold Ledger · Learn",
       claims: claims,
       catalog_issue: catalog_issue,
       inventory: Education.inventory(claims),
       families: Education.families(),
       guarantees: Education.guarantees(),
       components: Education.components(),
       statuses: Education.statuses(),
       glossary: Education.glossary(),
       journeys: @journeys,
       pipeline: @pipeline,
       scenario_step: 1,
       selected_component: "ledger",
       selected_status: "unknown",
       selected_guarantee: "uncertainty",
       pipeline_step: "02",
       query: "",
       family: "all",
       kind: "all",
       priority: "all",
       filtered_claims: claims,
       term_query: "",
       filtered_terms: Education.glossary(),
       profile: nil
     )}
  end

  @impl true
  def handle_params(params, _url, socket) do
    action = socket.assigns.live_action

    profile =
      if action == :profile do
        Enum.find(socket.assigns.claims, &(&1["slug"] == params["slug"]))
      end

    socket =
      socket
      |> assign(:page_title, "Hold Ledger · " <> Map.fetch!(@page_names, action))
      |> assign(:profile, profile)

    socket =
      if action == :atlas do
        filters = %{
          "q" => params["q"] || "",
          "family" => params["family"] || "all",
          "kind" => params["kind"] || "all",
          "priority" => params["priority"] || "all"
        }

        filter_claims(socket, filters)
      else
        socket
      end

    socket =
      if action == :glossary and is_binary(params["q"]) do
        query = String.slice(params["q"], 0, 100)
        needle = String.downcase(String.trim(query))

        terms =
          Enum.filter(socket.assigns.glossary, fn term ->
            String.contains?(
              String.downcase(term["term"] <> " " <> term["short"] <> " " <> term["detail"]),
              needle
            )
          end)

        assign(socket, term_query: query, filtered_terms: terms)
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("scenario", %{"step" => value}, socket) when value in ~w(1 2 3 4) do
    {:noreply, assign(socket, :scenario_step, String.to_integer(value))}
  end

  def handle_event("component", %{"id" => id}, socket) do
    if Enum.any?(Education.components(), &(&1.id == id)) do
      {:noreply, assign(socket, :selected_component, id)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("status", %{"id" => id}, socket) do
    if Enum.any?(Education.statuses(), &(&1.id == id)) do
      {:noreply, assign(socket, :selected_status, id)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("guarantee", %{"id" => id}, socket) do
    if Enum.any?(Education.guarantees(), &(&1.id == id)) do
      {:noreply, assign(socket, :selected_guarantee, id)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("pipeline", %{"step" => id}, socket) do
    if Enum.any?(@pipeline, &(&1.number == id)) do
      {:noreply, assign(socket, :pipeline_step, id)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("filter_claims", filters, socket) when is_map(filters) do
    {:noreply, filter_claims(socket, filters)}
  end

  def handle_event("filter_terms", %{"q" => query}, socket) when is_binary(query) do
    q = String.downcase(String.trim(String.slice(query, 0, 100)))

    filtered =
      Enum.filter(socket.assigns.glossary, fn term ->
        String.contains?(
          String.downcase(term["term"] <> " " <> term["short"] <> " " <> term["detail"]),
          q
        )
      end)

    {:noreply, assign(socket, term_query: query, filtered_terms: filtered)}
  end

  def handle_event(_, _, socket), do: {:noreply, socket}

  defp filter_claims(socket, filters) do
    q = filters |> Map.get("q", "") |> to_string() |> String.slice(0, 100)
    family = Map.get(filters, "family", "all")
    kind = Map.get(filters, "kind", "all")
    priority = Map.get(filters, "priority", "all")
    needle = String.downcase(String.trim(q))

    selected =
      Enum.filter(socket.assigns.claims, fn claim ->
        (family == "all" or claim["family"] == family) and
          (kind == "all" or claim["kind"] == kind) and
          (priority == "all" or claim["priority"] == priority) and
          String.contains?(
            String.downcase(
              Enum.join([claim["title"], claim["slug"], claim["purpose"], claim["family"]], " ")
            ),
            needle
          )
      end)

    assign(socket,
      query: q,
      family: family,
      kind: kind,
      priority: priority,
      filtered_claims: selected
    )
  end

  defp active_component(assigns),
    do: Enum.find(assigns.components, &(&1.id == assigns.selected_component))

  defp active_status(assigns),
    do: Enum.find(assigns.statuses, &(&1.id == assigns.selected_status))

  defp active_guarantee(assigns),
    do: Enum.find(assigns.guarantees, &(&1.id == assigns.selected_guarantee))

  defp active_pipeline(assigns),
    do: Enum.find(assigns.pipeline, &(&1.number == assigns.pipeline_step))

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns,
        active_component: active_component(assigns),
        active_status: active_status(assigns),
        active_guarantee: active_guarantee(assigns),
        active_pipeline: active_pipeline(assigns)
      )

    ~H"""
    <Layouts.app flash={@flash}>
      <div class="edu-root" id="education-root">
        <%= if @catalog_issue do %>
          <div id="edu-catalog-unavailable" class="edu-caution" role="alert">
            The current claim catalog could not be read. Inventory and claim links are unavailable; no cached proof status is assumed.
          </div>
        <% end %>
        <%= case @live_action do %>
          <% :overview -> %>
            <.overview inventory={@inventory} journeys={@journeys} />
          <% :start -> %>
            <.start step={@scenario_step} />
          <% :system -> %>
            <.system
              components={@components}
              statuses={@statuses}
              component={@active_component}
              status={@active_status}
            />
          <% :guarantees -> %>
            <.guarantees guarantees={@guarantees} guarantee={@active_guarantee} />
          <% :atlas -> %>
            <.atlas
              claims={@filtered_claims}
              families={@families}
              all={@claims}
              query={@query}
              family={@family}
              kind={@kind}
              priority={@priority}
            />
          <% :profile -> %>
            <.profile claim={@profile} />
          <% :proofs -> %>
            <.proofs pipeline={@pipeline} active={@active_pipeline} />
          <% :assurance -> %>
            <.assurance />
          <% :repository -> %>
            <.repository components={@components} />
          <% :glossary -> %>
            <.glossary terms={@filtered_terms} query={@term_query} count={length(@glossary)} />
        <% end %>
        <footer class="edu-footer">
          <span>HOLD LEDGER / REPOSITORY COMPANION</span>
          <p>Curated explanations are navigation aids, not new formal verification evidence.</p>
          <a href="/assurance">Understand evidence boundaries →</a>
        </footer>
      </div>
    </Layouts.app>
    """
  end

  attr :eyebrow, :string, required: true
  attr :heading, :string, required: true
  attr :description, :string, required: true
  slot :extra

  defp intro(assigns) do
    ~H"""
    <div class="edu-page-intro">
      <div>
        <p class="edu-eyebrow">{@eyebrow}</p><h1>{@heading}</h1><p>{@description}</p>
      </div>
      {render_slot(@extra)}
    </div>
    """
  end

  attr :inventory, :map, required: true
  attr :journeys, :list, required: true

  defp overview(assigns) do
    ~H"""
    <section class="edu-home-hero" id="edu-overview">
      <div class="edu-home-hero-content">
        <p class="edu-eyebrow">THE REPOSITORY, EXPLAINED / 00</p>
        <h1>Understand the system.<br /><em>Then question the proof.</em></h1>
        <p class="edu-hero-sub">
          A payment authorization can remain live even when its reply disappears. This project models that risk, specifies safe behavior, and investigates how far formal evidence reaches.
        </p>
        <div class="edu-hero-actions">
          <a class="edu-primary-button" href="/start">Start with the story
          <span aria-hidden="true">↗</span></a>
          <a class="edu-ghost-button" href="/atlas">Explore all claims →</a>
        </div>
        <p class="edu-home-trust">
          <span class="edu-dot"></span>
          A verification <em>workbench</em>, not a payment service or proof-status dashboard.
        </p>
      </div>
      <div
        class="edu-hero-visual"
        aria-label="Illustration: a reserved hold remains on the ledger while processor confirmation is unknown"
      >
        <div class="edu-visual-top">
          <span>ONE ACCOUNT / MODELED EXAMPLE</span><span class="edu-visual-live">● UNKNOWN</span>
        </div>
        <div class="edu-visual-amount">100<span>¢</span></div>
        <p>Capacity reserved</p>
        <div class="edu-visual-track"><span></span></div>
        <div class="edu-visual-nodes">
          <span>Request received</span><span>Sent to processor</span><strong>Reply missing</strong>
        </div>
        <div class="edu-visual-foot">
          <span class="edu-pulse"></span> Silence does not release a hold.
        </div>
      </div>
    </section>
    <section class="edu-stat-strip" aria-label="Current registered verification inventory">
      <div><strong>{@inventory.total}</strong><span>Registered groups</span></div>
      <div><strong>{@inventory.elixir}</strong><span>Elixir / Lynx law groups</span></div>
      <div><strong>{@inventory.lean}</strong><span>Native Lean groups</span></div>
      <div class="edu-stat-note">
        <strong>Important distinction</strong><span>Registered ≠ freshly verified.
        <a href="/assurance">How to read evidence</a></span>
      </div>
    </section>
    <section class="edu-home-journeys">
      <div class="edu-section-head">
        <div>
          <p class="edu-eyebrow">PICK YOUR ENTRY POINT</p><h2>No prerequisites. Multiple ways in.</h2>
        </div><span>Every path leads to real source and tools.</span>
      </div>
      <div class="edu-journey-grid">
        <a :for={journey <- @journeys} class="edu-journey" href={journey.path}>
          <span class="edu-journey-top"><b>{journey.icon}</b><small>{journey.tag}</small></span>
          <h3>{journey.title}</h3><p>{journey.description}</p>
          <span class="edu-journey-bottom"><small>{journey.steps}</small><strong aria-hidden="true">↗</strong></span>
        </a>
      </div>
    </section>
    <section class="edu-home-map">
      <div class="edu-section-head">
        <div>
          <p class="edu-eyebrow">THE BIG PICTURE</p><h2>Follow the complete story.</h2>
        </div><span>Choose any destination; nothing is locked.</span>
      </div>
      <div class="edu-destination-grid">
        <a href="/start"><span>01 · CONTEXT</span><strong>Why payment holds?</strong><small>A missing reply and a double-reservation risk</small></a>
        <a href="/system"><span>02 · CODE</span><strong>Meet the system</strong><small>Ledger, Spec, runtime and processor boundaries</small></a>
        <a href="/guarantees"><span>03 · POLICY</span><strong>Safety guarantees</strong><small>Six things the requirements care about</small></a>
        <a href="/atlas"><span>04 · CATALOG</span><strong>49 claims, one map</strong><small>Eight editorial families, full source links</small></a>
        <a href="/proofs"><span>05 · METHOD</span><strong>How proofs work</strong><small>From independent policy to checker evidence</small></a>
        <a href="/assurance"><span>06 · TRUST</span><strong>Evidence & assumptions</strong><small>What a proof establishes — and cannot</small></a>
        <a href="/repository"><span>07 · SOURCE</span><strong>Find the code</strong><small>Purpose-based repository navigation</small></a>
        <a href="/glossary"><span>08 · REFERENCE</span><strong>Glossary</strong><small>Plain-English explanations of 53 terms</small></a>
      </div>
    </section>
    <section class="edu-next-step">
      <div>
        <p class="edu-eyebrow">ALREADY KNOW THE CONTEXT?</p><h2>Open the working tools.</h2><p>
          Case Lab runs real source-bound case exploration. Claim Lens asks you to judge a curated semantic challenge before showing its pointwise interpretation.
        </p>
      </div><div><a href="/lab">Open Case Lab →</a><a href="/lens/po_a2">Open Claim Lens →</a></div>
    </section>
    """
  end

  attr :step, :integer, required: true

  defp start(assigns) do
    steps = [
      %{
        label: "Request",
        title: "A new request needs 100¢.",
        text:
          "An account has a 100-cent authorization limit. The fresh request fits exactly, so the modeled ledger reserves the full amount and a slot.",
        state: "RESERVED",
        result: "Accepted locally"
      },
      %{
        label: "Dispatch",
        title: "The authorization is sent.",
        text:
          "The runtime may send the authorization intent to the external processor. The ledger cannot yet infer what the processor will decide.",
        state: "SENT",
        result: "Outcome pending"
      },
      %{
        label: "Timeout",
        title: "The reply never arrives.",
        text:
          "A timeout is not evidence of a decline. The authorization might still be live remotely, so the amount and slot stay reserved.",
        state: "UNKNOWN",
        result: "Keep capacity held"
      },
      %{
        label: "Second request",
        title: "Another 100¢ cannot fit.",
        text:
          "If we released capacity on silence, a second request could overcommit the account. Retaining the unknown hold prevents that modeled risk.",
        state: "UNKNOWN",
        result: "Insufficient available capacity"
      }
    ]

    assigns = assign(assigns, selected: Enum.at(steps, assigns.step - 1), steps: steps)

    ~H"""
    <.intro
      eyebrow="01 / THE PROBLEM"
      heading="A missing reply can still cost money."
      description="Before looking at Lean or the proof catalog, understand the one safety mistake this project refuses to make."
    />
    <div class="edu-two-column edu-story-grid" id="edu-story">
      <div class="edu-story-console">
        <div class="edu-console-top">
          <span>ILLUSTRATIVE HOLD WALKTHROUGH</span><span>STEP {@step} / 4</span>
        </div>
        <div class="edu-story-progress"><span style={"width: #{@step * 25}%"}></span></div>
        <div class="edu-story-steps" role="group" aria-label="Scenario step">
          <button
            :for={{step, index} <- Enum.with_index(@steps, 1)}
            type="button"
            phx-click="scenario"
            phx-value-step={index}
            class={if(@step == index, do: "active", else: "")}
            aria-pressed={to_string(@step == index)}
          >{index} <span>{step.label}</span></button>
        </div>
        <div class="edu-story-money">
          <span>Available to new holds</span><strong>0<small>¢ of 100¢</small></strong><div class="edu-story-bar">
            <i></i>
          </div>
        </div>
        <div class="edu-story-event">
          <span class="edu-pill">{@selected.state}</span><h2>{@selected.title}</h2><p>
            {@selected.text}
          </p><div class="edu-story-result">
            <span>MODELED RESULT</span><strong>{@selected.result}</strong>
          </div>
        </div>
        <div class="edu-story-controls">
          <button type="button" phx-click="scenario" phx-value-step={@step - 1} disabled={@step == 1}>← Previous</button><button
            type="button"
            phx-click="scenario"
            phx-value-step={@step + 1}
            disabled={@step == 4}
          >Next step →</button>
        </div>
        <p class="edu-micro-note">
          Teaching scenario from documented model behavior, not an executed processor transaction or new proof run.
        </p>
      </div>
      <div class="edu-explainer-column">
        <div class="edu-note-card">
          <span class="edu-eyebrow">THE ENGINEERING PROBLEM</span><h2>A timeout is not a decline.</h2><p>
            The remote authorization might have succeeded while its reply was lost. Reusing the capacity would be unsafe.
          </p><a href="/system">See the seven hold states →</a>
        </div>
        <div class="edu-note-card">
          <span class="edu-eyebrow">THE VERIFICATION PROBLEM</span><h2>
            Correct totals are not enough.
          </h2><p>
            The code must also respect who owns capacity, what terminal evidence exists, and which input sequences the claims cover.
          </p><a href="/guarantees">Understand the requirements →</a>
        </div>
        <div class="edu-small-detail">
          <strong>One important limit</strong><p>
            This repository models a single-account authorization-hold system. It does not show that a real processor honors every assumption.
          </p>
        </div>
      </div>
    </div>
    <.next_links
      one="/system"
      one_title="Explore the actual system"
      two="/guarantees"
      two_title="What needs to stay true?"
    />
    """
  end

  attr :components, :list, required: true
  attr :statuses, :list, required: true
  attr :component, :map, required: true
  attr :status, :map, required: true

  defp system(assigns) do
    ~H"""
    <.intro
      eyebrow="02 / THE SYSTEM"
      heading="The code, the model, and the outside world."
      description="The web workbench is a companion to a real Elixir repository. It is not the ledger service itself."
    />
    <div class="edu-section-head">
      <div>
        <p class="edu-eyebrow">ARCHITECTURE / PICK A COMPONENT</p><h2>
          Follow the request across boundaries.
        </h2>
      </div><span>Click any layer for its role and source location.</span>
    </div>
    <div class="edu-architecture">
      <div class="edu-arch-cards" role="group" aria-label="Architecture layers">
        <button
          :for={node <- @components}
          type="button"
          phx-click="component"
          phx-value-id={node.id}
          class={["edu-arch-node", @component.id == node.id && "active"]}
          aria-pressed={to_string(@component.id == node.id)}
        ><span>{node.title}</span><small>{node.role}</small><b aria-hidden="true">↗</b></button>
      </div>
      <div class="edu-arch-explainer" id="edu-component-detail">
        <span class="edu-eyebrow">SELECTED LAYER</span><h3>{@component.title}</h3><p>
          {@component.explanation}
        </p><div class="edu-file-label">
          <span>REPOSITORY SOURCE</span><code>{@component.path}</code>
        </div><a href={@component.link}>Follow this concept →</a>
      </div>
    </div>
    <section class="edu-status-section">
      <div class="edu-section-head">
        <div>
          <p class="edu-eyebrow">THE STATE MACHINE</p><h2>
            Seven hold states, each with a different meaning.
          </h2>
        </div><span>Status ≠ external truth.</span>
      </div>
      <div class="edu-status-grid" role="group" aria-label="Hold state explanations">
        <button
          :for={status <- @statuses}
          type="button"
          phx-click="status"
          phx-value-id={status.id}
          class={["edu-state-chip", @status.id == status.id && "active"]}
          aria-pressed={to_string(@status.id == status.id)}
        ><span class="edu-state-dot"></span>{status.label}</button>
      </div>
      <div class="edu-status-detail" id="edu-status-detail">
        <span>SELECTED HOLD STATE</span><h3>{@status.label}</h3><strong>{@status.description}</strong><p>
          {@status.detail}
        </p><a href="/atlas?family=Identity+%26+lifecycle">Find lifecycle claims →</a>
      </div>
      <p class="edu-micro-note">
        Transitions are constrained by event and prior state; this selection is a status glossary, not an assertion that every state can transition directly to every other state.
      </p>
    </section>
    <.next_links
      one="/guarantees"
      one_title="Read the safety guarantees"
      two="/repository"
      two_title="Locate the source files"
    />
    """
  end

  attr :guarantees, :list, required: true
  attr :guarantee, :map, required: true

  defp guarantees(assigns) do
    ~H"""
    <.intro
      eyebrow="03 / REQUIREMENTS"
      heading="Six questions the policy must answer."
      description="These teaching themes summarize the independent specification. They are not extra verified claims or a replacement for the governing policy text."
    />
    <div class="edu-guarantee-layout">
      <div class="edu-guarantee-picker" role="group" aria-label="Select a guarantee">
        <button
          :for={g <- @guarantees}
          type="button"
          phx-click="guarantee"
          phx-value-id={g.id}
          class={["edu-guarantee-choice", @guarantee.id == g.id && "active"]}
          aria-pressed={to_string(@guarantee.id == g.id)}
        ><span>{g.number}</span><strong>{g.title}</strong><span aria-hidden="true">→</span></button>
      </div>
      <div class="edu-guarantee-card">
        <p class="edu-eyebrow">POLICY PERSPECTIVE / {@guarantee.number}</p><h2>{@guarantee.title}</h2><p class="edu-guarantee-nutshell">
          {@guarantee.nutshell}
        </p><div class="edu-contrast-pair">
          <div>
            <span>EXPECTED / SAFE</span><p>{@guarantee.safe}</p>
          </div><div>
            <span>NEAR-MISS / UNSAFE</span><p>{@guarantee.unsafe}</p>
          </div>
        </div><h3>Related registered claims</h3><div class="edu-related-links">
          <a :for={slug <- @guarantee.slugs} href={"/atlas/" <> slug}><code>{slug}</code><span aria-hidden="true">↗</span></a>
        </div><p class="edu-micro-note">
          Policy authority: <code>guides/specification.md</code>. Read the actual preconditions and postconditions before concluding a particular obligation covers this example.
        </p>
      </div>
    </div>
    <.next_links
      one="/atlas"
      one_title="How all 49 groups fit together"
      two="/lens/po_a2"
      two_title="Challenge an exact-fit claim"
    />
    """
  end

  attr :claims, :list, required: true
  attr :all, :list, required: true
  attr :families, :list, required: true
  attr :query, :string, required: true
  attr :family, :string, required: true
  attr :kind, :string, required: true
  attr :priority, :string, required: true

  defp atlas(assigns) do
    ~H"""
    <.intro
      eyebrow="04 / VERIFICATION ATLAS"
      heading="49 groups. Not 49 unrelated mysteries."
      description="All catalog entries remain intact. These eight families are an editorial teaching map, not a verified theorem dependency graph."
    />
    <section class="edu-origin-story" id="edu-origin-story">
      <div class="edu-section-head">
        <div>
          <p class="edu-eyebrow">HOW THE CLAIMS FIT TOGETHER</p><h2>
            From pure bookkeeping to modeled recovery.
          </h2>
        </div><span>Conceptual reading progression, not an audited chronology or proof-dependency graph.</span>
      </div>
      <div class="edu-origin-steps">
        <a href="/atlas?family=Foundations"><span>01</span><strong>Build the arithmetic</strong><small>Lookup, identity, totals and valid states</small></a>
        <a href="/atlas?family=Identity+%26+lifecycle"><span>02</span><strong>Protect the lifecycle</strong><small>Timeouts, voids and terminal states</small></a>
        <a href="/atlas?family=Attempts"><span>03</span><strong>Track runtime attempts</strong><small>Slots, retirement and persistence</small></a>
        <a href="/atlas?family=Processor+%26+exposure"><span>04</span><strong>Model remote exposure</strong><small>Fencing and what might still be live</small></a>
        <a href="/atlas?family=Composite+%26+recovery"><span>05</span><strong>Reason about recovery</strong><small>Pending void work and committed replay</small></a>
      </div>
    </section>
    <div class="edu-section-head">
      <div>
        <p class="edu-eyebrow">THE EIGHT TEACHING FAMILIES</p><h2>Choose a safety concern.</h2>
      </div><span>Every registered slug is assigned exactly once.</span>
    </div>
    <div class="edu-family-grid" id="edu-families">
      <a
        :for={family <- @families}
        href={"/atlas?family=" <> URI.encode_www_form(family.id)}
        class={["edu-family-tile", @family == family.id && "active"]}
      ><span>{family.number} / {length(Education.by_family(@all, family.id))} GROUPS</span><h3>
        {family.id}
      </h3><p>{family.description}</p></a>
    </div>
    <section class="edu-atlas-browser" id="edu-atlas-browser">
      <div class="edu-section-head">
        <div>
          <p class="edu-eyebrow">CATALOG / SOURCE-DERIVED INVENTORY</p><h2>
            Find a precise obligation.
          </h2>
        </div><span>{length(@claims)} matching / {length(@all)} registered</span>
      </div>
      <form id="edu-atlas-filters" phx-change="filter_claims" class="edu-atlas-filters">
        <label>Search name, slug, or purpose<input
          type="search"
          name="q"
          value={@query}
          placeholder="Try timeout, capacity, history…"
          phx-debounce="200"
        /></label><label>Family<select name="family"><option value="all" selected={@family == "all"}>
          All families
        </option><option :for={family <- @families} value={family.id} selected={@family == family.id}>
          {family.id}
        </option></select></label><label>Source type<select name="kind"><option
          value="all"
          selected={@kind == "all"}
        >
          Both source types
        </option><option value="elixir_law" selected={@kind == "elixir_law"}>
          Elixir / Lynx law
        </option><option value="native_lean" selected={@kind == "native_lean"}>
          Native Lean group
        </option></select></label><label>Priority<select name="priority"><option
          value="all"
          selected={@priority == "all"}
        >
          All priorities
        </option><option value="L" selected={@priority == "L"}>L / foundations</option><option
          value="P0"
          selected={@priority == "P0"}
        >
          P0
        </option><option value="P1" selected={@priority == "P1"}>P1</option></select></label>
      </form>
      <p class="edu-micro-note">
        Priority labels are taken from the repository catalog. A native Lean group describes Lean declarations, not an Elixir <code>requires</code>/<code>expects</code>
        contract.
      </p>
      <div class="edu-atlas-results" id="edu-atlas-results">
        <a :for={claim <- @claims} href={"/atlas/" <> claim["slug"]} class="edu-claim-row"><span class="edu-claim-identity"><code>{claim[
          "id"
        ]}</code><small>{claim["priority"]}</small></span><span><strong>{claim["title"]}</strong><small>{claim[
          "purpose"
        ]}</small></span><span class="edu-claim-tags"><b>{claim["family"]}</b><small>{if claim["kind"] ==
                                                                                           "native_lean",
                                                                                         do:
                                                                                           "Native Lean",
                                                                                         else:
                                                                                           "Elixir law"}</small></span><span
          class="edu-row-arrow"
          aria-hidden="true"
        >↗</span></a>
      </div>
      <div :if={@claims == []} class="edu-empty">
        No matching claims. Try clearing a filter; an empty search is not a failed proof result.
      </div>
    </section>
    <.next_links
      one="/proofs"
      one_title="Understand how proofs work"
      two="/assurance"
      two_title="Read evidence limits"
    />
    """
  end

  attr :claim, :map, default: nil

  defp profile(assigns) do
    ~H"""
    <%= if @claim do %>
      <div class="edu-profile-breadcrumb">
        <a href="/atlas">← Verification atlas</a><span>/ {@claim["family"]}</span>
      </div>
      <section class="edu-profile-hero" id="edu-claim-profile">
        <p class="edu-eyebrow">CLAIM PROFILE / {@claim["id"]}</p><h1>{@claim["title"]}</h1><p class="edu-profile-description">
          {@claim["purpose"]}
        </p><div class="edu-profile-badges">
          <span>{@claim["family"]}</span><span>{@claim["priority"]} priority</span><span>{if @claim[
                                                                                               "kind"
                                                                                             ] ==
                                                                                               "native_lean",
                                                                                             do:
                                                                                               "Native Lean group",
                                                                                             else:
                                                                                               "Elixir / Lynx law"}</span><span>Registered · proof status not implied</span>
        </div>
      </section>
      <div class="edu-profile-grid">
        <section class="edu-profile-panel">
          <p class="edu-eyebrow">WHY THIS EXISTS</p><h2>A small part of a larger safety argument.</h2><p>
            {@claim["risk"]}
          </p><p>
            The catalog describes this group's purpose as: <strong>{@claim["purpose"]}</strong>
          </p><p class="edu-micro-note">
            This explanation is a reading aid. Exact semantics live in the source declaration and its assumptions.
          </p>
        </section><section class="edu-profile-panel">
          <p class="edu-eyebrow">SOURCE IDENTITY</p><h2>Where the actual statement lives.</h2><dl>
            <dt>Registered slug</dt><dd><code>{@claim["slug"]}</code></dd><dt>Claim group</dt><dd>
              <code>{@claim["id"]}</code>
            </dd><dt>Source</dt><dd>
              <code>{@claim["education_source_path"] || @claim["module"] ||
                "Refer to the registered source"}</code>
            </dd><dt>Target</dt><dd>
              <code>{@claim["target"] || Enum.join(@claim["theorems"] || [], ", ")}</code>
            </dd>
          </dl>
          <%= if @claim["kind"] == "native_lean" do %>
            <p class="edu-micro-note">
              Native Lean model/history statement — no Elixir requires/ expects counterpart is asserted.
            </p>
          <% else %>
            <p class="edu-micro-note">
              Open the source-bound Case Lab reading to inspect the actual law and any supported proof source links.
            </p>
          <% end %>
        </section>
      </div>
      <div class="edu-profile-bridge">
        <div>
          <p class="edu-eyebrow">WHAT THIS DOES NOT SETTLE</p><h2>
            Registration is not formal acceptance.
          </h2><p>
            Neither this profile nor its conceptual group certifies that all required checkers accepted current source, that independent policy is adequate, or that a real processor obeys its trust contract. Source-reading links are not necessarily kernel dependencies.
          </p>
        </div><div>
          <a href={"/claims/" <> @claim["slug"]}>Inspect in Case Lab →</a><a
            :if={@claim["slug"] in ~w(po_a2 po_exposure_retain)}
            href={"/lens/" <> @claim["slug"]}
          >Try guided Claim Lens →</a><a href="/assurance">Learn evidence levels →</a>
        </div>
      </div>
    <% else %>
      <section id="edu-unknown-claim" class="edu-empty">
        <h1>That claim isn't in the current catalog.</h1><p>
          No proof result is inferred for an unknown slug.
        </p><a href="/atlas">Return to the complete atlas →</a>
      </section>
    <% end %>
    """
  end

  attr :pipeline, :list, required: true
  attr :active, :map, required: true

  defp proofs(assigns) do
    ~H"""
    <.intro
      eyebrow="05 / HOW PROOFS WORK"
      heading="From a human requirement to a checked statement."
      description="Five layers that are related but never interchangeable. Select a step to see the boundary and a real PO-A2 source anchor."
    />
    <div class="edu-pipeline" role="group" aria-label="Verification pipeline steps">
      <button
        :for={p <- @pipeline}
        type="button"
        phx-click="pipeline"
        phx-value-step={p.number}
        aria-pressed={to_string(@active.number == p.number)}
        class={["edu-pipeline-step", @active.number == p.number && "active"]}
      ><span>{p.number} / {p.tag}</span><strong>{p.name}</strong></button>
    </div>
    <section id="edu-proof-detail" class="edu-pipeline-detail">
      <div>
        <p class="edu-eyebrow">SELECTED LAYER / {@active.number}</p><h2>{@active.headline}</h2><p>
          {@active.explanation}
        </p><div class="edu-proof-anchor">
          <span>WORKED EXAMPLE / PO-A2</span><code>{@active.illustration}</code>
        </div>
      </div><aside>
        <h3>What you are seeing</h3><p>
          The actual Elixir law lives at <code>test/laws/po_a2_test.exs</code>. The human requirement lives in <code>guides/specification.md</code>.
        </p><a href="/atlas/po_a2">Open PO-A2 claim profile →</a><a href="/claims/po_a2">Open its source-bound Case Lab →</a>
      </aside>
    </section>
    <section class="edu-code-reading">
      <div class="edu-section-head">
        <div>
          <p class="edu-eyebrow">READING THE CONTRACT</p><h2>
            The smallest piece of real code worth understanding.
          </h2>
        </div><a href="/glossary?q=requires">Open the glossary →</a>
      </div><div class="edu-code-grid">
        <div>
          <span>01 / ELIXIR LAW SOURCE EXCERPT</span><pre><code>law(po_a2(s, key, amount),
    requires: Spec.request_eligible?(s, key, amount),
    expects: Ledger.request(s, key, amount) == ...)</code></pre><p>
            Source excerpt shortened with an ellipsis. The actual <code>expects</code>
            also fixes exact counters and matches <code>Spec.expected_step</code>.
          </p>
        </div><div>
          <span>02 / LEAN PROOF REFERENCE IN THE LAW</span><pre><code>exact Elixir.HoldLedger.ProofContracts.
    «po_a2/3» s key amount requires</code></pre><p>
            This is a source snippet, not a fresh Lean elaboration or acceptance receipt. The actual theorem/checks require source-bound tooling.
          </p>
        </div>
      </div>
    </section>
    <div class="edu-note-card edu-proof-concepts">
      <p class="edu-eyebrow">LEAN WITHOUT THE MYSTIQUE</p><h2>Four words you'll see again.</h2><div>
        <a href="/glossary?q=induction"><strong>Induction</strong><span>From a base to all finite modeled histories.</span></a><a href="/glossary?q=omega"><strong>omega</strong><span>Arithmetic tactic, not a new business rule.</span></a><a href="/glossary?q=axiom"><strong>Axiom</strong><span>A trust assumption the development relies on.</span></a><a href="/glossary?q=counterexample"><strong>Counterexample</strong><span>A concrete contradiction, not a failed tactic.</span></a>
      </div>
    </div>
    <.next_links
      one="/atlas"
      one_title="Browse the actual statements"
      two="/assurance"
      two_title="What counts as proof evidence?"
    />
    """
  end

  defp assurance(assigns) do
    ~H"""
    <.intro
      eyebrow="06 / EVIDENCE & ASSUMPTIONS"
      heading="A green proof can't answer every question."
      description="The workbench has several kinds of evidence. This page explains what each can establish, and where the formal model stops."
    />
    <div class="edu-assurance-note">
      <div>
        <p class="edu-eyebrow">CURRENT CHECKOUT / CAREFUL WORDING</p><h2>
          No formal-acceptance percentage is asserted here.
        </h2><p>
          The Atlas counts registered groups from the source catalog. A matching report, complete checker acceptance, and source hashes must be inspected separately before describing any group as formally accepted.
        </p>
      </div><a href="/lab">Inspect actual report surfaces →</a>
    </div>
    <div class="edu-section-head">
      <div>
        <p class="edu-eyebrow">THE EVIDENCE LADDER</p><h2>
          Seven different statements, seven different strengths.
        </h2>
      </div>
    </div>
    <div class="edu-evidence-grid">
      <div>
        <span>01 / POLICY</span><h3>Human requirement</h3><p>
          States intended behavior. It cannot prove what the code or processor does.
        </p>
      </div>
      <div>
        <span>02 / EXAMPLE</span><h3>Concrete or curated witness</h3><p>
          Illustrates one input/trace. It does not universally establish a claim.
        </p>
      </div>
      <div>
        <span>03 / POINTWISE</span><h3>Elixir claim evaluation</h3><p>
          Checks one source-bound candidate input and output; may be not applicable or incomplete.
        </p>
      </div>
      <div>
        <span>04 / SOURCE</span><h3>Reviewed Lean passage</h3><p>
          Useful source navigation. A link is not a kernel proof-dependency record.
        </p>
      </div>
      <div>
        <span>05 / DEVELOPMENT</span><h3>Focused elaboration</h3><p>
          Limited tool run evidence is not necessarily the full formal acceptance gate.
        </p>
      </div>
      <div>
        <span>06 / FORMAL RECEIPT</span><h3>Full checked artifact</h3><p>
          Requires matching sources, exports, axioms and all specified checkers; not inferred here.
        </p>
      </div>
      <div>
        <span>07 / WORLD</span><h3>External trust assumptions</h3><p>
          Real processor fencing, delivery and durable storage need separate verification.
        </p>
      </div>
    </div>
    <section class="edu-trust-boundary">
      <div>
        <p class="edu-eyebrow">MODEL BOUNDARY</p><h2>
          Requested remote work is not completed remote work.
        </h2><p>
          Pure transitions describe effect intentions. Journal and processor behavior introduce other trust boundaries.
        </p>
      </div><div class="edu-trust-flow">
        <span>LEDGER MODEL</span><b aria-hidden="true">→</b><span>REQUESTED EFFECT</span><b aria-hidden="true">⇢</b><span>REAL PROCESSOR</span>
      </div><ul>
        <li>Terminal fencing: Can late authorization resurrect a voided hold?</li><li>
          Processor truthfulness: Can an acknowledgment be confused with an approval?
        </li><li>Durable journal: What actually survived the crash?</li><li>
          Translation and source identity: Which exact statement and files were checked?
        </li>
      </ul>
    </section>
    <.next_links
      one="/lens/po_exposure_retain"
      one_title="Challenge a retention assumption"
      two="/repository"
      two_title="Find the evidence-related files"
    />
    """
  end

  attr :components, :list, required: true

  defp repository(assigns) do
    ~H"""
    <.intro
      eyebrow="07 / REPOSITORY MAP"
      heading="Where does each answer live?"
      description="A purpose-based map of the checkout. These are file locations and reading routes, not live hyperlinks to a remote repository revision."
    />
    <div class="edu-repository-map">
      <div :for={c <- @components} class="edu-repo-item">
        <span class="edu-repo-index">{c.id}</span><div>
          <h2>{c.title}</h2><p>{c.explanation}</p><code>{c.path}</code>
        </div><a href={c.link}>Explore →</a>
      </div>
      <div class="edu-repo-item">
        <span class="edu-repo-index">proof</span><div>
          <h2>Lean support library</h2><p>
            Reusable definitions, mathematical models and helper statements used by the proof pipeline.
          </p><code>test/support/lean/</code>
        </div><a href="/proofs">Understand →</a>
      </div>
      <div class="edu-repo-item">
        <span class="edu-repo-index">checks</span><div>
          <h2>Verification registry & evidence rules</h2><p>
            Obligations are registered here. That is distinct from executing complete source-bound verification checks.
          </p><code>verification/laws.json · verification/obligations.json</code>
        </div><a href="/atlas">Browse →</a>
      </div>
      <div class="edu-repo-item">
        <span class="edu-repo-index">tests</span><div>
          <h2>Tests and deliberate mutants</h2><p>
            Examples, property checks, and intentional broken implementations provide concrete challenges.
          </p><code>test/ · mutants/</code>
        </div><a href="/guarantees">Learn why →</a>
      </div>
      <div class="edu-repo-item">
        <span class="edu-repo-index">app</span><div>
          <h2>Interactive review companion</h2><p>
            The Phoenix interface you are using. It does not replace the actual Ledger, Spec or Lean checker.
          </p><code>apps/review_web/</code>
        </div><a href="/lab">Open →</a>
      </div>
    </div>
    <div class="edu-repo-follow">
      <p class="edu-eyebrow">FOLLOW ONE CONCEPT THROUGH THE REPO</p><h2>
        Why does an unknown hold keep its money?
      </h2><div>
        <a href="/glossary?q=unknown">01. Learn the state</a><a href="/guarantees">02. Read the policy</a><a href="/atlas/po_b2">03. Find the claim</a><a href="/claims/po_b2">04. Inspect the source</a>
      </div>
    </div>
    <.next_links
      one="/glossary"
      one_title="Look up terminology"
      two="/lab"
      two_title="Use the review tools"
    />
    """
  end

  attr :terms, :list, required: true
  attr :query, :string, required: true
  attr :count, :integer, required: true

  defp glossary(assigns) do
    ~H"""
    <.intro
      eyebrow="08 / PLAIN-LANGUAGE REFERENCE"
      heading="No unexplained vocabulary."
      description="Search the repository's key domain, code and formal-verification terms. The same definitions power help on the real workbench."
    />
    <form id="edu-glossary-filter" phx-change="filter_terms" class="edu-search">
      <label for="edu-term-query">Find a term or meaning</label><input
        id="edu-term-query"
        type="search"
        name="q"
        value={@query}
        placeholder="Try axiom, voiding, requires, processor…"
        phx-debounce="180"
      /><span>{length(@terms)} / {@count} terms</span>
    </form>
    <div class="edu-glossary-grid" id="edu-glossary-results">
      <article :for={term <- @terms} id={"term-" <> term["id"]} class="edu-term-card">
        <h2>{term["term"]}</h2><strong>{term["short"]}</strong><p>{term["detail"]}</p><div class="edu-term-example">
          <span>IN THIS REPOSITORY</span><p>{term["example"]}</p>
        </div><a href={term["link"]}>Explore this in context →</a>
      </article>
    </div><p :if={@terms == []} class="edu-empty">No matching terms. Try a shorter search.</p>
    <.next_links
      one="/atlas"
      one_title="Find a claim using the vocabulary"
      two="/proofs"
      two_title="See the proof pipeline"
    />
    """
  end

  attr :one, :string, required: true
  attr :one_title, :string, required: true
  attr :two, :string, required: true
  attr :two_title, :string, required: true

  defp next_links(assigns) do
    ~H"""
    <nav class="edu-next-links" aria-label="Recommended next pages">
      <p>KEEP EXPLORING</p><a href={@one}>{@one_title} <span aria-hidden="true">↗</span></a><a href={
        @two
      }>{@two_title} <span aria-hidden="true">↗</span></a>
    </nav>
    """
  end
end
