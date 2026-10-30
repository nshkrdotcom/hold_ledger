defmodule HoldLedgerReviewWeb.ClaimLensLive do
  @moduledoc "Source-linked, deliberately bounded semantic-gap experiments."
  use HoldLedgerReviewWeb, :live_view

  alias HoldLedgerReview.{ClaimLens, ProofReading}
  alias HoldLedgerReview.ProofReading.Links

  # Review judgments are user assertions, not evaluations or formal receipts.
  @decisions ~w(unresolved concern expected no_change covers permits_forbidden overconstrains)
  @review_fields ~w(policy_anchor contract_clause witness scope_limit text)

  @impl true
  def mount(_, _, socket) do
    {:ok,
     assign(socket,
       page_title: "Hold Ledger · Claim Lens",
       studies: ClaimLens.studies(),
       study: nil,
       reading: nil,
       policy_line: nil,
       observation: nil,
       witness_id: nil,
       variation_id: nil,
       selected_clause: nil,
       decision: nil,
       mode: "challenge",
       submitted_review: nil,
       coverage: [],
       review_form: empty_review_form()
     )}
  end

  @impl true
  def handle_params(%{"slug" => slug} = params, _, socket) do
    # The reviewer-first experience is the default. Exploration requires an
    # explicit mode, so the first view does not leak pointwise answers.
    mode = if params["mode"] == "explore", do: "explore", else: "challenge"
    same_study? = socket.assigns.study && socket.assigns.study.slug == slug
    same_attempt? = same_study? && socket.assigns.mode == mode

    with {:ok, study} <- ClaimLens.study(slug),
         {:ok, reading} <- ProofReading.document(slug),
         {:ok, line} <- ClaimLens.policy_line(study, reading),
         witness = if(same_study?, do: socket.assigns.witness_id, else: study.default_witness),
         variation =
           if(same_study?, do: socket.assigns.variation_id, else: study.default_variation),
         {:ok, observation} <- ClaimLens.observe(slug, witness, variation),
         {:ok, coverage} <- ClaimLens.coverage(slug, variation) do
      socket =
        assign(socket,
          study: study,
          reading: reading,
          policy_line: line,
          observation: observation,
          coverage: coverage,
          witness_id: witness,
          variation_id: variation,
          mode: mode,
          selected_clause:
            if(same_study?, do: socket.assigns.selected_clause, else: study.connection)
        )

      {:noreply, if(same_attempt?, do: socket, else: reset_attempt(socket))}
    else
      _ -> unavailable(socket)
    end
  end

  @impl true
  def handle_event(event, params, socket) do
    with %{slug: slug} = study <- socket.assigns.study,
         {:ok, reading} <- ProofReading.document(slug),
         true <- reading["reading_current"],
         {:ok, line} <- ClaimLens.policy_line(study, reading) do
      handle_lens_event(event, params, assign(socket, reading: reading, policy_line: line))
    else
      _ ->
        {:noreply,
         socket
         |> clear_study()
         |> put_flash(:error, "Claim or governing policy source unavailable.")}
    end
  end

  defp handle_lens_event("witness", %{"id" => id}, socket) do
    change_observation(socket, id, socket.assigns.variation_id)
  end

  defp handle_lens_event("variation", %{"id" => id}, socket) do
    change_observation(socket, socket.assigns.witness_id, id)
  end

  defp handle_lens_event("clause", %{"id" => id}, socket) do
    if socket.assigns.reading &&
         Enum.any?(socket.assigns.reading["connections"], &(&1["id"] == id)) do
      {:noreply, assign(socket, selected_clause: id)}
    else
      {:noreply, socket}
    end
  end

  defp handle_lens_event("decision", %{"choice" => value}, socket) when value in @decisions do
    if socket.assigns.submitted_review,
      do: {:noreply, socket},
      else: {:noreply, assign(socket, decision: value)}
  end

  defp handle_lens_event("decision", _, socket), do: {:noreply, socket}

  defp handle_lens_event("review_note", %{"review" => fields}, socket) when is_map(fields) do
    with nil <- socket.assigns.submitted_review,
         {:ok, values} <- review_values(fields) do
      {:noreply, assign(socket, review_form: to_form(values, as: :review))}
    else
      _ -> {:noreply, socket}
    end
  end

  defp handle_lens_event("review_note", _, socket), do: {:noreply, socket}

  defp handle_lens_event("reveal", %{"review" => fields}, socket) when is_map(fields) do
    case review_values(fields) do
      {:ok, values} -> confirm_review(socket, values)
      _ -> {:noreply, socket}
    end
  end

  defp handle_lens_event("reveal", _, socket), do: {:noreply, socket}

  defp handle_lens_event("try_again", _, socket), do: {:noreply, reset_attempt(socket)}

  defp confirm_review(
         %{assigns: %{mode: "challenge", decision: decision, submitted_review: nil}} = socket,
         values
       )
       when decision in @decisions do
    {:noreply,
     assign(socket,
       submitted_review: %{
         decision: decision,
         text: values["text"],
         policy_anchor: values["policy_anchor"],
         contract_clause: values["contract_clause"],
         witness: values["witness"],
         scope_limit: values["scope_limit"]
       },
       review_form: to_form(values, as: :review)
     )}
  end

  defp confirm_review(socket, _values), do: {:noreply, socket}

  defp empty_review_form do
    to_form(Map.new(@review_fields, &{&1, ""}), as: :review)
  end

  defp review_values(fields) do
    values = Map.new(@review_fields, &{&1, Map.get(fields, &1, "")})

    if Enum.all?(values, fn {key, value} ->
         is_binary(value) and byte_size(value) <= review_limit(key)
       end) do
      {:ok, values}
    else
      {:error, :invalid_draft}
    end
  end

  defp review_limit("text"), do: 2000
  defp review_limit(_field), do: 500

  defp change_observation(socket, witness, variation) do
    slug = socket.assigns.study.slug

    with {:ok, observation} <- ClaimLens.observe(slug, witness, variation),
         {:ok, coverage} <- ClaimLens.coverage(slug, variation) do
      {:noreply,
       socket
       |> assign(
         witness_id: witness,
         variation_id: variation,
         observation: observation,
         coverage: coverage,
         selected_clause:
           if(observation.changed?,
             do: socket.assigns.study.connection,
             else: socket.assigns.selected_clause
           )
       )
       |> reset_attempt()}
    else
      _ -> unavailable(socket)
    end
  end

  defp reset_attempt(socket) do
    assign(socket,
      decision: nil,
      submitted_review: nil,
      review_form: empty_review_form()
    )
  end

  defp unavailable(socket) do
    {:noreply,
     socket
     |> clear_study()
     |> put_flash(:error, "Claim or governing policy source unavailable.")}
  end

  @impl true
  def render(assigns) do
    selected =
      if assigns.reading,
        do: Enum.find(assigns.reading["connections"], &(&1["id"] == assigns.selected_clause))

    selected_steps =
      if selected && assigns.reading && selected["availability"] == "available" do
        Enum.map(selected["steps"], &Enum.at(assigns.reading["proof_steps"], &1))
        |> Enum.reject(&is_nil/1)
      else
        []
      end

    observed_links =
      if assigns.reading && assigns.observation do
        Links.project(
          assigns.reading,
          %{"explanation" => assigns.observation.explanation},
          0,
          "candidate"
        )
      else
        %{links: [], unavailable: []}
      end

    observation_link =
      if selected,
        do: Enum.find(observed_links.links, &(&1["id"] == selected["id"]))

    assigns =
      assign(assigns,
        selected_link: selected,
        selected_steps: selected_steps,
        observed_link: observation_link,
        observed_links: observed_links,
        feedback?: assigns.mode == "explore" or not is_nil(assigns.submitted_review)
      )

    ~H"""
    <Layouts.app flash={@flash}>
      <section :if={!@study || !@observation || !@reading} id="lens-unavailable" role="status">
        Source-bound Claim Lens reading is unavailable.
      </section>
      <div :if={@study && @observation && @reading} id="claim-lens">
        <div class="edu-workbench-intro" id="lens-education-bridge">
          <div><strong>New to formal review?</strong>
            <p>Learn the system first; this view tests how an authored claim relates to independent policy, not whether the payment processor is safe.</p>
          </div>
          <a href="/proofs">Understand the claim →</a>
        </div>
        <header class="lens-hero">
          <div class="lens-hero-top">
            <span class="lens-kicker">VERIFICATION / INTERACTIVE SEMANTICS</span>
            <nav id="lens-modes" class="lens-modes" aria-label="Review experiences">
              <a href={~p"/claims/#{@study.slug}"}>Case Lab</a>
              <a href={~p"/lens/#{@study.slug}"} aria-current="page">Claim Lens</a>
              <a href={~p"/claims/#{@study.slug}?compare=open"}>Compare versions</a>
            </nav>
          </div>
          <div id="lens-demo-scope" class="lens-demo-scope">
            <strong>Claim Lens · 2 guided examples</strong>
            <p>
              These two demos use real claims and curated cases to show the review workflow.
              Other claims are available in Case Lab; this guided flow is only built for these two.
            </p>
            <nav aria-label="Choose a guided example">
              <a
                :for={study <- @studies}
                href={lens_path(study.slug, @mode)}
                aria-current={if(study.slug == @study.slug, do: "page")}
              >
                {study.title}
              </a>
            </nav>
          </div>
          <div class="lens-hero-content">
            <div>
              <span class="lens-overline">SPECIFICATION REVIEW / 001</span>
              <h1>Decide what the claim <em>really</em> protects.</h1>
              <p>Start from independent policy. Inspect a concrete near-miss. Record your
                own interpretation <strong>before</strong> seeing a pointwise conclusion.</p>
            </div>
            <div class="lens-hero-aside" aria-label="Review scope">
              <span class="lens-hero-aside-icon" aria-hidden="true">↗</span>
              <strong>Human judgment first.</strong>
              <span>Formal acceptance and policy adequacy answer different questions.</span>
              <small>Curated scenario · no new verification run</small>
            </div>
          </div>
          <nav id="lens-exercise-modes" class="lens-exercise-modes" aria-label="Learning mode">
            <.link patch={~p"/lens/#{@study.slug}"} aria-current={if @mode == "challenge", do: "page"}>
              <strong>01 · Review first</strong><small>Commit an initial classification</small>
            </.link>
            <.link
              patch={~p"/lens/#{@study.slug}?mode=explore"}
              aria-current={if @mode == "explore", do: "page"}
            >
              <strong>02 · Explore freely</strong><small>Open answers for learning and QA</small>
            </.link>
          </nav>
          <p :if={@mode == "challenge"} id="lens-challenge-scope" class="lens-footnote">
            Practice, not a blinded or scored assessment. Explore or earlier feedback may already
            have shown this example. Your initial answer stays only in this LiveView.
          </p>
          <div class="lens-trust-strip" aria-label="Evidence boundaries">
            <span><b>Policy requirement</b> Human-authored intent</span>
            <span><b>Pointwise evaluation</b> This input and output only</span>
            <span><b>Hypothetical</b> Unchecked by Lean</span>
          </div>
          <details id="lens-evidence-legend" class="lens-details lens-legend">
            <summary data-edu-hint="Distinguish policy, a pointwise result, source reading, checked artifacts, and unverified external assumptions.">Understand the five evidence levels</summary>
            <ol class="lens-legend-list">
              <li>
                <strong>Policy Requirement</strong>
                — independently authored intended behavior, not a theorem.
              </li>
              <li>
                <strong>Pointwise Evaluation</strong> — one bound input/output, not a universal proof.
              </li>
              <li>
                <strong>Reviewed Source Reading</strong> — text navigation, not a kernel dependency.
              </li>
              <li>
                <strong>Checked Formal Artifact</strong>
                — only if a report matches the exact source and declared scope.
              </li>
              <li>
                <strong>Unverified External Assumption</strong>
                — processor behavior and durability require separate evidence.
              </li>
            </ol>
            <p>No proof is rerun, no AI request is made, and no payments are sent by this page.</p>
          </details>
        </header>

        <div class="lens-layout">
          <aside class="lens-rail" aria-label="Claim and witness selection">
            <section class="lens-panel lens-index" id="lens-study-picker">
              <span class="lens-step">01 / Review subject</span>
              <h2>Choose an example</h2>
              <nav aria-label="Curated obligations" class="lens-choice-stack">
                <a
                  :for={study <- @studies}
                  href={lens_path(study.slug, @mode)}
                  aria-current={if(study.slug == @study.slug, do: "page")}
                  class={["lens-study-link", study.slug == @study.slug && "selected"]}
                >
                  <strong>{study.title}</strong>
                  <small :if={@feedback?}>{study.question}</small>
                </a>
              </nav>
              <p class="lens-footnote">
                These are the only two guided examples. Browse the full 49-claim catalog in Case Lab.
                <a href={~p"/claims/#{@study.slug}"}>All claims in Case Lab</a>
              </p>
            </section>
            <section class="lens-panel" id="lens-witness-picker">
              <span class="lens-step">02 / Near-miss selector</span>
              <h2 data-edu-term="witness" tabindex="0">Change one boundary</h2>
              <div class="lens-choice-stack" role="group" aria-label="Pointwise witness">
                <button
                  data-edu-hint="Choose one concrete input boundary. This is an authored comparison, not a new theorem proof."
                  :for={witness <- @study.witnesses}
                  id={"lens-witness-#{witness.id}"}
                  type="button"
                  class={["lens-choice", witness.id == @witness_id && "selected"]}
                  aria-pressed={to_string(witness.id == @witness_id)}
                  phx-click="witness"
                  phx-value-id={witness.id}
                >
                  <strong>{witness.title}</strong><small>{witness.description}</small>
                </button>
              </div>
              <p class="lens-footnote">
                Each witness keeps the same law and candidate-output shape. Selecting another witness resets your draft.
              </p>
            </section>
          </aside>

          <div class="lens-main">
            <section class="lens-panel lens-policy" id="lens-policy">
              <div class="lens-panel-head">
                <span class="lens-step">03 / Independent intent</span>
                <span class="lens-evidence lens-provenance" data-kind="policy">Policy Requirement</span>
              </div>
              <h2>{@study.title}</h2>
              <blockquote>{@study.policy}</blockquote>
              <p class="lens-footnote">
                {@study.policy_section} ·
                <a
                  :if={source_href(@reading, "guides/specification.md")}
                  href={source_href(@reading, "guides/specification.md")}
                  target="_blank"
                  rel="noopener"
                >Read governing specification<span :if={@policy_line}>, line {@policy_line}</span></a>
              </p>
            </section>

            <section class="lens-panel lens-perturb" id="lens-perturbation">
              <div class="lens-panel-head">
                <span class="lens-step">04 / Contract boundary</span>
                <span class="lens-evidence lens-provenance" data-kind="hypothetical">HYPOTHETICAL: Unchecked by Lean</span>
              </div>
              <h2 data-edu-term="requires" tabindex="0">What if the precondition changed?</h2>
              <div class="lens-variations" role="group" aria-label="Hypothetical edit">
                <button
                  data-edu-hint="Select an illustrative contract edit. All changes here are hypothetical and unchecked by Lean."
                  :for={variation <- @study.variations}
                  id={"lens-variation-#{variation.id}"}
                  type="button"
                  aria-pressed={to_string(variation.id == @variation_id)}
                  class={["lens-variation", variation.id == @variation_id && "selected"]}
                  phx-click="variation"
                  phx-value-id={variation.id}
                >{variation_title(variation, @mode)}</button>
              </div>
              <p :if={@feedback?} class="lens-detail">{@observation.variation.detail}</p>
              <p
                :if={@variation_id == "proof_only" && @feedback?}
                id="lens-proof-control"
                class="lens-detail lens-null-control"
              >
                <strong>No semantic delta in specification.</strong>
                Requires and expects are identical in this proof-body-only illustration.
                The edited proof has not been checked.
              </p>
              <p
                :if={@variation_id == "proof_only" && !@feedback?}
                id="lens-proof-control"
                class="lens-detail"
              >
                Proof-body-only change proposed. Compare the authored and illustrative clauses;
                no revised proof was run. Determine whether its guarantee changed.
              </p>
              <div class="lens-code-diff" id="lens-clause-diff">
                <div><span>Authored requires · excerpt</span><code>{@study.clause}</code></div>
                <div>
                  <span>Illustrative precondition</span><code>{if @observation.changed?,
                    do: @study.changed_clause,
                    else: @study.clause}</code>
                </div>
              </div>
              <p class="lens-footnote" id="lens-model-scope">
                The authored promise stays fixed. Expand the evidence library to read the complete source contract.
              </p>
            </section>

            <section
              class="lens-panel lens-case-brief"
              id="lens-case-brief"
              aria-label="Concrete case for human review"
            >
              <div class="lens-panel-head">
                <span class="lens-step">05 / Concrete test case</span>
                <span class="lens-evidence lens-provenance" data-kind="hypothetical">Curated alternative · unexecuted</span>
              </div>
              <h2>One event. Two possible outcomes.</h2>
              <div class="lens-witness-data">
                <div><span>Input event</span><code>{format_event(@observation.event)}</code></div>
                <div>
                  <span>Code returned</span><strong>{format_output(@observation.actual)}</strong>
                </div>
                <div>
                  <span>Challenged output · unexecuted</span><strong>{format_output(
                    @observation.candidate
                  )}</strong>
                </div>
              </div>
              <p class="lens-footnote">
                The code output is evaluated by the existing Ledger step function.
                The alternative is curated and unexecuted; this is not a new mutant run.
              </p>
            </section>

            <section class="lens-panel lens-human" id="lens-review">
              <div class="lens-panel-head">
                <span class="lens-step">06 / Commit your interpretation</span>
                <span class="lens-evidence lens-provenance" data-kind="human">Human judgment · local only</span>
              </div>
              <h2 data-edu-term="review" tabindex="0">What does the contract promise here?</h2>
              <p>
                Choose the best classification, then anchor it to the policy, claim,
                concrete witness and scope limit. No concern and uncertainty are valid conclusions.
              </p>
              <div class="lens-decisions" role="group" aria-label="Provisional human decision">
                <button
                  id="lens-decision-concern"
                  phx-click="decision"
                  disabled={not is_nil(@submitted_review)}
                  type="button"
                  phx-value-choice="concern"
                  aria-pressed={to_string(@decision == "concern")}
                >Excludes valid input <small>Possible guarantee loss</small></button>
                <button
                  id="lens-decision-expected"
                  phx-click="decision"
                  disabled={not is_nil(@submitted_review)}
                  type="button"
                  phx-value-choice="expected"
                  aria-pressed={to_string(@decision == "expected")}
                >Permitted by policy <small>Expected exclusion</small></button>
                <button
                  id="lens-decision-no-change"
                  phx-click="decision"
                  disabled={not is_nil(@submitted_review)}
                  type="button"
                  phx-value-choice="no_change"
                  aria-pressed={to_string(@decision == "no_change")}
                >No semantic delta <small>Proof-only control</small></button>
                <button
                  id="lens-decision-unresolved"
                  phx-click="decision"
                  disabled={not is_nil(@submitted_review)}
                  type="button"
                  phx-value-choice="unresolved"
                  aria-pressed={to_string(@decision == "unresolved")}
                >Insufficient evidence <small>Unresolved assumptions</small></button>
                <button
                  id="lens-decision-covers"
                  type="button"
                  phx-click="decision"
                  phx-value-choice="covers"
                  disabled={not is_nil(@submitted_review)}
                  aria-pressed={to_string(@decision == "covers")}
                >Covers intended policy <small>Scoped to this example</small></button>
                <button
                  id="lens-decision-permits-forbidden"
                  type="button"
                  phx-click="decision"
                  phx-value-choice="permits_forbidden"
                  disabled={not is_nil(@submitted_review)}
                  aria-pressed={to_string(@decision == "permits_forbidden")}
                >Permits forbidden output <small>Possible underconstraint</small></button>
                <button
                  id="lens-decision-overconstrains"
                  type="button"
                  phx-click="decision"
                  phx-value-choice="overconstrains"
                  disabled={not is_nil(@submitted_review)}
                  aria-pressed={to_string(@decision == "overconstrains")}
                >Overconstrains valid behavior <small>Possible false alarm</small></button>
              </div>
              <.form
                for={@review_form}
                id="lens-review-form"
                phx-change="review_note"
                phx-submit="reveal"
              >
                <div class="lens-argument-grid" aria-label="Four-part evidence argument">
                  <.input
                    field={@review_form[:policy_anchor]}
                    type="text"
                    maxlength="500"
                    disabled={not is_nil(@submitted_review)}
                    label="01 · Policy anchor"
                    placeholder="guides/specification.md · exact-fit admission"
                  />
                  <.input
                    field={@review_form[:contract_clause]}
                    type="text"
                    maxlength="500"
                    disabled={not is_nil(@submitted_review)}
                    label="02 · Contract provision"
                    placeholder="requires or expects clause"
                  />
                  <.input
                    field={@review_form[:witness]}
                    type="text"
                    maxlength="500"
                    disabled={not is_nil(@submitted_review)}
                    label="03 · Discriminating witness"
                    placeholder="100¢ request / 100¢ remaining"
                  />
                  <.input
                    field={@review_form[:scope_limit]}
                    type="text"
                    maxlength="500"
                    disabled={not is_nil(@submitted_review)}
                    label="04 · Limitation / assumption"
                    placeholder="Illustrative edit; not Lean checked"
                  />
                </div>
                <.input
                  field={@review_form[:text]}
                  type="textarea"
                  maxlength="2000"
                  disabled={not is_nil(@submitted_review)}
                  label="Your explanation · which requirement or boundary matters?"
                />
                <button
                  :if={@mode == "challenge" && !@submitted_review}
                  id="lens-confirm"
                  type="submit"
                  disabled={is_nil(@decision)}
                >
                  Confirm classification and reveal feedback
                </button>
              </.form>
              <div :if={@submitted_review} id="lens-initial-answer" role="status">
                <strong>Your initial classification: {decision_label(@submitted_review.decision)}.</strong>
                <div class="lens-argument-summary">
                  <p :if={@submitted_review.policy_anchor != ""}>
                    <b>Policy:</b> {@submitted_review.policy_anchor}
                  </p>
                  <p :if={@submitted_review.contract_clause != ""}>
                    <b>Claim:</b> {@submitted_review.contract_clause}
                  </p>
                  <p :if={@submitted_review.witness != ""}>
                    <b>Witness:</b> {@submitted_review.witness}
                  </p>
                  <p :if={@submitted_review.scope_limit != ""}>
                    <b>Limitation:</b> {@submitted_review.scope_limit}
                  </p>
                  <p :if={@submitted_review.text != ""}><b>Reasoning:</b> {@submitted_review.text}</p>
                </div>
                <p>
                  Feedback is now available. This provisional answer is not a saved review decision.
                </p>
                <button
                  id="lens-copy-packet"
                  type="button"
                  phx-hook="CopyReview"
                  data-packet={review_packet(@submitted_review, @study, @observation)}
                >
                  Copy local Markdown argument
                </button>
                <span id="lens-copy-status" class="lens-copy-status" role="status" aria-live="polite"></span>
                <a href="#lens-results">Read the comparison and coverage</a>
                <button type="button" id="lens-try-again" phx-click="try_again">Try again</button>
              </div>
              <p class="lens-footnote" id="lens-draft-state">
                Draft classification: {decision_label(@decision)}.
                No session write, source edit, agent request, or proof execution occurs here.
              </p>
              <details :if={@feedback?} id="lens-worked-challenge" class="lens-details">
                <summary>Worked challenge · exact input and candidate</summary>
                <p>
                  {@observation.witness.reason} {baseline_description(@observation.baseline.status)}
                </p>
                <p>
                  The candidate below is curated and unexecuted. It is not a result from running a mutant patch.
                </p>
                <pre tabindex="0" aria-label="Worked challenge values">{Jason.encode!(%{"before" => @observation.before, "event" => @observation.event, "computed" => @observation.actual, "candidate" => @observation.candidate}, pretty: true)}</pre>
                <p class="lens-footnote">
                  Related mutation exercise: <code>{@study.mutant}/mutant.patch</code>
                  and <code>{@study.mutant}/counterexample_test.exs</code>. These files are references, not a browser test run.
                </p>
              </details>
              <p>
                <a href={~p"/claims/#{@study.slug}"} class="lens-cta">Explore this rule in Case Lab →</a>
              </p>
            </section>

            <section class="lens-panel lens-results" id="lens-results">
              <div class="lens-panel-head">
                <span class="lens-step">07 / Feedback · after classification</span>
                <span class="lens-evidence lens-provenance" data-kind="pointwise">Bounded, pointwise evidence</span>
              </div>
              <h2 data-edu-term="policy-gap" tabindex="0">Policy expectation vs. contract permission</h2>

              <p :if={!@feedback?} id="lens-feedback-withheld" class="lens-feedback-withheld">
                Automated verdicts, source-bound applicability and any worked answer are deliberately
                withheld. <a href="#lens-review">Record your initial classification</a> to reveal
                the policy and pointwise judgments.
              </p>
              <%= if @feedback? do %>
                <div class="lens-verdict-grid">
                  <article id="lens-policy-verdict" class="lens-verdict">
                    <span class="lens-evidence lens-provenance" data-kind="policy">Policy Requirement · independent</span>
                    <strong>{policy_label(@observation.witness.policy)}</strong>
                    <p>{@observation.witness.reason}</p>
                  </article>
                  <article id="lens-baseline-verdict" class="lens-verdict">
                    <span class="lens-evidence lens-provenance" data-kind="pointwise">Current law · Pointwise Evaluation</span>
                    <strong>{verdict_label(@observation.baseline.status)}</strong>
                    <p>{baseline_description(@observation.baseline.status)}</p>
                  </article>
                  <article
                    id="lens-hypothetical-verdict"
                    class="lens-verdict"
                    data-applicability={
                      if @observation.alternative.status == :doesnt_apply, do: "excluded"
                    }
                  >
                    <span class="lens-evidence lens-provenance" data-kind="hypothetical">Hypothetical · unchecked by Lean</span>
                    <strong>{verdict_label(@observation.alternative.status)}</strong>
                    <p>
                      {hypothetical_description(@observation)}
                    </p>
                  </article>
                </div>
                <div id="lens-gap" class="lens-gap" role="status">
                  <span class="lens-step">Semantic gap · human assessment still required</span>
                  <strong>{gap_title(@observation)}</strong>
                  <p>{gap_text(@observation)}</p>
                </div>
                <section id="lens-coverage" class="lens-coverage" aria-label="Witness input coverage">
                  <h3>Which inputs are covered?</h3>
                  <p class="lens-footnote">
                    Applicability only: authored evaluator versus the hypothetical model.
                  </p>
                  <div class="lens-coverage-grid">
                    <button
                      :for={row <- @coverage}
                      id={"lens-coverage-#{row.id}"}
                      type="button"
                      phx-click="witness"
                      phx-value-id={row.id}
                      aria-pressed={to_string(row.id == @witness_id)}
                      data-change={coverage_change(row)}
                    >
                      <strong>{row.title}</strong>
                      <span>Authored: {coverage_label(row.original)}</span>
                      <span>Hypothetical: {coverage_label(row.hypothetical)}</span>
                      <small>{coverage_change_label(row)}</small>
                    </button>
                  </div>
                </section>
              <% end %>
              <details id="lens-pointwise-details" class="lens-details">
                <summary>Show exact pointwise input and outputs</summary>
                <div class="lens-json-grid">
                  <div>
                    <h3>Before and event</h3><pre tabindex="0">{Jason.encode!(%{"before" => @observation.before, "event" => @observation.event}, pretty: true)}</pre>
                  </div>
                  <div>
                    <h3>Computed result</h3><pre tabindex="0">{Jason.encode!(@observation.actual, pretty: true)}</pre>
                  </div>
                  <div>
                    <h3>Alternative (not run)</h3><pre tabindex="0">{Jason.encode!(@observation.candidate, pretty: true)}</pre>
                  </div>
                </div>
              </details>
            </section>
            <section :if={@feedback?} id="lens-near-misses" class="lens-panel lens-near-misses">
              <div class="lens-panel-head">
                <span class="lens-step">Contrast studio / 3 curated examples</span>
                <span class="lens-evidence lens-provenance" data-kind="hypothetical">Exercises P02 / P05 / P08 · not executed here</span>
              </div>
              <h2>Same action, different reason.</h2>
              <p>Use these authored guide examples to separate a missing outside request,
                premature release, and a legitimate local cancellation. They are not
                new pointwise evaluations or proof results.</p>
              <div class="lens-case-atlas">
                <details name="lens-case-pair" open>
                  <summary>
                    <span>P02</span><strong>Remote void request missing</strong><small>Authorized → voiding</small>
                  </summary>
                  <dl>
                    <div>
                      <dt>Capacity</dt><dd>100¢ / 1 slot retained</dd>
                    </div>
                    <div>
                      <dt>Remote effect</dt><dd class="lens-emphasis">None requested</dd>
                    </div>
                    <div>
                      <dt>Decision boundary</dt><dd>Retention alone is insufficient</dd>
                    </div>
                  </dl>
                </details>
                <details name="lens-case-pair">
                  <summary>
                    <span>P05</span><strong>Capacity released too soon</strong><small>Authorized → voided</small>
                  </summary>
                  <dl>
                    <div>
                      <dt>Capacity</dt><dd class="lens-emphasis">0¢ / 0 slots, too early</dd>
                    </div>
                    <div>
                      <dt>Remote effect</dt><dd>Void requested</dd>
                    </div>
                    <div>
                      <dt>Decision boundary</dt><dd>
                        An emitted effect is not terminal confirmation
                      </dd>
                    </div>
                  </dl>
                </details>
                <details name="lens-case-pair">
                  <summary>
                    <span>P08</span><strong>Legitimate local release</strong><small>Reserved → voided</small>
                  </summary>
                  <dl>
                    <div>
                      <dt>Capacity</dt><dd>0¢ / 0 slots, permitted</dd>
                    </div>
                    <div>
                      <dt>Remote effect</dt><dd>No effect needed; never dispatched</dd>
                    </div>
                    <div>
                      <dt>Decision boundary</dt><dd>
                        Correct acceptance is as important as catching a fault
                      </dd>
                    </div>
                  </dl>
                </details>
              </div>
              <p class="lens-footnote">
                Source: <code>guides/payment_hold_review_exercises.md</code>
                and curated <code>priv/scenarios/P02.json</code>, <code>P05.json</code>, <code>P08.json</code>.
              </p>
            </section>
          </div>

          <details id="lens-evidence-drawer" class="lens-evidence-drawer" open={@mode == "explore"}>
            <summary>
              <span><b>08 / Evidence library</b>
              · Claim source, Lean reading and verification provenance</span>
              <small>Secondary depth · source navigation is not a proof dependency</small>
            </summary>
            <aside class="lens-reading" aria-label="Source and verification evidence">
              <section class="lens-panel" id="lens-source-contract">
                <span class="lens-step">Source / Elixir law</span>
                <h2 data-edu-term="law" tabindex="0">The authored contract</h2>
                <p class="lens-evidence">{@reading["law"]["file"]}</p>
                <dl :if={@reading["contract"]["status"] == "source_read"} class="lens-contract">
                  <dt>REQUIRES</dt><dd tabindex="0" aria-label="Authored precondition">
                    <code>{@reading["contract"]["requires"]}</code>
                  </dd>
                  <dt>EXPECTS</dt><dd tabindex="0" aria-label="Authored postcondition">
                    <code>{@reading["contract"]["expects"]}</code>
                  </dd>
                </dl>
                <p :if={@reading["contract"]["status"] != "source_read"} role="status">
                  Audited Elixir expression unavailable.
                </p>
                <a
                  :if={source_href(@reading, @observation.source_path)}
                  href={source_href(@reading, @observation.source_path)}
                  target="_blank"
                  rel="noopener"
                >Read complete registered law</a>
              </section>
              <section class="lens-panel" id="lens-source-links">
                <span class="lens-step">Source / Reviewed correspondences</span>
                <h2>Select a clause to inspect</h2>
                <div class="lens-clause-list" role="group" aria-label="Source-linked clauses">
                  <button
                    :for={link <- @reading["connections"]}
                    id={"lens-clause-#{link["id"]}"}
                    class={[
                      "lens-clause",
                      @selected_clause == link["id"] && "selected",
                      @observation.changed? && @study.connection == link["id"] && "lens-clause-edited"
                    ]}
                    phx-click="clause"
                    phx-value-id={link["id"]}
                    aria-pressed={to_string(@selected_clause == link["id"])}
                  >
                    <span>{link["phase"]} · {link["id"]}</span>
                    <code>{link["expression"]}</code>
                  </button>
                </div>
                <p :if={@selected_link && @feedback?} id="lens-selected-clause" class="lens-detail">
                  {@selected_link["relation"]}
                </p>
                <p :if={@selected_link && @selected_link["availability"] != "available"} role="status">
                  Reviewed source link unavailable for the current source.
                </p>
                <p :if={@feedback? && @observed_link} id="lens-observed-path" class="lens-footnote">
                  Matching observed AST path:
                  <code>{@observed_link["phase"]}:{@observed_link["path"]}</code>
                  · one bound witness.
                </p>
                <p
                  :if={@feedback? && @selected_link && !@observed_link}
                  id="lens-observed-unavailable"
                  class="lens-footnote"
                >
                  No unique observed AST link for this candidate and binding; source reading remains separate.
                </p>
              </section>
              <section class="lens-panel" id="lens-lean-reading">
                <span class="lens-step">Source / Lean text</span>
                <h2 data-edu-term="theorem" tabindex="0">What the theorem states</h2>
                <article :for={decl <- @reading["declarations"]} class="lens-lean-decl">
                  <p class="lens-evidence">
                    {decl["path"]}:{decl["line"]} · {evidence_label(decl["status"])}
                  </p>
                  <pre tabindex="0" aria-label={"Lean statement #{decl["name"]}"}>{decl["header"]}</pre>
                  <a
                    :if={source_href(@reading, decl["path"])}
                    href={source_href(@reading, decl["path"])}
                    target="_blank"
                    rel="noopener"
                  >Read Lean declaration</a>
                </article>
                <div :if={@feedback? && @selected_steps != []} id="lens-proof-steps">
                  <h3>Reviewed source passages for selected clause</h3>
                  <article :for={step <- @selected_steps} class="lens-step-reading">
                    <span>{step["title"]} · line {step["line"]}</span>
                    <p>{step["reason"]}</p>
                    <pre tabindex="0" aria-label={"Lean passage: #{step["title"]}"}>{step["code"]}</pre>
                  </article>
                </div>
                <p :if={@feedback? && @selected_steps == []} class="lens-footnote">
                  No current reviewed source passages for this selection.
                </p>
              </section>
              <section class="lens-panel" id="lens-evidence-status">
                <span class="lens-step">Evidence / Provenance</span>
                <h2 data-edu-term="proof-status" tabindex="0">What is actually checked?</h2>
                <dl class="lens-evidence-grid">
                  <dt>Pointwise baseline</dt><dd>
                    Audited Elixir law · {@observation.baseline.bindings_tested} source binding(s)
                  </dd>
                  <dt>Law source SHA-256</dt><dd>
                    <code>{String.slice(@observation.baseline[:source_sha256] || "", 0, 16)}</code>
                  </dd>
                  <dt>Evaluator ID</dt><dd>
                    <code>{String.slice(@observation.baseline[:evaluator_id] || "", 0, 16)}</code>
                  </dd>
                  <dt>Clause → Lean</dt><dd>
                    {evidence_label(@reading["reading_status"])} · source link only
                  </dd>
                  <dt>Focused elaboration</dt><dd>{evidence_label(@reading["focused"]["status"])}</dd>
                  <dt>Required formal gate</dt><dd id="lens-formal-status">
                    {evidence_label(@reading["formal"]["status"])}
                  </dd>
                  <dt>Hypothetical edit proof</dt><dd>Not run / unavailable</dd>
                  <dt>Lean tactic goals</dt><dd>Not collected / unavailable</dd>
                </dl>
                <p class="lens-footnote">
                  Even a source-matched accepted Lean theorem does not prove that its policy is correct. Any proof repair requires a real source comparison and full-scoped verification.
                </p>
                <p :if={@reading["omits"]} class="lens-footnote">
                  Scope omitted: {@reading["omits"]}
                </p>
                <div id="lens-premise-ledger" class="lens-premise-ledger">
                  <h3>External premises to establish separately</h3>
                  <p class="lens-footnote">
                    Personal reading checklist only; checking a box never verifies a processor guarantee.
                  </p>
                  <label><input type="checkbox" />
                  Permanent terminal fencing against delayed authorization</label>
                  <label><input type="checkbox" /> Truthful remote decline vs. local acknowledgment</label>
                  <label><input type="checkbox" />
                  Durable journal synchronization and replay assumptions</label>
                  <p class="lens-footnote lens-provenance" data-kind="external">
                    Unverified External Assumption · not established by Lean source text.
                  </p>
                </div>
              </section>
            </aside>
          </details>
        </div>
      </div>
    </Layouts.app>
    """
  end

  defp clear_study(socket) do
    assign(socket,
      study: nil,
      reading: nil,
      policy_line: nil,
      observation: nil,
      witness_id: nil,
      variation_id: nil,
      selected_clause: nil,
      decision: nil,
      submitted_review: nil,
      coverage: [],
      review_form: empty_review_form()
    )
  end

  defp source_href(reading, path) do
    case Enum.find(reading["sources"], &(&1["path"] == path)) do
      nil -> nil
      source -> "/claims/#{reading["slug"]}/source/#{source["id"]}/#{source["sha256"]}"
    end
  end

  defp format_event(%{"type" => "request", "amount" => amount, "key" => key}),
    do: "request(#{key}, #{amount}¢)"

  defp format_event(%{"type" => type, "key" => key}), do: "#{type}(#{key})"
  defp format_event(_), do: "Unknown event"

  defp format_output(%{"after" => after_state, "result" => result}),
    do:
      "#{result} · #{after_state["used_amount"]}¢ reserved · #{after_state["used_holds"]} slot(s)"

  defp policy_label(:allowed), do: "Policy permits this output"
  defp policy_label(:forbidden), do: "Policy forbids this output"

  defp verdict_label(:catches), do: "Rejects this output"
  defp verdict_label(:allows_here), do: "Allows this output here"
  defp verdict_label(:doesnt_apply), do: "Doesn't apply"
  defp verdict_label(:cant_check), do: "Cannot evaluate"

  defp baseline_description(:catches),
    do: "The current source law excludes this candidate on the selected binding."

  defp baseline_description(:allows_here),
    do: "The current source law accepts the candidate on this bound input."

  defp baseline_description(:doesnt_apply),
    do: "The source precondition is false; the postcondition is not evaluated."

  defp baseline_description(:cant_check), do: "No pointwise acceptance conclusion is available."

  defp gap_title(%{baseline: %{status: :cant_check}}), do: "No evaluation conclusion"
  defp gap_title(%{alternative: %{status: :cant_check}}), do: "Illustration unavailable"
  defp gap_title(%{changed?: false}), do: "No claim-level change in this illustration"

  defp gap_title(%{
         witness: %{policy: :forbidden},
         alternative: %{status: :doesnt_apply},
         baseline: %{status: :catches}
       }),
       do: "Potential loss of required coverage"

  defp gap_title(%{witness: %{policy: :allowed}, alternative: %{status: :catches}}),
    do: "Potential overconstraint of permitted behavior"

  defp gap_title(%{witness: %{policy: :forbidden}, alternative: %{status: :allows_here}}),
    do: "Potentially unprotected forbidden output"

  defp gap_title(_), do: "Inspect the boundary; no defect inferred"

  defp gap_text(%{baseline: %{status: :cant_check}}),
    do:
      "Source-bound evaluation is unavailable. Neither an untested model nor an observed result establishes acceptance."

  defp gap_text(%{alternative: %{status: :cant_check}}),
    do:
      "The hypothetical model could not be compared reliably with the baseline. No claim-delta conclusion follows."

  defp gap_text(%{changed?: false}),
    do:
      "The authored assumptions and promise were not changed in this example. A harmless proof-body-only edit is a false-alarm control, not evidence that the edited proof still checks."

  defp gap_text(%{
         witness: %{policy: :forbidden},
         alternative: %{status: :doesnt_apply},
         baseline: %{status: :catches}
       }),
       do:
         "The current claim rejects this forbidden output, but the hypothetical narrower requires excludes the input completely. Losing a case from the domain is different from proving its output safe."

  defp gap_text(%{witness: %{policy: :allowed}, alternative: %{status: :catches}}),
    do:
      "The widened hypothetical claim rejects legitimate terminal release because its promise still requires retention. This is a counterexample to the altered assertion, not a bug in the original policy or code."

  defp gap_text(_),
    do:
      "The pointwise comparison covers only this concrete input. Check other cases and the actual source diff before judging a guarantee."

  # Do not put the case answer in a tab label before the human has decided.
  # The exact changed source clause stays visible for independent inspection.
  defp variation_title(%{id: "original", title: title}, _mode), do: title
  defp variation_title(%{id: "proof_only"}, "challenge"), do: "Proof-source edit"
  defp variation_title(_variation, "challenge"), do: "Proposed precondition"
  defp variation_title(variation, _mode), do: variation.title

  defp lens_path(slug, "explore"), do: ~p"/lens/#{slug}?mode=explore"
  defp lens_path(slug, _), do: ~p"/lens/#{slug}"

  defp hypothetical_description(%{alternative: %{status: :doesnt_apply}}),
    do: "The hypothetical claim says nothing about this input."

  defp hypothetical_description(%{changed?: true}),
    do: "The authored promise is checked under the hypothetical precondition."

  defp hypothetical_description(_), do: "Requires and expects are unchanged."

  defp coverage_label(true), do: "Covered"
  defp coverage_label(false), do: "Doesn't apply"
  defp coverage_change(%{original: true, hypothetical: false}), do: "removed"
  defp coverage_change(%{original: false, hypothetical: true}), do: "added"
  defp coverage_change(_), do: "same"
  defp coverage_change_label(%{original: true, hypothetical: false}), do: "Coverage removed"
  defp coverage_change_label(%{original: false, hypothetical: true}), do: "Coverage added"
  defp coverage_change_label(_), do: "Same coverage"

  defp evidence_label("source_declaration_not_elaborated_evidence"),
    do: "Source text · not proof-check evidence"

  defp evidence_label("missing_or_ambiguous_declaration"),
    do: "Declaration unavailable or ambiguous"

  defp evidence_label("missing_or_stale"), do: "Unavailable · missing or out of date"
  defp evidence_label("not_supplied"), do: "No report supplied"
  defp evidence_label("current"), do: "Matches reviewed source"
  defp evidence_label("stale"), do: "Out of date for current source"
  defp evidence_label("elaborated"), do: "Focused elaboration completed · not full acceptance"
  defp evidence_label("full_catalog_checked"), do: "Full required catalog checked"
  defp evidence_label("selected_checked"), do: "Selected scope checked · not full catalog"
  defp evidence_label("development_only"), do: "Development proof evidence only"
  defp evidence_label("failed"), do: "Verification failed"
  defp evidence_label("incomplete"), do: "Verification incomplete or unavailable"
  defp evidence_label(_), do: "Unavailable · inspect the verification record"

  defp decision_label("concern"), do: "possible guarantee loss"
  defp decision_label("expected"), do: "expected exclusion"
  defp decision_label("no_change"), do: "no claim change"
  defp decision_label("unresolved"), do: "needs more evidence"
  defp decision_label("covers"), do: "covers intended policy (at this witness)"
  defp decision_label("permits_forbidden"), do: "permits forbidden output"
  defp decision_label("overconstrains"), do: "overconstrains valid behavior"
  defp decision_label(_), do: "not classified"

  # UI-only copy packet: locally authored argument, never a formal receipt.
  defp review_packet(review, study, observation) do
    """
    # Hold Ledger · provisional human review

    - Study: #{study.slug} · #{study.title}
    - Classification: #{decision_label(review.decision)}
    - Policy anchor: #{review.policy_anchor}
    - Contract clause: #{review.contract_clause}
    - Witness: #{review.witness}
    - Limitation / assumption: #{review.scope_limit}
    - Reasoning: #{review.text}
    - Concrete event: #{format_event(observation.event)}
    - Candidate: curated, unexecuted illustrative output
    - Formal status: hypothetical edit NOT checked by Lean

    Human interpretation only. No source revision, verification run, or
    processor result is certified by this note.
    """
  end
end
