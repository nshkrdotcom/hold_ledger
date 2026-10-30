defmodule HoldLedgerReviewWeb.ClaimLensLive do
  @moduledoc "Source-linked, deliberately bounded semantic-gap experiments."
  use HoldLedgerReviewWeb, :live_view

  alias HoldLedgerReview.{ClaimLens, ProofReading}
  alias HoldLedgerReview.ProofReading.Links

  @decisions ~w(unresolved concern expected no_change)

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
       decision: "unresolved",
       review_form: to_form(%{"text" => ""}, as: :review)
     )}
  end

  @impl true
  def handle_params(%{"slug" => slug}, _, socket) do
    with {:ok, study} <- ClaimLens.study(slug),
         {:ok, reading} <- ProofReading.document(slug),
         {:ok, line} <- ClaimLens.policy_line(study, reading) do
      same_study? = socket.assigns.study && socket.assigns.study.slug == slug
      witness = if(same_study?, do: socket.assigns.witness_id, else: study.default_witness)
      variation = if(same_study?, do: socket.assigns.variation_id, else: study.default_variation)

      case ClaimLens.observe(slug, witness, variation) do
        {:ok, observation} ->
          {:noreply,
           assign(socket,
             study: study,
             reading: reading,
             policy_line: line,
             observation: observation,
             witness_id: witness,
             variation_id: variation,
             selected_clause:
               if(same_study?, do: socket.assigns.selected_clause, else: study.connection),
             decision: if(same_study?, do: socket.assigns.decision, else: "unresolved"),
             review_form:
               if(same_study?,
                 do: socket.assigns.review_form,
                 else: to_form(%{"text" => ""}, as: :review)
               )
           )}

        _ ->
          {:noreply,
           socket
           |> clear_study()
           |> put_flash(:error, "Pointwise observation is unavailable.")}
      end
    else
      _ ->
        {:noreply,
         socket
         |> clear_study()
         |> put_flash(:error, "Claim or governing policy source unavailable.")}
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

  defp handle_lens_event("decision", %{"choice" => value}, socket) when value in @decisions,
    do: {:noreply, assign(socket, decision: value)}

  defp handle_lens_event("decision", _, socket), do: {:noreply, socket}

  defp handle_lens_event("review_note", %{"review" => %{"text" => text}}, socket)
       when is_binary(text) and byte_size(text) <= 2000,
       do: {:noreply, assign(socket, review_form: to_form(%{"text" => text}, as: :review))}

  defp handle_lens_event("review_note", _, socket), do: {:noreply, socket}

  defp change_observation(%{assigns: %{study: nil}} = socket, _, _),
    do: {:noreply, socket}

  defp change_observation(socket, witness, variation) do
    case ClaimLens.observe(socket.assigns.study.slug, witness, variation) do
      {:ok, observation} ->
        {:noreply,
         assign(socket,
           witness_id: witness,
           variation_id: variation,
           observation: observation,
           decision: "unresolved",
           review_form: to_form(%{"text" => ""}, as: :review)
         )}

      _ ->
        {:noreply,
         socket
         |> clear_study()
         |> put_flash(:error, "This curated observation is unavailable.")}
    end
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
        observed_links: observed_links
      )

    ~H"""
    <Layouts.app flash={@flash}>
      <section :if={!@study || !@observation || !@reading} id="lens-unavailable" role="status">
        Source-bound Claim Lens reading is unavailable.
      </section>
      <div :if={@study && @observation && @reading} id="claim-lens">
        <header class="lens-hero">
          <div class="lens-hero-top">
            <span class="lens-kicker">VERIFICATION / INTERACTIVE SEMANTICS</span>
            <nav id="lens-modes" class="lens-modes" aria-label="Review experiences">
              <a href={~p"/claims/#{@study.slug}"}>Case Lab</a>
              <a href={~p"/lens/#{@study.slug}"} aria-current="page">Claim Lens</a>
              <a href={~p"/claims/#{@study.slug}?compare=open"}>Compare versions</a>
            </nav>
          </div>
          <h1>What does this claim actually protect?</h1>
          <p>Change a <strong>hypothetical</strong> precondition, inspect a real pointwise witness,
            and compare it with the independently written payment policy. No Lean proof is rerun.</p>
        </header>

        <div class="lens-layout">
          <aside class="lens-rail" aria-label="Claim and witness selection">
            <section class="lens-panel lens-index" id="lens-study-picker">
              <span class="lens-step">01 / Choose a guarantee</span>
              <nav aria-label="Curated obligations" class="lens-choice-stack">
                <a
                  :for={study <- @studies}
                  href={~p"/lens/#{study.slug}"}
                  aria-current={if(study.slug == @study.slug, do: "page")}
                  class={["lens-study-link", study.slug == @study.slug && "selected"]}
                >
                  <strong>{study.title}</strong>
                  <small>{study.question}</small>
                </a>
              </nav>
              <p class="lens-footnote">
                Two curated source-bound laws, not the full 49-claim catalog.
                <a href={~p"/claims/#{@study.slug}"}>All claims in Case Lab</a>
              </p>
            </section>
            <section class="lens-panel" id="lens-witness-picker">
              <span class="lens-step">02 / Challenge the boundary</span>
              <h2>Select a concrete witness</h2>
              <div class="lens-choice-stack" role="group" aria-label="Pointwise witness">
                <button
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
                The same selected witness is checked against both preconditions.
              </p>
            </section>
          </aside>

          <div class="lens-main">
            <section class="lens-panel lens-policy" id="lens-policy">
              <div class="lens-panel-head">
                <span class="lens-step">03 / Intended requirement</span>
                <span class="lens-evidence">Policy · independently authored</span>
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
                <span class="lens-step">04 / Interrogate the formal claim</span>
                <span class="lens-evidence">Hypothetical edit · not applied to source</span>
              </div>
              <h2>What if the precondition changed?</h2>
              <div class="lens-variations" role="group" aria-label="Hypothetical edit">
                <button
                  :for={variation <- @study.variations}
                  id={"lens-variation-#{variation.id}"}
                  type="button"
                  aria-pressed={to_string(variation.id == @variation_id)}
                  class={["lens-variation", variation.id == @variation_id && "selected"]}
                  phx-click="variation"
                  phx-value-id={variation.id}
                >{variation.title}</button>
              </div>
              <p class="lens-detail">{@observation.variation.detail}</p>
              <div class="lens-code-diff" id="lens-clause-diff">
                <div><span>Authored requires · excerpt</span><code>{@study.clause}</code></div>
                <div>
                  <span>Illustrative precondition</span><code>{if @observation.changed?,
                    do: @study.changed_clause,
                    else: @study.clause}</code>
                </div>
              </div>
              <p class="lens-footnote" id="lens-model-scope">The illustrative side is a bounded
                pointwise model of this stated edit, not a generated law or a rechecked Lean theorem.
                The full source contract is visible in the proof-reading column.</p>
            </section>

            <section class="lens-panel lens-results" id="lens-results">
              <div class="lens-panel-head">
                <span class="lens-step">05 / Compare two independent judgments</span>
                <span class="lens-evidence">One input and one candidate output</span>
              </div>
              <h2>Does the alternative get through?</h2>
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
              <div class="lens-verdict-grid">
                <article id="lens-policy-verdict" class="lens-verdict">
                  <span class="lens-evidence">Governing policy · curated expectation</span>
                  <strong>{policy_label(@observation.witness.policy)}</strong>
                  <p>{@observation.witness.reason}</p>
                </article>
                <article id="lens-baseline-verdict" class="lens-verdict">
                  <span class="lens-evidence">Current law · source-bound pointwise evaluator</span>
                  <strong>{verdict_label(@observation.baseline.status)}</strong>
                  <p>{baseline_description(@observation.baseline.status)}</p>
                </article>
                <article id="lens-hypothetical-verdict" class="lens-verdict">
                  <span class="lens-evidence">Illustrative precondition · pointwise only</span>
                  <strong>{verdict_label(@observation.alternative.status)}</strong>
                  <p>
                    {if @observation.changed?,
                      do: "Unchanged promise under the illustrated altered domain.",
                      else: "No claim-level change is assumed."}
                  </p>
                </article>
              </div>
              <div id="lens-gap" class="lens-gap" role="status">
                <span class="lens-step">Review insight</span>
                <strong>{gap_title(@observation)}</strong>
                <p>{gap_text(@observation)}</p>
              </div>
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

            <section class="lens-panel lens-human" id="lens-review">
              <div class="lens-panel-head"><span class="lens-step">06 / Human challenge</span>
                <span class="lens-evidence">Local draft · not saved or submitted</span></div>
              <h2>What would you tell the author?</h2>
              <p>
                Classify the <em>illustration</em>, not the proof status. Acceptance is not automatically a defect.
              </p>
              <div class="lens-decisions" role="group" aria-label="Provisional human decision">
                <button
                  id="lens-decision-concern"
                  phx-click="decision"
                  type="button"
                  phx-value-choice="concern"
                  aria-pressed={to_string(@decision == "concern")}
                >Possible guarantee loss</button>
                <button
                  id="lens-decision-expected"
                  phx-click="decision"
                  type="button"
                  phx-value-choice="expected"
                  aria-pressed={to_string(@decision == "expected")}
                >Expected exclusion</button>
                <button
                  id="lens-decision-no-change"
                  phx-click="decision"
                  type="button"
                  phx-value-choice="no_change"
                  aria-pressed={to_string(@decision == "no_change")}
                >No claim change</button>
                <button
                  id="lens-decision-unresolved"
                  phx-click="decision"
                  type="button"
                  phx-value-choice="unresolved"
                  aria-pressed={to_string(@decision == "unresolved")}
                >Need more evidence</button>
              </div>
              <.form for={@review_form} id="lens-review-form" phx-change="review_note">
                <.input
                  field={@review_form[:text]}
                  type="textarea"
                  maxlength="2000"
                  label="Your explanation · which requirement or boundary matters?"
                />
              </.form>
              <p class="lens-footnote" id="lens-draft-state">
                Draft classification: {decision_label(@decision)}.
                No session write, source edit, agent request, or proof execution occurs here.
              </p>
              <p class="lens-footnote">
                Known mutation exercise: <code>{@study.mutant}/mutant.patch</code>
                and <code>{@study.mutant}/counterexample_test.exs</code>.
                These repository fixtures are examples, not a test run by this page.
              </p>
              <p>
                <a href={~p"/claims/#{@study.slug}"} class="lens-cta">Explore this rule in Case Lab →</a>
              </p>
            </section>
          </div>

          <aside class="lens-reading" aria-label="Source and verification evidence">
            <section class="lens-panel" id="lens-source-contract">
              <span class="lens-step">Source / Elixir law</span>
              <h2>The authored contract</h2>
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
                  class={["lens-clause", @selected_clause == link["id"] && "selected"]}
                  phx-click="clause"
                  phx-value-id={link["id"]}
                  aria-pressed={to_string(@selected_clause == link["id"])}
                >
                  <span>{link["phase"]} · {link["id"]}</span>
                  <code>{link["expression"]}</code>
                </button>
              </div>
              <p :if={@selected_link} id="lens-selected-clause" class="lens-detail">
                {@selected_link["relation"]}
              </p>
              <p :if={@selected_link && @selected_link["availability"] != "available"} role="status">
                Reviewed source link unavailable: {@selected_link["availability"]}
              </p>
              <p :if={@observed_link} id="lens-observed-path" class="lens-footnote">
                Matching observed AST path:
                <code>{@observed_link["phase"]}:{@observed_link["path"]}</code>
                · one bound witness, not a kernel dependency.
              </p>
              <p
                :if={@selected_link && !@observed_link}
                id="lens-observed-unavailable"
                class="lens-footnote"
              >
                No unique observed AST link for this candidate and binding; source reading remains separate.
              </p>
            </section>
            <section class="lens-panel" id="lens-lean-reading">
              <span class="lens-step">Source / Lean text</span>
              <h2>What the theorem states</h2>
              <article :for={decl <- @reading["declarations"]} class="lens-lean-decl">
                <p class="lens-evidence">{decl["path"]}:{decl["line"]} · {decl["status"]}</p>
                <pre tabindex="0" aria-label={"Lean statement #{decl["name"]}"}>{decl["header"]}</pre>
                <a
                  :if={source_href(@reading, decl["path"])}
                  href={source_href(@reading, decl["path"])}
                  target="_blank"
                  rel="noopener"
                >Read Lean declaration</a>
              </article>
              <div :if={@selected_steps != []} id="lens-proof-steps">
                <h3>Reviewed source passages for selected clause</h3>
                <article :for={step <- @selected_steps} class="lens-step-reading">
                  <span>{step["title"]} · line {step["line"]}</span>
                  <p>{step["reason"]}</p>
                  <pre tabindex="0" aria-label={"Lean passage: #{step["title"]}"}>{step["code"]}</pre>
                </article>
              </div>
              <p :if={@selected_steps == []} class="lens-footnote">
                No current reviewed source passages for this selection.
              </p>
              <p class="lens-footnote">
                These are source excerpts, <strong>not</strong>
                recorded Lean tactic goals or dependency footprints.
              </p>
            </section>
            <section class="lens-panel" id="lens-evidence-status">
              <span class="lens-step">Evidence / Provenance</span>
              <h2>What is actually checked?</h2>
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
                <dt>Clause → Lean</dt><dd>{@reading["reading_status"]} · source link only</dd>
                <dt>Focused elaboration</dt><dd>{@reading["focused"]["status"]}</dd>
                <dt>Required formal gate</dt><dd id="lens-formal-status">
                  {@reading["formal"]["status"]}
                </dd>
                <dt>Hypothetical edit proof</dt><dd>Not run / unavailable</dd>
                <dt>Lean tactic goals</dt><dd>Not collected / unavailable</dd>
              </dl>
              <p class="lens-footnote">
                Even a source-matched accepted Lean theorem does not prove that its policy is correct. Any proof repair requires a real source comparison and full-scoped verification.
              </p>
              <p :if={@reading["omits"]} class="lens-footnote">Scope omitted: {@reading["omits"]}</p>
            </section>
          </aside>
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
      decision: "unresolved",
      review_form: to_form(%{"text" => ""}, as: :review)
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
  defp verdict_label(:doesnt_apply), do: "Outside the claim's domain"
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

  defp decision_label("concern"), do: "possible guarantee loss"
  defp decision_label("expected"), do: "expected exclusion"
  defp decision_label("no_change"), do: "no claim change"
  defp decision_label(_), do: "needs more evidence"
end
