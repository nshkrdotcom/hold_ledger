defmodule HoldLedgerReviewWeb.EducationLive do
  @moduledoc "Learning pages using existing model execution and source readers."
  use HoldLedgerReviewWeb, :live_view
  import HoldLedgerReviewWeb.ScrubberComponents, only: [capacity_view: 1]
  alias HoldLedgerReviewWeb.{Education, Learning, ReviewCopy}

  @page_names %{
    overview: "Explore",
    start: "Follow a payment hold",
    how_it_fits: "How the pieces fit",
    examples: "Learn from deliberate faults",
    translation: "Elixir to Lean with Lynx",
    system: "The hold system",
    guarantees: "Payment-hold requirements",
    atlas: "Find a claim",
    profile: "Read a claim",
    proofs: "Read the statement",
    assurance: "Evidence and assumptions",
    repository: "Find the source",
    glossary: "Glossary"
  }

  @pipeline [
    %{
      number: "01",
      name: "Policy",
      tag: "Required behavior",
      headline: "Does the policy cover the case?",
      explanation:
        "A fresh request for exactly the available amount must be admitted when a slot is free. Review the requirement before inspecting the claim.",
      risk: "A missing or contradictory policy case leaves the intended behavior undecided.",
      source: "guides/specification.md"
    },
    %{
      number: "02",
      name: "Claim",
      tag: "Input and output",
      headline: "Does the statement cover an exact fit?",
      explanation:
        "PO-A2 calls Spec.request_eligible? in requires. Follow that predicate: its amount comparison uses <=. The expects clause requires admission and the exact new state.",
      risk:
        "Changing the precondition to exclude exact fit could leave a true claim that misses this requirement.",
      source: "test/laws/po_a2_test.exs · lib/hold_ledger/spec.ex"
    },
    %{
      number: "03",
      name: "Translation",
      tag: "Elixir to Lean",
      headline: "Is the source represented faithfully?",
      explanation:
        "Lynx translates the supported Elixir code and laws for formal checking. The supported language subset and the exact source version define what reaches Lean.",
      risk:
        "A translation gap or a mismatched source version breaks the connection to the code being reviewed.",
      source: "guides/verification.md"
    },
    %{
      number: "04",
      name: "Proof",
      tag: "The stated theorem",
      headline: "What does the proof establish?",
      explanation:
        "Lean checks a proof of the theorem it is given. That includes the theorem's domain and assumptions. Read those before deciding whether the proof answers the policy question.",
      risk:
        "A proof can establish a statement whose premises are too narrow or whose conclusion asks too little.",
      source: "test/laws/po_a2_test.exs"
    },
    %{
      number: "05",
      name: "Receipt",
      tag: "Checked source",
      headline: "Does the evidence match this source?",
      explanation:
        "A full acceptance report must account for the required checkers, exported statements, allowed axioms and source identity. Read the report together with the files it records.",
      risk:
        "A receipt for different source bytes does not establish acceptance of the current claim.",
      source: "guides/verification.md · verification/laws.json"
    }
  ]

  @journeys [
    %{
      title: "I'm new to formal verification",
      tag: "Start with one payment hold",
      description:
        "Follow a 100¢ request through dispatch and timeout. See why the amount stays held when the reply is missing.",
      path: "/start",
      number: "01",
      destination: "Payment-hold walkthrough"
    },
    %{
      title: "I know Elixir",
      tag: "Follow familiar code into Lean",
      description:
        "Read an Elixir law, follow its translation and inspect the supplied theorem. See which part Lynx provides and which part the proof establishes.",
      path: "/translation",
      number: "02",
      destination: "Elixir → Lynx → Lean"
    },
    %{
      title: "I review proofs or agent changes",
      tag: "Check meaning and evidence",
      description:
        "Follow policy, claims and evidence across the repository. Then practice spotting a change that leaves out a required case.",
      path: "/how-it-fits",
      number: "03",
      destination: "Reading map and review practice"
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
       scenario_step: 0,
       story_moments: nil,
       story_issue: nil,
       mutations: Learning.mutations(),
       selected_mutation: nil,
       mutation_issue: nil,
       translation: nil,
       translation_issue: nil,
       source_counts: Learning.source_counts(),
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

    {:noreply, page_params(socket, action, params)}
  end

  defp page_params(socket, :atlas, params) do
    filter_claims(socket, %{
      "q" => params["q"] || "",
      "family" => params["family"] || "all",
      "kind" => params["kind"] || "all",
      "priority" => params["priority"] || "all"
    })
  end

  defp page_params(socket, :glossary, params) do
    query = if is_binary(params["q"]), do: String.slice(params["q"], 0, 100), else: ""
    assign(socket, term_query: query, filtered_terms: Education.search_terms(query))
  end

  defp page_params(socket, page, params) when page in [:overview, :start] do
    value = params["moment"]
    index = if value in ~w(0 1 2 3 4), do: String.to_integer(value), else: 0
    socket |> load_story() |> assign(:scenario_step, index)
  end

  defp page_params(socket, :examples, params) do
    case Learning.mutation(params["example"] || "M4") do
      {:ok, selected} -> assign(socket, selected_mutation: selected, mutation_issue: nil)
      {:error, _} -> assign(socket, selected_mutation: nil, mutation_issue: :unknown_mutation)
    end
  end

  defp page_params(socket, :translation, _params) do
    case Learning.translation() do
      {:ok, source} -> assign(socket, translation: source, translation_issue: nil)
      {:error, reason} -> assign(socket, translation: nil, translation_issue: reason)
    end
  end

  defp page_params(socket, _action, _params), do: socket

  @impl true
  def handle_event("scenario", %{"step" => value}, socket) when value in ~w(0 1 2 3 4) do
    {:noreply, assign(socket, :scenario_step, String.to_integer(value))}
  end

  def handle_event("reload_story", _, socket),
    do: {:noreply, socket |> assign(story_moments: nil) |> load_story()}

  def handle_event("open_story", _, socket) do
    if is_list(socket.assigns.story_moments) do
      case Learning.open_moment(socket.assigns.scenario_step) do
        {:ok, %{doc: doc, slug: slug}} ->
          {:noreply, push_navigate(socket, to: ~p"/claims/#{slug}/#{doc["id"]}")}

        {:error, _} ->
          {:noreply,
           put_flash(
             socket,
             :error,
             "Case Lab could not open this moment. The walkthrough is still here; you can try again."
           )}
      end
    else
      {:noreply,
       put_flash(socket, :error, "The example is unavailable. Reload it before opening Case Lab.")}
    end
  end

  def handle_event("select_mutation", %{"id" => id}, socket) do
    if Enum.any?(socket.assigns.mutations, &(&1["id"] == id)),
      do: {:noreply, push_patch(socket, to: ~p"/examples?example=#{id}")},
      else: {:noreply, socket}
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
    query = String.slice(query, 0, 100)
    {:noreply, assign(socket, term_query: query, filtered_terms: Education.search_terms(query))}
  end

  def handle_event(_, _, socket), do: {:noreply, socket}

  defp load_story(%{assigns: %{story_moments: moments}} = socket) when is_list(moments),
    do: socket

  defp load_story(socket) do
    case Learning.walkthrough() do
      {:ok, moments} -> assign(socket, story_moments: moments, story_issue: nil)
      {:error, reason} -> assign(socket, story_moments: nil, story_issue: reason)
    end
  end

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
              Enum.map_join(
                ~w(title slug purpose family scenario must_happen wrong_behavior),
                " ",
                &(claim[&1] || "")
              )
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
        active_pipeline: active_pipeline(assigns),
        story_moment:
          if(is_list(assigns.story_moments),
            do: Enum.at(assigns.story_moments, assigns.scenario_step)
          )
      )

    ~H"""
    <Layouts.app
      flash={@flash}
      review_stage={if(@profile, do: "claim")}
      review_claim={@profile && @profile["slug"]}
    >
      <div class="edu-root" id="education-root">
        <%= if @catalog_issue do %>
          <div id="edu-catalog-unavailable" class="edu-caution" role="alert">
            The claim catalog is unavailable. You can still read the guides; claim counts and source links will return when the catalog can be loaded.
          </div>
        <% end %>
        <%= case @live_action do %>
          <% :overview -> %>
            <.overview inventory={@inventory} journeys={@journeys} moment={@story_moment} />
          <% :start -> %>
            <.start moment={@story_moment} moments={@story_moments || []} />
          <% :how_it_fits -> %>
            <.how_it_fits inventory={@inventory} guarantees={@guarantees} counts={@source_counts} />
          <% :examples -> %>
            <.mutation_examples mutations={@mutations} selected={@selected_mutation} />
          <% :translation -> %>
            <.translation source={@translation} />
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
            <.repository />
          <% :glossary -> %>
            <.glossary terms={@filtered_terms} query={@term_query} count={length(@glossary)} />
        <% end %>
        <footer class="edu-footer">
          <span>Hold Ledger · A guide to the repository</span>
          <a href="/repository">Find the source</a>
          <a href="/assurance">Read the evidence</a>
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
  attr :moment, :any, default: nil

  defp overview(assigns) do
    ~H"""
    <section class="edu-home-hero learning-home" id="edu-overview">
      <div class="edu-home-hero-content">
        <p class="edu-eyebrow">Formal verification with Lynx and Lean</p>
        <h1>Follow the code.<span>Understand the proof.</span></h1>
        <p class="edu-hero-sub">
          A payment processor can approve a hold even when its reply never arrives.
          Follow a 100¢ example, inspect the Elixir laws that describe it,
          and see what the Lean proofs establish.
        </p>
        <div class="edu-hero-actions">
          <a class="edu-primary-button" href="/start">
            Follow a payment hold <span aria-hidden="true">→</span>
          </a>
          <a class="edu-ghost-button" href="/lab">Open Case Lab</a>
        </div>
        <p class="edu-home-caption">One account · 100¢ ($1.00) · two hold slots</p>
      </div>
      <.home_example moment={@moment} />
    </section>

    <aside class="edu-overview-lesson" id="edu-overview-lesson">
      <span class="edu-eyebrow">The review question</span>
      <p>
        A ledger can refuse every request and still keep its totals consistent.
        Check whether its claims require the behavior you need.
      </p>
      <a href="/atlas/po_a2">Read the exact-fit claim <span aria-hidden="true">→</span></a>
    </aside>

    <section class="edu-home-journeys" aria-labelledby="edu-paths-title">
      <div class="edu-section-head">
        <div>
          <p class="edu-eyebrow">Choose your next step</p><h2 id="edu-paths-title">
            Start with the question you have.
          </h2>
        </div>
      </div>
      <div class="edu-journey-grid">
        <a :for={journey <- @journeys} class="edu-journey" href={journey.path}>
          <span class="edu-journey-top"><b>{journey.number}</b><small>{journey.tag}</small></span>
          <h3>{journey.title}</h3>
          <p>{journey.description}</p>
          <span class="edu-journey-bottom"><small>{journey.destination}</small><strong aria-hidden="true">→</strong></span>
        </a>
      </div>
    </section>

    <section class="edu-stat-strip" aria-label="Current registered claim inventory">
      <div><strong>{@inventory.total}</strong><span>Registered claims</span></div>
      <div><strong>{@inventory.elixir}</strong><span>Elixir laws</span></div>
      <div><strong>{@inventory.lean}</strong><span>Lean-only claims</span></div>
      <p class="edu-stat-note">
        Counts come from the current catalog. <a href="/assurance">Check the evidence</a>
        before treating a registered claim as formally accepted.
      </p>
    </section>

    <section class="edu-home-map" aria-labelledby="edu-directory-title">
      <div class="edu-section-head">
        <div>
          <p class="edu-eyebrow">Keep a useful page close</p><h2 id="edu-directory-title">
            Find your way around.
          </h2>
        </div>
        <span>Open any page. The reading paths are suggestions.</span>
      </div>
      <nav class="edu-page-directory" aria-label="Page directory">
        <div>
          <h3>The payment model</h3>
          <a href="/start"><strong>Follow a payment hold</strong><span>Request, dispatch and a missing reply</span></a>
          <a href="/system"><strong>Explore the system</strong><span>Ledger, Spec, runtime and the seven states</span></a>
          <a href="/guarantees"><strong>Read the requirements</strong><span>Six behaviors the policy calls for</span></a>
        </div>
        <div>
          <h3>Claims and evidence</h3>
          <a href="/how-it-fits"><strong>How the pieces fit</strong><span>Policy, code, claims and evidence</span></a>
          <a href="/translation"><strong>Elixir to Lean with Lynx</strong><span>Actual source and the supplied theorem</span></a>
          <a href="/proofs"><strong>Read a formal statement</strong><span>Input coverage, promises and assumptions</span></a>
          <a href="/atlas"><strong>Find a claim</strong><span>Browse the eight claim families</span></a>
          <a href="/assurance"><strong>Check the evidence</strong><span>Examples, checks, reports and their scope</span></a>
        </div>
        <div>
          <h3>Tools and reference</h3>
          <a href="/examples"><strong>Learn from deliberate faults</strong><span>Ten source changes and what each challenges</span></a>
          <a href="/lab"><strong>Case Lab</strong><span>Try an input and propose an output</span></a>
          <a href="/repository"><strong>Repository map</strong><span>Find the source for your question</span></a>
          <a href="/glossary"><strong>Glossary</strong><span>Plain meanings and repository examples</span></a>
        </div>
      </nav>
    </section>
    """
  end

  attr :moment, :any, default: nil

  defp home_example(assigns) do
    ~H"""
    <section
      :if={@moment}
      id="edu-home-example"
      class="learning-home-example"
      data-moment={@moment.index}
      aria-label="Interactive payment example"
    >
      <header class="learning-example-heading">
        <span class="edu-eyebrow">Try the payment example</span>
        <span class="learning-step-count">{@moment.index} / 4 events</span>
      </header>
      <div class="learning-home-narration" aria-live="polite">
        <h2>{@moment.title}</h2>
        <p>{@moment.text}</p>
      </div>
      <.capacity_view id="edu-home-capacity" ledger={@moment.ledger} title="The account now" />
      <p :if={@moment.output} id="edu-home-result" class="learning-home-result" role="status">
        <span>Code returned</span>
        <strong>{ReviewCopy.result(@moment.output["result"])}</strong>
        <code>:{@moment.output["result"]}</code>
      </p>
      <div class="learning-home-actions">
        <button
          type="button"
          id="edu-home-next"
          class="edu-primary-button"
          phx-click="scenario"
          phx-value-step={if(@moment.index == 4, do: 0, else: @moment.index + 1)}
        >{@moment.next_action} <span aria-hidden="true">→</span></button>
        <button
          :if={@moment.index > 0 && @moment.index < 4}
          type="button"
          id="edu-home-reset"
          class="learning-text-button"
          phx-click="scenario"
          phx-value-step="0"
        >Start again</button>
      </div>
      <p class="learning-home-scope">Computed by the ledger. No payment processor is contacted.</p>
      <a class="learning-continuation" href={~p"/start?moment=#{@moment.index}"}>
        See this moment before and after <span aria-hidden="true">↗</span>
      </a>
    </section>
    <.story_unavailable :if={!@moment} />
    """
  end

  defp story_unavailable(assigns) do
    ~H"""
    <section id="edu-story-unavailable" class="learning-unavailable" role="status">
      <span class="edu-eyebrow">Example unavailable</span>
      <h2>The model could not be evaluated for this source.</h2>
      <p>Reload the example to try again. You can continue reading the policy and claims.</p>
      <div class="learning-inline-actions">
        <button type="button" id="edu-story-retry" phx-click="reload_story">Reload example</button>
        <a href="/guarantees">Read the requirements →</a>
      </div>
    </section>
    """
  end

  attr :moment, :any, default: nil
  attr :moments, :list, required: true

  defp start(assigns) do
    ~H"""
    <.intro
      eyebrow="Learn · the payment example"
      heading="A missing reply still leaves money on hold."
      description="Start with an empty account, a 100¢ ($1.00) limit and two hold slots. Run the events and watch what the ledger keeps reserved."
    />
    <.story_unavailable :if={!@moment} />
    <section
      :if={@moment}
      id="edu-story"
      class="learning-story"
      data-moment={@moment.index}
      aria-label="Payment-hold walkthrough"
    >
      <header class="learning-story-top">
        <p class="edu-eyebrow">Computed payment example</p>
        <span>{@moment.index} of 4 events · one account</span>
      </header>
      <nav id="edu-story-steps" class="learning-story-steps" aria-label="Choose a story moment">
        <button
          :for={moment <- @moments}
          type="button"
          phx-click="scenario"
          phx-value-step={moment.index}
          class={if(@moment.index == moment.index, do: "active", else: "")}
          aria-pressed={to_string(@moment.index == moment.index)}
          aria-controls="edu-story-event"
        >
          <span class="learning-moment-number">{if(moment.index == 0, do: "○", else: moment.index)}</span>
          <span>{moment.label}</span>
        </button>
      </nav>
      <div id="edu-story-event" class="learning-story-event" aria-live="polite">
        <div>
          <p class="edu-eyebrow">{@moment.label}</p>
          <h2>{@moment.title}</h2>
          <p>{@moment.text}</p>
        </div>
        <div :if={@moment.event} class="learning-event-term">
          <span>Input event</span><code>{inspect(@moment.native_event)}</code>
        </div>
      </div>
      <div class={["learning-story-states", @moment.index == 0 && "learning-story-initial"]}>
        <.capacity_view
          :if={@moment.index == 0}
          id="edu-story-initial"
          ledger={@moment.ledger}
          title="Starting account"
        />
        <.capacity_view
          :if={@moment.index > 0}
          id="edu-story-before"
          ledger={@moment.before}
          title="Before this event"
        />
        <.capacity_view
          :if={@moment.index > 0}
          id="edu-story-after"
          ledger={@moment.ledger}
          title="After this event"
        />
      </div>
      <div :if={@moment.output} id="edu-story-result" class="learning-story-result" role="status">
        <div>
          <span>Code returned</span>
          <strong>{ReviewCopy.result(@moment.output["result"])}</strong>
          <code>:{@moment.output["result"]}</code>
        </div>
        <div>
          <span>Requested outside work</span>
          <p :if={@moment.output["effects"] == []}>None for this event.</p>
          <p :for={effect <- @moment.output["effects"]}>{ReviewCopy.action(effect)}</p>
        </div>
      </div>
      <div class="learning-story-controls">
        <button
          type="button"
          id="edu-story-prev"
          phx-click="scenario"
          phx-value-step={@moment.index - 1}
          disabled={@moment.index == 0}
        >← Previous moment</button>
        <button
          type="button"
          id="edu-story-next"
          class="edu-primary-button"
          phx-click="scenario"
          phx-value-step={if(@moment.index == 4, do: 0, else: @moment.index + 1)}
        >{@moment.next_action} <span aria-hidden="true">→</span></button>
      </div>
      <section class="learning-story-bridge" aria-labelledby="edu-open-moment-title">
        <div>
          <h3 id="edu-open-moment-title">Take this moment into Case Lab.</h3>
          <p>Keep this account and its history. Try another event or propose an output to inspect.</p>
        </div>
        <button
          type="button"
          id="edu-open-moment"
          phx-click="open_story"
          phx-disable-with="Opening…"
        >
          Open this moment in Case Lab <span aria-hidden="true">↗</span>
        </button>
      </section>
      <div class="learning-story-reading">
        <a href={"/atlas/" <> @moment.claim}>{@moment.claim_label} →</a>
        <p :if={@moment.index == 4} class="edu-micro-note">
          PO-A1 checks the next state's validity. The payment policy specifies this rejection;
          validity alone does not require this exact result.
        </p>
        <details id="edu-story-values" class="learning-source-disclosure">
          <summary>See the Elixir values and source</summary>
          <div class="learning-value-grid">
            <section>
              <h3>{if(@moment.index == 0, do: "Initial state", else: "State before the event")}</h3>
              <pre tabindex="0" role="region" aria-label="Story starting state as Elixir"><code>{ReviewCopy.state_tuple(@moment.before)}</code></pre>
            </section>
            <section :if={@moment.output}>
              <h3>Full output: next state, result, effects</h3>
              <pre tabindex="0" role="region" aria-label="Computed output as Elixir"><code>{Learning.output_term(@moment.output)}</code></pre>
            </section>
          </div>
          <p>
            This event uses <code>{@moment.source_function}</code>
            in <code>lib/hold_ledger/ledger.ex</code>.
            <a href="/translation#translation-elixir">Read the code and its admission law →</a>
          </p>
        </details>
      </div>
      <p class="learning-scope-note">
        The states and outputs come from the current ledger implementation. This example contacts no
        processor and does not run a Lean proof.
      </p>
    </section>
    <.reading_note
      id="edu-hold-primer"
      title="What does a payment hold reserve?"
      question="Does reserving an amount mean the payment has already been captured?"
      answer="No. A hold reserves an amount for possible later capture. This walkthrough models the hold and its reserved capacity; it does not run a capture."
    >
      <p>An authorization hold reserves an amount for possible later capture.</p>
      <p>
        Read the opening explanation of
        <a href="https://docs.stripe.com/payments/place-a-hold-on-a-payment-method">Stripe's authorization holds</a>
        and the difference between authorization and capture. API examples can wait.
      </p>
      <p>
        For the Elixir-to-Lean lesson, read the repository's <a href={Education.crash_course_url()}>formal verification crash course</a>.
      </p>
    </.reading_note>
    <.next_links
      one="/how-it-fits"
      one_title="See how the code, claims and proofs fit"
      two="/examples"
      two_title="Learn from a deliberately broken implementation"
    />
    """
  end

  attr :inventory, :map, required: true
  attr :guarantees, :list, required: true
  attr :counts, :map, required: true

  defp how_it_fits(assigns) do
    ~H"""
    <section id="edu-how-it-fits" class="learning-page">
      <.intro
        eyebrow="Learn · the repository map"
        heading="Follow the question from policy to proof."
        description="Each part answers a different question. Use this map to move from required payment behavior to code, claims and evidence for the source you are reading."
      />
      <p id="edu-reading-map-scope" class="learning-map-caption">
        <strong>Reading map, not proof dependencies.</strong>
        The order below is a way into the repository. It does not describe which theorems depend on one another.
      </p>
      <ol class="learning-map" aria-label="From payment policy to matching evidence">
        <li>
          <span class="learning-map-number">01</span>
          <h2>Begin with the payment policy.</h2>
          <p>
            When must a request succeed? When may capacity be released? Decide what the system is required to do.
          </p>
          <code>guides/specification.md</code>
          <a href="/guarantees">Read the required behavior →</a>
        </li>
        <li>
          <span class="learning-map-number">02</span>
          <h2>Find a requirement to examine.</h2>
          <p>
            {@guarantees |> length()} summaries connect the policy to concrete cases, including exact fit, missing replies and retained identities.
          </p>
          <span class="learning-map-fact">Curated reading summaries</span>
          <a href="/start">Follow the missing-reply example →</a>
        </li>
        <li>
          <span class="learning-map-number">03</span>
          <h2>Compare implementation and specification.</h2>
          <p>
            Ledger handles an event. Spec independently describes the expected behavior. Both are pure Elixir modules.
          </p>
          <code>lib/hold_ledger/ledger.ex · spec.ex</code>
          <a href="/system">See their responsibilities →</a>
        </li>
        <li>
          <span class="learning-map-number">04</span>
          <h2>Read the claim's input and conclusion.</h2>
          <p>
            The catalog registers {@inventory.total} claim groups: {@inventory.elixir} Elixir laws and {@inventory.lean} Lean-only claims. A group may contain several theorems.
          </p>
          <code>verification/laws.json</code>
          <a href="/atlas">Find a claim →</a>
        </li>
        <li>
          <span class="learning-map-number">05</span>
          <h2>Follow the translation and supplied proof.</h2>
          <p>
            Lynx translates supported Elixir into Lean. The shared proof library has {@counts.shared_lean_files} source files, with definitions and proofs used across claims.
          </p>
          <code>test/support/lean/*.lean</code>
          <a href="/translation">Read Elixir and Lean together →</a>
        </li>
        <li>
          <span class="learning-map-number">06</span>
          <h2>Check evidence for these source bytes.</h2>
          <p>
            A matching verification report records its scope, required checker results, exported statements and allowed axioms.
          </p>
          <span class="learning-map-fact">Registration alone is not acceptance</span>
          <a href="/assurance">Read the evidence and assumptions →</a>
        </li>
      </ol>
      <aside class="learning-context-note">
        <h2>Where does the outside world enter?</h2>
        <p>
          The runtime records and delivers work. The processor contract states the assumptions about identities and terminal results. A proof about the ledger or coupled model covers its stated model and premises; it does not itself contact a payment processor.
        </p>
        <a href="/system">Read the system boundary →</a>
      </aside>
      <div class="learning-reading-cards" aria-label="Continue learning">
        <a href="/examples"><span>Practice reading a fault</span><strong>See what a deliberate code change breaks.</strong></a>
        <a href="/lens/po_a2?mode=explore"><span>Practice reading a claim</span><strong>See how a changed premise can leave out exact fit.</strong></a>
        <a href={Education.crash_course_url()}><span>Repository guide</span><strong>Read the formal verification crash course.</strong></a>
      </div>
    </section>
    """
  end

  attr :mutations, :list, required: true
  attr :selected, :any, default: nil

  defp mutation_examples(assigns) do
    ~H"""
    <section id="edu-examples" class="learning-page">
      <.intro
        eyebrow="Learn · deliberate faults"
        heading="See what one code change can break."
        description="Choose a mutation, follow its concrete input and read the claim aimed at the fault. These examples make the required behavior easier to recognize."
      />
      <p id="edu-examples-scope" class="learning-scope-note">
        Source examples from this repository. This page reads the existing patch and witness;
        it does not run the mutation or report a new test result.
      </p>
      <div class="learning-example-layout">
        <nav class="learning-example-picker" aria-label="Choose a deliberate mutation">
          <button
            :for={example <- @mutations}
            type="button"
            id={"edu-mutation-" <> example["id"]}
            phx-click="select_mutation"
            phx-value-id={example["id"]}
            aria-pressed={to_string(@selected != nil && @selected.example["id"] == example["id"])}
            aria-controls="edu-selected-mutation"
          ><span>{example["id"]}</span><strong>{example["title"]}</strong></button>
        </nav>
        <article
          :if={@selected}
          id="edu-selected-mutation"
          class="learning-example-detail"
          data-example-id={@selected.example["id"]}
          aria-live="polite"
        >
          <header>
            <p class="edu-eyebrow">Mutation {@selected.example["id"]}</p>
            <h2>{@selected.example["title"]}</h2>
            <p>{@selected.example["summary"]}</p>
          </header>
          <dl class="learning-example-contrast">
            <div>
              <dt>Expected from the source</dt><dd>{@selected.example["expected_output"]}</dd>
            </div>
            <div>
              <dt>What the mutation changes</dt><dd>{@selected.example["challenge"]}</dd>
            </div>
          </dl>
          <section class="learning-example-witness" aria-labelledby="edu-mutation-witness-title">
            <h3 id="edu-mutation-witness-title">A concrete input to examine</h3>
            <div class="learning-value-grid">
              <div>
                <h4>Starting state</h4><pre
                  tabindex="0"
                  role="region"
                  aria-label="Mutation witness starting state"
                ><code>{@selected.example["before"]}</code></pre>
              </div>
              <div>
                <h4>Event</h4><pre tabindex="0" role="region" aria-label="Mutation witness event"><code>{@selected.example["event"]}</code></pre>
              </div>
            </div>
            <p>{@selected.example["lesson"]}</p>
          </section>
          <section class="learning-example-target">
            <div>
              <span>Claim aimed at this fault</span><h3>
                {Education.title(@selected.example["target_slug"])}
              </h3><code>{@selected.example["target_slug"]}</code>
            </div>
            <a id="edu-mutation-claim" href={"/atlas/" <> @selected.example["target_slug"]}>Read the claim →</a>
          </section>
          <section class="learning-patch" aria-labelledby="edu-mutation-patch-title">
            <h3 id="edu-mutation-patch-title">The patch in the repository</h3>
            <%= if @selected.patch do %>
              <p class="edu-source-note"><code>{@selected.patch.path}</code></p>
              <pre
                id="edu-mutation-patch"
                tabindex="0"
                role="region"
                aria-label="Mutation source patch"
              ><code>{@selected.patch.text}</code></pre>
            <% else %>
              <p id="edu-mutation-patch-unavailable">
                The patch file is unavailable in this checkout. The authored example remains available above.
              </p>
            <% end %>
            <details class="learning-source-disclosure">
              <summary>Source paths for this example</summary>
              <ul>
                <li :for={path <- @selected.example["source_paths"]}><code>{path}</code></li>
              </ul>
            </details>
          </section>
        </article>
        <section
          :if={!@selected}
          id="edu-mutation-unavailable"
          class="learning-unavailable"
          role="status"
        >
          <h2>That mutation is not in this directory.</h2>
          <p>Choose one of the ten listed examples to read its input and source patch.</p>
        </section>
      </div>
      <aside class="learning-context-note">
        <h2>Continue with a proposed output or claim.</h2>
        <p>
          The full directory also has eight policy exercises, including P08's correct local cancellation. Claim Lens lets you inspect two authored claim changes.
        </p>
        <div class="learning-inline-actions">
          <a href="/repository#review-exercises">Read all policy exercises →</a>
          <a href="/lens/po_a2?mode=explore">See a worked claim review →</a>
        </div>
      </aside>
    </section>
    """
  end

  attr :source, :any, default: nil

  defp translation(assigns) do
    assigns = assign(assigns, :reading, assigns.source && assigns.source.reading)

    ~H"""
    <section id="edu-translation" class="learning-page">
      <.intro
        eyebrow="Learn · Elixir to Lean with Lynx"
        heading="Follow an Elixir law into its proof."
        description="Use the exact-fit claim, PO-A2, to distinguish the code and law you write, the Lean definitions Lynx generates, and the theorem whose proof is supplied in the repository."
      />
      <section :if={!@source} id="translation-unavailable" class="learning-unavailable" role="status">
        <h2>The matching source is unavailable.</h2>
        <p>
          This page could not read PO-A2 from the configured checkout. The source panels will return when those files can be read together.
        </p>
        <a href="/assurance">Read how source identity is checked →</a>
      </section>
      <%= if @source do %>
        <div class="learning-translation-grid">
          <section id="translation-elixir" class="learning-translation-panel">
            <header>
              <span class="learning-panel-number">01</span><p class="edu-eyebrow">Authored Elixir</p><h2>
                The law states when and what.
              </h2>
            </header>
            <p>
              <button type="button" class="edu-term-button" data-edu-term="requires">requires</button>
              selects the inputs covered by this law.
              <button type="button" class="edu-term-button" data-edu-term="expects">expects</button>
              describes the required output.
            </p>
            <h3>Input condition</h3>
            <pre tabindex="0" role="region" aria-label="PO-A2 requires condition"><code>{@reading["contract"]["requires"]}</code></pre>
            <h3>Required output</h3>
            <pre tabindex="0" role="region" aria-label="PO-A2 expects condition"><code>{@reading["contract"]["expects"]}</code></pre>
            <p class="edu-source-note">
              <code>test/laws/po_a2_test.exs</code> · line {@reading["contract"]["line"]}
            </p>
            <a href={Learning.source_url(@reading, "test/laws/po_a2_test.exs")}>Read the complete Elixir law →</a>
            <details id="translation-implementation" class="learning-source-disclosure">
              <summary>Read the implementation and eligibility predicate</summary>
              <%= for {label, excerpt} <- [{"Implementation", @source.implementation}, {"Independent input predicate", @source.eligibility}] do %>
                <section :if={excerpt}>
                  <h3>{label}</h3>
                  <pre tabindex="0" role="region" aria-label={label <> " source excerpt"}><code>{excerpt.text}</code></pre>
                  <p class="edu-source-note"><code>{excerpt.path}</code> · line {excerpt.line}</p>
                  <a href={excerpt.url}>Read the complete source →</a>
                </section>
                <p :if={!excerpt}>{label} excerpt is unavailable for the current source.</p>
              <% end %>
            </details>
          </section>
          <section id="translation-generated" class="learning-translation-panel">
            <header>
              <span class="learning-panel-number">02</span><p class="edu-eyebrow">
                Generated by Lynx
              </p><h2>The code becomes Lean definitions.</h2>
            </header>
            <p>
              Lynx translates supported Elixir through Core Erlang into Lean. Its definitions represent the implementation and the law's input and output conditions.
            </p>
            <%= if @source.generated do %>
              <p>A matching generated definition excerpt:</p>
              <pre
                id="translation-generated-source"
                tabindex="0"
                role="region"
                aria-label="Actual Lynx-generated definition"
              ><code>{@source.generated.text}</code></pre>
              <p class="edu-source-note">
                <code>{@source.generated.path}</code> · line {@source.generated.line}
              </p>
              <a href={@source.generated.url}>Read the full generated source →</a>
            <% else %>
              <div id="translation-generated-unavailable" class="learning-source-empty">
                <h3>No matching generated definition is available here.</h3>
                <p>
                  This checkout does not currently expose a readable generated definition for this example. The Elixir and supplied proof panels remain useful for reading.
                </p>
                <p>
                  Existing verification tooling produces the focused artifacts. This page does not generate them or substitute proof text for translated code.
                </p>
              </div>
            <% end %>
            <p class="learning-source-status">
              Focused artifact status:
              <strong>{ReviewCopy.evidence_status(@reading["focused"]["status"])}</strong>
            </p>
            <details
              :if={@reading["focused"]["artifacts"] not in [nil, []]}
              class="learning-source-disclosure"
            >
              <summary>Available matching generated artifacts</summary>
              <ul>
                <li :for={artifact <- @reading["focused"]["artifacts"]}>
                  <a href={"/claims/po_a2/generated/" <> artifact["sha256"]}><code>{artifact["path"]}</code></a>
                </li>
              </ul>
            </details>
            <p class="learning-scope-note">
              A faithful translation and the supported language subset are part of the connection from Elixir to the checked theorem.
            </p>
          </section>
          <section id="translation-theorem" class="learning-translation-panel">
            <header>
              <span class="learning-panel-number">03</span><p class="edu-eyebrow">
                Supplied Lean theorem and proof
              </p><h2>The proof establishes this statement.</h2>
            </header>
            <p>
              The premise below uses the generated <code>requires</code>
              condition. The conclusion requires the generated <code>ensures</code>
              condition to return true; that condition comes from the law's <code>expects</code>
              clause.
            </p>
            <div :for={declaration <- @reading["declarations"]}>
              <p class="learning-source-status">
                {ReviewCopy.evidence_status(declaration["status"])}
              </p>
              <pre
                id="translation-theorem-header"
                tabindex="0"
                role="region"
                aria-label="PO-A2 supplied theorem statement"
              ><code>{declaration["header"]}</code></pre>
              <p class="edu-source-note">
                <code>{declaration["path"]}</code> · line {declaration["line"]}
              </p>
              <details id="translation-proof" class="learning-source-disclosure">
                <summary>Read the supplied proof body</summary>
                <pre tabindex="0" role="region" aria-label="PO-A2 supplied proof body"><code>{declaration["text"]}</code></pre>
                <a href={Learning.source_url(@reading, declaration["path"])}>Read the complete Lean file →</a>
              </details>
            </div>
            <details :if={@reading["inline_proof"]} class="learning-source-disclosure">
              <summary>See how the Elixir law invokes this proof</summary>
              <pre tabindex="0" role="region" aria-label="Proof supplied by the Elixir law"><code>{@reading["inline_proof"]["text"]}</code></pre>
            </details>
            <p class="learning-scope-note">
              These are checked-in source declarations. Reading them does not establish a current verification result.
            </p>
          </section>
        </div>
        <section
          id="translation-evidence"
          class="learning-evidence-summary"
          aria-labelledby="translation-evidence-title"
        >
          <div>
            <p class="edu-eyebrow">Source and evidence</p><h2 id="translation-evidence-title">
              Does a verification report match this checkout?
            </h2>
            <p>
              Current report status:
              <strong>{ReviewCopy.evidence_status(@reading["formal"]["status"])}</strong>
            </p>
            <p>
              Focused elaboration is separate from full acceptance. Full acceptance also checks the required scope, exported statements, allowed axioms and exact source identity.
            </p>
          </div>
          <div class="learning-inline-actions">
            <a href="/claims/po_a2">Open this claim in Case Lab →</a><a href="/assurance">Understand evidence and assumptions →</a>
          </div>
        </section>
      <% end %>
      <div id="translation-reading" class="learning-reading-cards" aria-label="Continue learning">
        <a href={Education.crash_course_url()}><span>Repository guide</span><strong>Read the formal verification crash course.</strong></a>
        <a href="/start"><span>A concrete input</span><strong>Follow the 100¢ payment example.</strong></a>
        <a href="/lens/po_a2?mode=explore"><span>A changed claim</span><strong>See why excluding exact fit leaves a policy gap.</strong></a>
      </div>
    </section>
    """
  end

  attr :components, :list, required: true
  attr :statuses, :list, required: true
  attr :component, :map, required: true
  attr :status, :map, required: true

  defp system(assigns) do
    ~H"""
    <.intro
      eyebrow="Learn · the system"
      heading="Follow a hold through the system."
      description="Ledger handles each event. Spec describes the expected behavior independently. The runtime records inputs and asks the processor to do the outside work."
    />
    <div class="edu-section-head">
      <div>
        <p class="edu-eyebrow">Code and responsibilities</p><h2>Choose a part to see its role.</h2>
      </div>
    </div>
    <section class="edu-architecture" aria-label="System responsibilities">
      <div class="edu-arch-cards" role="group" aria-label="Architecture layers">
        <button
          :for={node <- @components}
          type="button"
          phx-click="component"
          phx-value-id={node.id}
          class={["edu-arch-node", @component.id == node.id && "active"]}
          aria-pressed={to_string(@component.id == node.id)}
          aria-controls="edu-component-detail"
        ><strong>{node.title}</strong><span>{node.role}</span></button>
      </div>
      <div class="edu-arch-explainer" id="edu-component-detail" aria-live="polite">
        <p class="edu-eyebrow">Its part in the system</p>
        <h3>{@component.title}</h3>
        <p>{@component.explanation}</p>
        <div class="edu-file-label"><span>Source</span><code>{@component.path}</code></div>
        <a href={@component.link}>Read more about this part →</a>
      </div>
    </section>
    <.reading_note
      id="edu-retry-primer"
      title="A retry keeps the payment identity."
      question="Should retrying this authorization create a new payment identity?"
      answer="No. This ledger retries with the same request key and amount. A new worker attempt can have its own attempt ID while still referring to that same hold."
    >
      <p>
        Read the opening paragraphs of
        <a href="https://docs.stripe.com/api/idempotent_requests">Stripe's idempotent requests</a>
        about connection errors, keeping the key and unchanged parameters. The API examples can wait.
      </p>
      <p class="edu-source-note">
        This repository's permanent identity and terminal-fencing requirements are stronger
        assumptions, defined in <code>guides/processors.md</code>.
      </p>
    </.reading_note>
    <section class="edu-status-section">
      <div class="edu-section-head">
        <div>
          <p class="edu-eyebrow">What the ledger remembers</p><h2>
            Seven states, different reasons to hold capacity.
          </h2>
        </div>
      </div>
      <div class="edu-status-grid" role="group" aria-label="Hold state explanations">
        <button
          :for={status <- @statuses}
          type="button"
          phx-click="status"
          phx-value-id={status.id}
          class={["edu-state-chip", @status.id == status.id && "active"]}
          aria-pressed={to_string(@status.id == status.id)}
          aria-controls="edu-status-detail"
        >{status.label}</button>
      </div>
      <div class="edu-status-detail" id="edu-status-detail" aria-live="polite">
        <div>
          <p class="edu-eyebrow">Selected state</p><h3>{@status.label}</h3>
        </div>
        <div>
          <strong>{@status.description}</strong><p>{@status.detail}</p>
        </div>
        <a href="/atlas?family=Identity+%26+lifecycle">Read the lifecycle claims →</a>
      </div>
      <p class="edu-micro-note">
        These are state descriptions. Which transitions are allowed depends on the current state and the event.
      </p>
      <details class="edu-disclosure" id="edu-raw-state-guide">
        <summary>Read the raw state tuple</summary>
        <div class="edu-disclosure-content">
          <code phx-no-curly-interpolation>{amount_limit, hold_limit, used_amount, used_holds, entries}</code>
          <p>
            The first two fields are the account's limits. The next two count the amount and slots currently held. Each entry records a key, an amount in cents and a state.
          </p>
          <code phx-no-curly-interpolation>{100, 2, 100, 1, [{11, 100, :unknown}]}</code>
          <p>
            This account allows 100¢ and two holds. Request 11 uses all 100¢ and one slot. Amounts are integer cents; 100¢ is $1.00.
          </p>
          <p class="edu-source-note">Source: <code>guides/specification.md</code></p>
        </div>
      </details>
    </section>
    <.next_links
      one="/guarantees"
      one_title="Read the required behavior"
      two="/repository"
      two_title="Find the source files"
    />
    """
  end

  attr :guarantees, :list, required: true
  attr :guarantee, :map, required: true

  defp guarantees(assigns) do
    ~H"""
    <.intro
      eyebrow="Learn · policy"
      heading="Six requirements for a payment hold."
      description="The policy explains when capacity may be used, kept or released. Choose a requirement to see the behavior it calls for and the claims that help check it."
    />
    <div class="edu-guarantee-layout">
      <div class="edu-guarantee-picker" role="group" aria-label="Select a requirement">
        <button
          :for={g <- @guarantees}
          type="button"
          phx-click="guarantee"
          phx-value-id={g.id}
          class={["edu-guarantee-choice", @guarantee.id == g.id && "active"]}
          aria-pressed={to_string(@guarantee.id == g.id)}
          aria-controls="edu-guarantee-detail"
        ><span>{g.number}</span><strong>{g.title}</strong><span aria-hidden="true">→</span></button>
      </div>
      <section class="edu-guarantee-card" id="edu-guarantee-detail" aria-live="polite">
        <p class="edu-eyebrow">Requirement {@guarantee.number}</p>
        <h2>{@guarantee.title}</h2>
        <p class="edu-guarantee-nutshell">{@guarantee.nutshell}</p>
        <div class="edu-contrast-pair">
          <div>
            <h3>Required behavior</h3><p>{@guarantee.safe}</p>
          </div>
          <div>
            <h3>What would go wrong</h3><p>{@guarantee.unsafe}</p>
          </div>
        </div>
        <h3 class="edu-related-heading">Claims to read</h3>
        <div class="edu-related-links">
          <a :for={slug <- @guarantee.slugs} href={"/atlas/" <> slug}>
            <span>{Education.title(slug) || slug}</span><code>{slug}</code>
          </a>
        </div>
        <p class="edu-source-note">
          Policy source: <code>guides/specification.md</code>. Each claim's input conditions determine which part it covers.
        </p>
      </section>
    </div>
    <.next_links
      one="/atlas"
      one_title="Find claims by question"
      two="/lens/po_a2"
      two_title="Review a changed exact-fit claim"
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
      eyebrow="Claims · the reading map"
      heading="Find the claim you need."
      description="Start with a question, then read the statement that answers it. The eight families below suggest a reading order, from bookkeeping to recovery."
    />
    <section id="edu-origin-story" class="edu-origin-story" aria-labelledby="edu-families-title">
      <div class="edu-section-head">
        <div>
          <p class="edu-eyebrow">Eight families</p><h2 id="edu-families-title">
            What are you trying to understand?
          </h2>
        </div>
        <span>This is a reading order, not a proof-dependency diagram.</span>
      </div>
      <nav class="edu-family-grid" id="edu-families" aria-label="Claim families in reading order">
        <a
          :for={family <- @families}
          href={"/atlas?family=" <> URI.encode_www_form(family.id)}
          class={["edu-family-tile", @family == family.id && "active"]}
          aria-current={if(@family == family.id, do: "true", else: nil)}
        >
          <span class="edu-family-number">{family.number}</span>
          <div>
            <span class="edu-family-name">{family.id}</span><h3>{family.question}</h3>
          </div>
          <span class="edu-family-count">{length(Education.by_family(@all, family.id))}<small>claims</small></span>
        </a>
      </nav>
    </section>
    <section class="edu-atlas-browser" id="edu-atlas-browser">
      <div class="edu-section-head">
        <div>
          <p class="edu-eyebrow">The current catalog</p><h2>Search the claims.</h2>
        </div>
        <span id="edu-atlas-count" role="status">{length(@claims)} of {length(@all)} claims</span>
      </div>
      <.form
        for={to_form(%{"q" => @query, "family" => @family, "kind" => @kind, "priority" => @priority})}
        id="edu-atlas-filters"
        phx-change="filter_claims"
        class="edu-atlas-filters"
      >
        <.input
          id="edu-claim-query"
          type="search"
          name="q"
          value={@query}
          label="Search a claim or scenario"
          placeholder="Try timeout, exact fit, recovery…"
          phx-debounce="200"
          class="edu-filter-input"
        />
        <.input
          id="edu-family-filter"
          type="select"
          name="family"
          value={@family}
          label="Family"
          options={[{"All families", "all"}] ++ Enum.map(@families, &{&1.id, &1.id})}
          class="edu-filter-input"
        />
        <.input
          id="edu-kind-filter"
          type="select"
          name="kind"
          value={@kind}
          label="Source type"
          options={[
            {"Both source types", "all"},
            {"Elixir law", "elixir_law"},
            {"Lean-only claim", "native_lean"}
          ]}
          class="edu-filter-input"
        />
        <.input
          id="edu-priority-filter"
          type="select"
          name="priority"
          value={@priority}
          label="Catalog priority"
          options={[{"All priorities", "all"}, {"L · foundations", "L"}, {"P0", "P0"}, {"P1", "P1"}]}
          class="edu-filter-input"
        />
      </.form>
      <div class="edu-atlas-results" id="edu-atlas-results">
        <a
          :for={claim <- @claims}
          href={"/atlas/" <> claim["slug"]}
          class="edu-claim-row"
          data-claim-slug={claim["slug"]}
        >
          <span class="edu-claim-identity"><code>{claim["id"]}</code><small>{claim["priority"]}</small></span>
          <span class="edu-claim-description"><strong>{claim["title"]}</strong><span>{claim[
            "must_happen"
          ] || claim["purpose"]}</span></span>
          <span class="edu-claim-tags"><span>{claim["family"]}</span><small>{if(
            claim["kind"] == "native_lean",
            do: "Lean-only",
            else: "Elixir law"
          )}</small></span>
          <span class="edu-row-arrow" aria-hidden="true">→</span>
        </a>
      </div>
      <div :if={@claims == []} class="edu-empty">
        <h3>No claims match these filters.</h3>
        <p>Try a shorter phrase or return to all families and source types.</p>
        <.link patch="/atlas">Clear filters →</.link>
      </div>
      <p class="edu-source-note">
        The catalog supplies the claim IDs, source types and priorities. Registration identifies a statement; acceptance requires matching evidence.
      </p>
    </section>
    <.next_links
      one="/proofs"
      one_title="Learn to read the statement"
      two="/assurance"
      two_title="Check what the evidence establishes"
    />
    """
  end

  attr :example, :map, required: true

  defp example_card(assigns) do
    ~H"""
    <article
      class="edu-example-card"
      id={"example-" <> String.downcase(@example["id"])}
      data-example-id={@example["id"]}
      data-example-kind={@example["kind"]}
    >
      <header class="edu-example-heading">
        <p class="edu-eyebrow">
          {if(@example["kind"] == "mutation", do: "Deliberate mutation", else: "Policy exercise")}
        </p>
        <h3><span>{@example["id"]}</span> {@example["title"]}</h3>
        <span :if={@example["correct_control"]} class="edu-example-control">
          Correct local cancellation
        </span>
      </header>
      <p class="edu-example-summary">{@example["summary"]}</p>
      <dl class="edu-example-contrast">
        <div>
          <dt>Expected from the source</dt>
          <dd>{@example["expected_output"]}</dd>
        </div>
        <div>
          <dt>
            {if(@example["kind"] == "mutation",
              do: "What the mutation changes",
              else: "Proposed output · not run"
            )}
          </dt>
          <dd>{@example["challenge"]}</dd>
        </div>
      </dl>
      <p class="edu-example-lesson">{@example["lesson"]}</p>
      <details class="edu-example-source">
        <summary>Input and source details</summary>
        <div>
          <dl :if={@example["kind"] == "mutation"} class="edu-example-input">
            <div>
              <dt>Starting state</dt><dd><code>{@example["before"]}</code></dd>
            </div>
            <div>
              <dt>Event</dt><dd><code>{@example["event"]}</code></dd>
            </div>
          </dl>
          <p :if={@example["fixture_path"]} class="edu-source-note">
            Existing source fixture · not executed here<br />
            <code>{@example["fixture_path"]}</code>
          </p>
          <pre
            :if={@example["fixture_json"]}
            tabindex="0"
            role="region"
            aria-label={"Source fixture for " <> @example["id"]}
          ><code>{@example["fixture_json"]}</code></pre>
          <p :if={@example["fixture_path"] && !@example["fixture_json"]} class="edu-source-note">
            The fixture source is unavailable in this checkout.
          </p>
          <p class="edu-source-note">Read these paths in your checkout:</p>
          <ul class="edu-example-paths">
            <li :for={path <- @example["source_paths"]}><code>{path}</code></li>
          </ul>
          <a
            :if={@example["target_slug"]}
            class="edu-inline-link"
            href={"/atlas/" <> @example["target_slug"]}
          >Read the claim: {Education.title(@example["target_slug"])}</a>
        </div>
      </details>
    </article>
    """
  end

  attr :claim, :map, default: nil

  defp profile(assigns) do
    related =
      if assigns.claim do
        Education.examples(
          (assigns.claim["named_mutants"] || []) ++ (assigns.claim["exercise_ids"] || [])
        )
      else
        []
      end

    assigns = assign(assigns, :examples, related)

    ~H"""
    <%= if @claim do %>
      <nav class="edu-profile-breadcrumb" aria-label="Claim location">
        <a href="/atlas">← All claims</a><span>{@claim["family"]}</span>
      </nav>
      <section class="edu-profile-hero" id="edu-claim-profile">
        <div class="edu-profile-heading">
          <p class="edu-eyebrow">Read a claim · {@claim["id"]}</p>
          <span class="edu-evidence-label">Registered claim</span>
        </div>
        <h1>{@claim["title"]}</h1>
        <div class="edu-profile-badges">
          <span>{@claim["family"]}</span>
          <span>{if(@claim["kind"] == "native_lean", do: "Lean-only claim", else: "Elixir law")}</span>
        </div>
        <div class="edu-editorial-status" id="edu-claim-editorial">
          <span>Editorial draft</span>
          <p>Sources are linked below. Owner review of this explanation is not recorded here.</p>
        </div>
        <div class="edu-profile-scenario" id="edu-claim-scenario">
          <p class="edu-eyebrow">Consider this case</p><p>{@claim["scenario"]}</p>
        </div>
      </section>
      <div class="edu-profile-grid">
        <section class="edu-profile-panel edu-profile-promise">
          <p class="edu-eyebrow">The promise</p><h2>Must happen</h2><p>{@claim["must_happen"]}</p>
        </section>
        <section class="edu-profile-panel edu-profile-wrong">
          <p class="edu-eyebrow">The challenge</p><h2>Wrong behavior</h2><p>
            {@claim["wrong_behavior"]}
          </p>
        </section>
      </div>
      <section class="edu-profile-scope" id="edu-claim-scope" aria-labelledby="edu-scope-title">
        <h2 id="edu-scope-title">Scope</h2><p>{@claim["does_not_cover"]}</p>
      </section>
      <div class="edu-profile-actions">
        <a class="edu-primary-button" href={"/claims/" <> @claim["slug"]}>Read the full statement
        <span aria-hidden="true">→</span></a>
        <a
          :if={@claim["slug"] in ~w(po_a2 po_exposure_retain)}
          class="edu-secondary-button"
          href={"/lens/" <> @claim["slug"]}
        >Practice this review</a>
        <button
          id="edu-copy-claim"
          type="button"
          class="edu-copy-button"
          data-copy-text={Education.claim_summary(@claim)}
        >Copy claim summary</button>
      </div>
      <p class="edu-source-note">
        Registration does not report checker acceptance.
        <a href="/assurance#catalog-evidence">See what each kind of evidence covers.</a>
      </p>
      <section class="edu-related-examples" id="edu-related-examples">
        <div class="edu-section-head">
          <div>
            <h2>Examples for this claim</h2>
          </div>
        </div>
        <p :if={@examples != []} class="edu-source-note">
          M identifies a deliberate source fault outside the default implementation.
          P identifies a payment-policy exercise. These cards explain the source examples;
          they do not run them.
        </p>
        <div :if={@examples != []} class="edu-example-grid">
          <.example_card :for={example <- @examples} example={example} />
        </div>
        <p :if={(@claim["named_mutants"] || []) == []} class="edu-source-note">
          No named mutant yet.
        </p>
        <p :if={@examples == []} class="edu-source-note">
          Use the case above and the statement's cited sources to inspect this claim.
        </p>
      </section>
      <details class="edu-disclosure" id="edu-claim-source">
        <summary>Explanation and source references</summary>
        <div class="edu-disclosure-content edu-profile-detail-grid">
          <section>
            <h2>Why another check may miss it</h2>
            <p>{@claim["why_others_miss"]}</p>
          </section>
          <section>
            <h2>Statement and explanation sources</h2>
            <dl class="edu-source-identity">
              <div>
                <dt>Claim ID</dt><dd><code>{@claim["slug"]}</code></dd>
              </div>
              <div>
                <dt>Statement</dt><dd>
                  <code>{@claim["education_source_path"] || @claim["module"]}</code>
                </dd>
              </div>
              <div>
                <dt>Declaration</dt><dd>
                  <code>{@claim["target"] || Enum.join(@claim["theorems"] || [], ", ")}</code>
                </dd>
              </div>
            </dl>
            <ul class="edu-provenance-list">
              <li :for={source <- @claim["provenance"] || []}>
                <strong>{source["reference"]}</strong>
                <span :if={source["section"]}>{source["section"]}</span>
                <code>{source["path"]}</code>
              </li>
            </ul>
            <a class="edu-inline-link" href={"/claims/" <> @claim["slug"]}>Open the source reading →</a>
          </section>
        </div>
      </details>
      <.next_links
        one="/atlas"
        one_title="Find another claim"
        two="/assurance"
        two_title="Read the evidence and assumptions"
      />
    <% else %>
      <section id="edu-unknown-claim" class="edu-empty">
        <h1>That claim is not in the current catalog.</h1>
        <p>Check the claim ID or browse the catalog to find the statement you need.</p>
        <a href="/atlas">Return to all claims →</a>
      </section>
    <% end %>
    """
  end

  attr :pipeline, :list, required: true
  attr :active, :map, required: true

  defp proofs(assigns) do
    ~H"""
    <.intro
      eyebrow="Learn · reading statements"
      heading="Read what a claim promises."
      description="A proof establishes the statement it was given. Your first job is to check whether that statement covers the behavior the policy requires. Start with a request that fits exactly."
    />
    <section class="edu-reading-guide" aria-labelledby="edu-reading-title">
      <aside class="edu-reading-example">
        <p class="edu-eyebrow">The running example · PO-A2</p>
        <h2 id="edu-reading-title">100¢ free.<br />100¢ requested.</h2>
        <p>
          The valid account starts empty, with a 100¢ limit and two hold slots. Request 11 is new. The policy requires admission.
        </p>
        <dl>
          <div>
            <dt>Amount held afterward</dt><dd>100¢</dd>
          </div><div>
            <dt>Slots used afterward</dt><dd>1</dd>
          </div>
        </dl>
        <a href="/atlas/po_a2">Read the claim's full example →</a>
      </aside>
      <ol class="edu-reading-steps">
        <li>
          <h3>Find the inputs it covers</h3>
          <p>
            The
            <button type="button" class="edu-term-button" data-edu-term="requires">requires</button>
            clause calls <code>Spec.request_eligible?(s, key, amount)</code>. The name is a starting point; follow the predicate to read its conditions.
          </p>
        </li>
        <li>
          <h3>Read the called predicate</h3>
          <p>
            Eligibility includes a valid state, an unused integer key, a positive integer amount, an open slot and enough remaining amount. Its comparison uses <code>&lt;=</code>, so the 100¢ exact fit is included.
          </p>
        </li>
        <li>
          <h3>Read the promised output</h3>
          <p>
            The <button type="button" class="edu-term-button" data-edu-term="expects">expects</button>
            clause requires <code>:admitted</code>, the exact updated counters and a reserved entry. It also matches the independent Spec result.
          </p>
        </li>
      </ol>
    </section>
    <.reading_note
      id="edu-statement-primer"
      title="Read the condition before the promise."
      question="In P → Q, what must hold before this implication promises Q?"
      answer="P must hold. If the input does not satisfy the premise, this implication makes no promise about Q for that input."
    >
      <p>
        Read sections 3.1–3.3 of Lean's
        <a href="https://lean-lang.org/theorem_proving_in_lean4/Propositions-and-Proofs/">Propositions and Proofs</a>
        to recognize <code>Prop</code>, implication <code>→</code>
        and conjunction <code>∧</code>.
        Skip constructing the proofs and exercises on the first pass.
      </p>
    </.reading_note>
    <details class="edu-disclosure" id="edu-contract-source">
      <summary>Read the PO-A2 contract in Elixir</summary>
      <div class="edu-disclosure-content">
        <p>Contract excerpt from <code>test/laws/po_a2_test.exs</code>:</p>
        <pre phx-no-curly-interpolation><code>requires: Spec.request_eligible?(s, key, amount),
    expects:
    Ledger.request(s, key, amount) ==
    {{elem(s, 0), elem(s, 1), elem(s, 2) + amount, elem(s, 3) + 1,
      [{key, amount, :reserved} | elem(s, 4)]}, :admitted, []} and
    Ledger.request(s, key, amount) == Spec.expected_step(s, {:request, key, amount})</code></pre>
        <p>
          The final empty list means this request produces no outside effect. Dispatch is a separate event.
        </p>
        <a class="edu-inline-link" href="/claims/po_a2">Open the current source and its reading aids →</a>
      </div>
    </details>
    <section class="edu-concept-pair" aria-label="Two questions to ask of a statement">
      <article>
        <p class="edu-eyebrow">Beyond one example</p><h2>Which inputs does “every” include?</h2>
        <p>
          The 100¢ example is one case. A checked proof establishes the statement for every input in its domain that satisfies the premise. That domain is part of the claim you are reviewing.
        </p>
        <p>
          Compare the covered inputs with the policy. Excluding exact fit would leave out an important case, even if other requests were still covered.
        </p>
      </article>
      <article>
        <p class="edu-eyebrow">Check that it can apply</p><h2>
          Can a real input satisfy the premise?
        </h2>
        <p>
          If nothing satisfies the premise, the statement can be true without requiring any behavior. This is <button
            type="button"
            class="edu-term-button"
            data-edu-term="vacuity"
          >vacuity</button>.
        </p>
        <p>
          Find a concrete covered input, then test important boundaries. An always-false premise and a premise that merely misses exact fit are different problems.
        </p>
      </article>
    </section>
    <.reading_note
      id="edu-domain-primer"
      title="“Every input” has a domain."
      question="In ∀ x : α, P x, which inputs does x range over?"
      answer="All values of the stated type α. Further premises can limit which inputs receive the promised conclusion. Check both against the payment requirement."
    >
      <p>
        Read the opening of section 4.1, “The Universal Quantifier,” in <a href="https://lean-lang.org/theorem_proving_in_lean4/Quantifiers-and-Equality/">Quantifiers and Equality</a>.
        Skip equality proofs and the remaining chapter for now.
      </p>
    </.reading_note>
    <div class="edu-section-head">
      <div>
        <p class="edu-eyebrow">Follow the same claim</p><h2>Where could the argument go wrong?</h2>
      </div>
    </div>
    <div class="edu-pipeline" role="group" aria-label="Verification pipeline steps">
      <button
        :for={p <- @pipeline}
        type="button"
        phx-click="pipeline"
        phx-value-step={p.number}
        aria-pressed={to_string(@active.number == p.number)}
        aria-controls="edu-proof-detail"
        class={["edu-pipeline-step", @active.number == p.number && "active"]}
      ><span>{p.tag}</span><strong>{p.name}</strong></button>
    </div>
    <section id="edu-proof-detail" class="edu-pipeline-detail" aria-live="polite">
      <div>
        <p class="edu-eyebrow">{@active.name}</p><h2>{@active.headline}</h2><p>
          {@active.explanation}
        </p>
      </div>
      <aside>
        <h3>What can go wrong</h3><p>{@active.risk}</p><code>{@active.source}</code>
      </aside>
    </section>
    <details class="edu-disclosure" id="edu-proof-body">
      <summary>Reading the proof body</summary>
      <div class="edu-disclosure-content">
        <p>
          Tactics help construct a proof. Names such as <code>omega</code>, <code>cases</code>
          and <code>induction</code>
          describe proof work; they do not choose the payment policy.
        </p>
        <p>The PO-A2 law refers to this proof:</p>
        <pre><code>exact Elixir.HoldLedger.ProofContracts.«po_a2/3» s key amount requires</code></pre>
        <.reading_note
          id="edu-syntax-primer"
          title="Recognize the parts of a Lean definition."
          question="In def add1 (n : Nat) : Nat := n + 1, where are the input type and function body?"
          answer="The n : Nat annotation gives the input type. The Nat after the parentheses gives the result type. The expression after := is the function body."
        >
          <p>
            Read the first annotations in
            <a href="https://lean-lang.org/functional_programming_in_lean/Getting-to-Know-Lean/Types/">Types</a>
            and the first examples in <a href="https://lean-lang.org/functional_programming_in_lean/Getting-to-Know-Lean/Functions-and-Definitions/">Functions and Definitions</a>.
            Focus on <code>:</code>, <code>:=</code>, arguments and result types; skip the exercises and later features.
          </p>
        </.reading_note>
        <p>
          For a policy review, concentrate on the statement, called definitions, domain and assumptions. For a proof-only change, first confirm that the statement and other review-sensitive source really are unchanged.
        </p>
        <p class="edu-source-note">
          Review rules: <code>guides/human_review.md</code>. The source snippet above is not a fresh proof run.
        </p>
        <a class="edu-inline-link" href="/glossary?q=axiom">Look up proof assumptions →</a>
      </div>
    </details>
    <.next_links
      one="/lens/po_a2"
      one_title="Review a changed precondition"
      two="/assurance"
      two_title="Check the evidence behind a proof"
    />
    """
  end

  defp assurance(assigns) do
    evidence = [
      %{
        id: "catalog-evidence",
        label: "Registration",
        question: "Which statement is in the catalog?",
        meaning: "A claim ID points to a source declaration and its intended purpose.",
        scope: "Registration alone does not report checker acceptance."
      },
      %{
        id: "example-evidence",
        label: "Example",
        question: "What happens in this situation?",
        meaning:
          "The payment walkthrough executes the local ledger. The mutation and policy directories explain existing source examples without running them.",
        scope: "One example covers that situation, not every possible input."
      },
      %{
        id: "case-evidence",
        label: "Single-case check",
        question: "What does this claim accept here?",
        meaning:
          "The evaluator checks an input and output against the supported source-bound claim.",
        scope:
          "It may reject the output, accept it or say nothing because the premise is false. A successful case is not a universal proof."
      },
      %{
        id: "source-evidence",
        label: "Source reading",
        question: "What does the statement actually say?",
        meaning: "Read the law, theorem and relevant definitions in the recorded source.",
        scope:
          "A source link helps you inspect meaning; it does not establish a kernel dependency or checker result."
      },
      %{
        id: "focused-evidence",
        label: "Focused elaboration",
        question: "Did this selected Lean work elaborate?",
        meaning:
          "A focused tool run can help develop or diagnose a particular statement or proof.",
        scope:
          "Its report covers the work it ran. It may not include every check required for full acceptance."
      },
      %{
        id: "formal-evidence",
        label: "Full acceptance report",
        question: "Did the required checks accept these sources?",
        meaning:
          "Inspect source identity, exported statements, allowed axioms and the outcomes of all required checkers.",
        scope:
          "The report establishes its stated formal scope. Policy suitability and real-world assumptions still need review."
      }
    ]

    assigns = assign(assigns, :evidence, evidence)

    ~H"""
    <.intro
      eyebrow="Evidence · meaning and scope"
      heading="Check what the evidence covers."
      description="A catalog entry, an example and a completed formal report answer different questions. Read the kind of evidence beside each result, then check that its scope matches your question."
    />
    <section class="edu-evidence-list" aria-label="Kinds of evidence">
      <article :for={item <- @evidence} id={item.id}>
        <span class="edu-evidence-label">{item.label}</span>
        <div>
          <h2>{item.question}</h2><p>{item.meaning}</p><p class="edu-evidence-scope">{item.scope}</p>
        </div>
      </article>
    </section>
    <.reading_note
      id="edu-kernel-primer"
      title="What does Lean's kernel check?"
      question="Does an accepted proof show that the statement matches the payment policy?"
      answer="No. It establishes the formal claim under its assumptions. Review the statement, the source translation and the payment requirement separately. A real processor also needs evidence that it satisfies the model's assumptions."
    >
      <p>
        Lean checks the formal proof against the formal statement. The translation and the
        intended payment requirement still need their own review.
      </p>
      <p>
        Read “The Kernel” in <a href="https://lean-lang.org/doc/reference/latest/Elaboration-and-Compilation/">Elaboration and Compilation</a>.
        In <a href="https://lean-lang.org/doc/reference/latest/ValidatingProofs/">Validating Proofs</a>, read the opening distinction
        between proof validity and statement meaning, then “Printing Axioms.” Advanced checker commands can wait.
      </p>
    </.reading_note>
    <aside class="edu-assurance-note">
      <div>
        <h2>Match the report to the code.</h2><p>
          A report for different source bytes does not establish acceptance of the current claim. Open the source and report together when reviewing a change.
        </p>
      </div>
      <a href="/lab">Inspect source and evidence in Case Lab →</a>
    </aside>
    <section class="edu-trust-boundary" id="model-boundary" aria-labelledby="edu-boundary-title">
      <p class="edu-eyebrow">Outside the pure model</p>
      <h2 id="edu-boundary-title">The processor and storage need their own evidence.</h2>
      <p>
        A pure transition can request an authorization or void. That output does not show that the work reached the processor or completed there.
      </p>
      <div class="edu-boundary-questions">
        <article>
          <h3>Will a terminal key stay final remotely?</h3><p>
            The processor must honor permanent terminal fencing, including delayed requests. The ledger's own handling of late replies does not establish that remote property.
          </p>
        </article>
        <article>
          <h3>What actually survived the crash?</h3><p>
            The runtime relies on synced journal inputs. A model of replay does not by itself establish the durability of the storage carrying those inputs.
          </p>
        </article>
        <article>
          <h3>What does a reply establish?</h3><p>
            A transport acknowledgment is not an approval. Trusted processor outcomes and confirmations have specific meanings in the model.
          </p>
        </article>
      </div>
      <p class="edu-source-note">
        Sources: <code>guides/specification.md</code>, <code>guides/processors.md</code>
        and <code>guides/verification.md</code>.
      </p>
    </section>
    <.next_links
      one="/lens/po_exposure_retain"
      one_title="Review when capacity may be released"
      two="/repository"
      two_title="Find the evidence-related source"
    />
    """
  end

  defp repository(assigns) do
    sections = [
      %{
        title: "Decide what should happen",
        description: "Start with the policy, then use the independent Spec and the review rules.",
        entries: [
          %{
            id: "policy-source",
            title: "Payment-hold policy",
            path: "guides/specification.md",
            explanation:
              "The state shape, event behavior and conditions for keeping or releasing capacity.",
            link: "/guarantees",
            action: "Read the requirements"
          },
          %{
            id: "spec-source",
            title: "Independent behavioral Spec",
            path: "lib/hold_ledger/spec.ex",
            explanation:
              "Expected transitions and predicates such as request_eligible?, implemented separately from Ledger.",
            link: "/proofs",
            action: "Read a predicate in context"
          },
          %{
            id: "review-rules",
            title: "Human review rules",
            path: "guides/human_review.md",
            explanation:
              "How to inspect a statement change, distinguish proof-only work and record unresolved questions.",
            link: "/lens/po_a2",
            action: "Practice a review"
          }
        ]
      },
      %{
        title: "Read the implementation and claims",
        description: "Keep the code, its stated properties and the registration record distinct.",
        entries: [
          %{
            id: "ledger-source",
            title: "Pure ledger",
            path: "lib/hold_ledger/ledger.ex",
            explanation:
              "State transitions that return a new state, a result and requested effects.",
            link: "/system",
            action: "Explore the system"
          },
          %{
            id: "claim-source",
            title: "Elixir laws and Lean models",
            path: "test/laws/ · test/support/lean/",
            explanation: "The actual statements, proof references and supporting formal models.",
            link: "/atlas",
            action: "Find a claim"
          },
          %{
            id: "registry-source",
            title: "Claim registry and verification guide",
            path: "verification/laws.json · guides/verification.md",
            explanation:
              "Registered claims, supported verification commands and the evidence required for acceptance.",
            link: "/assurance",
            action: "Read the evidence guide"
          }
        ]
      },
      %{
        title: "Inspect runtime assumptions",
        description: "Follow what has to happen outside a pure state transition.",
        entries: [
          %{
            id: "runtime-source",
            title: "Journal, server and effect execution",
            path: "lib/hold_ledger/",
            explanation:
              "Input persistence, recovery and attempts to carry out requested effects.",
            link: "/atlas?family=Composite+%26+recovery",
            action: "Read recovery claims"
          },
          %{
            id: "processor-source",
            title: "Processor contract",
            path: "guides/processors.md",
            explanation:
              "The remote properties an adapter must attest to, including permanent terminal fencing.",
            link: "/assurance#model-boundary",
            action: "Review the external assumptions"
          }
        ]
      },
      %{
        title: "Try a concrete challenge",
        description:
          "Use repository examples to connect a statement to behavior it should catch.",
        entries: [
          %{
            id: "witness-examples",
            title: "Witnesses and ordinary tests",
            path: "test/hold_ledger_witness_test.exs · test/",
            explanation:
              "Concrete inputs and traces for checking what happens in selected cases.",
            link: "/lab",
            action: "Explore a case"
          },
          %{
            id: "mutation-examples",
            title: "Deliberately broken implementations",
            path: "mutants/",
            explanation:
              "Named mutations describe a wrong behavior, the input that exposes it and the claims that catch it.",
            link: "#mutation-example-directory",
            action: "Browse the mutation examples"
          },
          %{
            id: "review-exercises",
            title: "Payment-hold review exercises",
            path: "guides/payment_hold_review_exercises.md",
            explanation:
              "P01–P08 provide review cases grounded in the policy. Claim Lens presents two interactive studies.",
            link: "#policy-exercise-directory",
            action: "Browse the policy exercises"
          }
        ]
      }
    ]

    examples = Education.examples()

    assigns =
      assign(assigns,
        sections: sections,
        mutations: Enum.filter(examples, &(&1["kind"] == "mutation")),
        exercises: Enum.filter(examples, &(&1["kind"] == "exercise"))
      )

    ~H"""
    <.intro
      eyebrow="Reference · repository map"
      heading="Find the source for your question."
      description="Use the paths below in your checkout. The links beside them open the related explanation or tool in this app."
    />
    <section :for={section <- @sections} class="edu-repository-section">
      <div class="edu-section-head">
        <div>
          <h2>{section.title}</h2><p>{section.description}</p>
        </div>
      </div>
      <div class="edu-repository-map">
        <article :for={entry <- section.entries} class="edu-repo-item" id={entry.id}>
          <div>
            <h3>{entry.title}</h3><p>{entry.explanation}</p><code>{entry.path}</code>
          </div>
          <a href={entry.link}>{entry.action} <span aria-hidden="true">→</span></a>
        </article>
      </div>
    </section>
    <section class="edu-example-directory" id="mutation-example-directory">
      <div class="edu-section-head">
        <div>
          <p class="edu-eyebrow">M1–M10 · deliberate source faults</p><h2>Mutation examples</h2>
        </div>
      </div>
      <p class="edu-source-note">
        Each M example changes a source implementation outside the default ledger. Read the
        input, required result and deliberate fault together. These cards describe the source;
        they do not run the mutation.
      </p>
      <div class="edu-example-grid">
        <.example_card :for={example <- @mutations} example={example} />
      </div>
    </section>
    <section class="edu-example-directory" id="policy-exercise-directory">
      <div class="edu-section-head">
        <div>
          <p class="edu-eyebrow">P01–P08 · payment-policy exercises</p><h2>Policy exercises</h2>
        </div>
      </div>
      <p class="edu-source-note">
        Each P example pairs an input with a proposed output for review against the policy.
        P08 is a correct local cancellation. The input details show the existing source fixture,
        not a new execution result.
      </p>
      <div class="edu-example-grid">
        <.example_card :for={example <- @exercises} example={example} />
      </div>
    </section>
    <.next_links
      one="/glossary"
      one_title="Look up a source term"
      two="/lab"
      two_title="Try a case in the workbench"
    />
    """
  end

  attr :terms, :list, required: true
  attr :query, :string, required: true
  attr :count, :integer, required: true

  defp glossary(assigns) do
    ~H"""
    <.intro
      eyebrow="Reference · glossary"
      heading="Look up a term."
      description="Find its plain meaning, a concrete example from this repository and the source to read next. The same definitions appear in contextual help."
    />
    <.form
      for={to_form(%{"q" => @query})}
      id="edu-glossary-filter"
      phx-change="filter_terms"
      class="edu-search"
    >
      <.input
        id="edu-term-query"
        type="search"
        name="q"
        value={@query}
        label="Find a term or meaning"
        placeholder="Try requires, unknown, idempotency…"
        phx-debounce="180"
        class="edu-filter-input"
      />
      <span role="status">{length(@terms)} of {@count} terms</span>
    </.form>
    <.reading_directory />
    <div class="edu-glossary-grid" id="edu-glossary-results">
      <article :for={term <- @terms} id={"term-" <> term["id"]} class="edu-term-card">
        <span :if={term["level"]} class="learning-term-level">{String.capitalize(term["level"])}</span>
        <h2>{term["term"]}</h2>
        <p class="edu-term-meaning">{term["short"]}</p>
        <div :if={term["why_it_matters"]} class="learning-term-purpose">
          <h3>Why it matters</h3><p>{term["why_it_matters"]}</p>
        </div>
        <div class="edu-term-example">
          <h3>In this repository</h3><p>{term["example"]}</p>
        </div>
        <details class="edu-term-detail">
          <summary>More context and source</summary>
          <p>{term["detail"]}</p>
          <div :if={term["limit"]} class="learning-term-limit">
            <h3>Keep its scope in view</h3><p>{term["limit"]}</p>
          </div>
          <code data-source-path={term["source_path"]}>{term["source_path"]}</code>
          <ul
            :if={term["lookup"] not in [nil, []]}
            class="learning-term-lookups"
            aria-label="Further reading"
          >
            <li :for={reference <- term["lookup"]}>
              <a href={reference["url"]}>{reference["label"]} →</a>
            </li>
          </ul>
        </details>
        <a href={term["link"]} aria-label={"See " <> term["term"] <> " in context"}>See in context →</a>
      </article>
    </div>
    <div :if={@terms == []} class="edu-empty">
      <h2>No matching terms.</h2><p>
        Try a shorter phrase or clear the search to browse all definitions.
      </p><.link patch="/glossary">Show all terms →</.link>
    </div>
    <.next_links
      one="/atlas"
      one_title="Find a claim using these terms"
      two="/proofs"
      two_title="Practice reading a statement"
    />
    """
  end

  defp reading_directory(assigns) do
    ~H"""
    <details class="edu-disclosure edu-reading-directory" id="edu-reading-directory">
      <summary>Optional background reading</summary>
      <div class="edu-reading-directory-grid">
        <article>
          <h2>Payment holds and retries</h2>
          <p>
            Start with the <a href="/start">100¢ walkthrough</a>
            and the <a href="/system">system guide</a>.
          </p>
          <p>
            Read the opening of Stripe's
            <a href="https://docs.stripe.com/payments/place-a-hold-on-a-payment-method">authorization holds</a>
            and <a href="https://docs.stripe.com/api/idempotent_requests">idempotent requests</a>.
            Focus on authorization versus capture and retrying with the same key. Skip API examples.
          </p>
          <p class="edu-source-note">
            This repository's permanent identity and fencing assumptions are defined separately in its processor contract.
          </p>
        </article>
        <article>
          <h2>Formal statements</h2>
          <p>
            Start with the <a href="/proofs">statement-reading guide</a>
            or <a href="/translation">follow an Elixir law into Lean</a>.
            The repository's
            <a href={Education.crash_course_url()}>formal verification crash course</a>
            develops the same example at more depth.
          </p>
          <p>
            Read sections 3.1–3.3 of
            <a href="https://lean-lang.org/theorem_proving_in_lean4/Propositions-and-Proofs/">Propositions and Proofs</a>
            and the opening of 4.1 in <a href="https://lean-lang.org/theorem_proving_in_lean4/Quantifiers-and-Equality/">Quantifiers and Equality</a>.
            Focus on <code>Prop</code>, <code>→</code>, <code>∧</code>
            and <code>∀</code>; skip constructing proofs.
          </p>
        </article>
        <article>
          <h2>Lean syntax</h2>
          <p>
            Read the first annotations in
            <a href="https://lean-lang.org/functional_programming_in_lean/Getting-to-Know-Lean/Types/">Types</a>
            and the first examples in <a href="https://lean-lang.org/functional_programming_in_lean/Getting-to-Know-Lean/Functions-and-Definitions/">Functions and Definitions</a>.
            Focus on arguments, result types, <code>:</code>
            and <code>:=</code>. Exercises and later language features can wait.
          </p>
        </article>
        <article>
          <h2>What the kernel checks</h2>
          <p>Start with the <a href="/assurance">evidence guide</a>.</p>
          <p>
            Read “The Kernel” in <a href="https://lean-lang.org/doc/reference/latest/Elaboration-and-Compilation/">Elaboration and Compilation</a>,
            then the opening and “Printing Axioms” in <a href="https://lean-lang.org/doc/reference/latest/ValidatingProofs/">Validating Proofs</a>.
            Advanced checker commands can wait.
          </p>
        </article>
      </div>
    </details>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :question, :string, required: true
  attr :answer, :string, required: true
  slot :inner_block, required: true

  defp reading_note(assigns) do
    ~H"""
    <aside class="edu-reading-note" id={@id} aria-labelledby={@id <> "-title"}>
      <div>
        <p class="edu-reading-note-label">Optional background</p>
        <h2 id={@id <> "-title"}>{@title}</h2>
        {render_slot(@inner_block)}
      </div>
      <details class="edu-self-check">
        <summary><span>Check your understanding</span>{@question}</summary>
        <p>{@answer}</p>
      </details>
    </aside>
    """
  end

  attr :one, :string, required: true
  attr :one_title, :string, required: true
  attr :two, :string, required: true
  attr :two_title, :string, required: true

  defp next_links(assigns) do
    ~H"""
    <nav class="edu-next-links" aria-label="Recommended next pages">
      <p>Where to go next</p><a href={@one}>{@one_title} <span aria-hidden="true">↗</span></a><a href={
        @two
      }>{@two_title} <span aria-hidden="true">↗</span></a>
    </nav>
    """
  end
end
