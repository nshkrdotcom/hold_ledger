defmodule HoldLedgerReviewWeb.ReviewLive do
  use HoldLedgerReviewWeb, :live_view
  import HoldLedgerReviewWeb.SourceExcerpt
  alias HoldLedgerReview.{Packet, Session, Receipts}

  def mount(%{"case_id" => id}, _session, socket) do
    case Packet.build(id) do
      {:ok, p} ->
        {:ok,
         assign(socket,
           s: Session.new(p),
           error: nil,
           question_form: to_form(%{"question" => ""}),
           prediction_form: to_form(%{"note" => ""}),
           decision_form:
             to_form(%{
               "rationale" => "",
               "decision" => "insufficient_evidence",
               "scope" => "",
               "revision" => ""
             }),
           explanation_status: :idle
         )}

      {:error, reason} ->
        {:ok, assign(socket, s: nil, error: inspect(reason))}
    end
  end

  def handle_event("record_review", params, socket) do
    case Receipts.record(socket.assigns.s, params) do
      {:ok, id} ->
        {:noreply, push_navigate(socket, to: ~p"/review/receipts/#{id}")}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:error, inspect(reason))
         |> update(:s, &%{&1 | stale?: not Packet.current?(&1.packet)})}
    end
  end

  def handle_event("ask_explainer", %{"question" => question}, socket) do
    s = socket.assigns.s

    if s.prediction != nil and Session.text(question, 1000) != "" do
      socket = socket |> cancel_async(:explanation) |> assign(:explanation_status, :pending)

      {:noreply,
       start_async(socket, :explanation, fn ->
         {s.packet.packet_sha256, s.candidate,
          HoldLedgerReview.Explainer.explain(s.packet, question, %{candidate: s.candidate})}
       end)}
    else
      {:noreply,
       assign(socket, :error, "Reveal a case and enter a question of at most 1000 bytes.")}
    end
  end

  def handle_event(event, params, socket) do
    case Session.act(socket.assigns.s, event, params) do
      {:ok, s} ->
        socket =
          if event == "select_candidate",
            do: socket |> cancel_async(:explanation) |> assign(:explanation_status, :idle),
            else: socket

        {:noreply, assign(socket, s: s, error: nil)}

      {:error, reason} ->
        {:noreply, assign(socket, :error, inspect(reason))}
    end
  end

  def handle_async(:explanation, {:ok, {digest, candidate, result}}, socket) do
    s = socket.assigns.s

    if s.packet.packet_sha256 == digest and s.candidate == candidate do
      case result do
        {:ok, e} ->
          {:noreply,
           socket |> assign(:s, %{s | explanation: e}) |> assign(:explanation_status, :ready)}

        _ ->
          {:noreply, assign(socket, :explanation_status, :unavailable)}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_async(:explanation, _, socket),
    do: {:noreply, assign(socket, :explanation_status, :unavailable)}

  defp report_summary(p) do
    p.proof.report
    |> Map.take([
      "stage",
      "cache",
      "complete",
      "checker_claim",
      "release_complete",
      "execution",
      "source_changes_during_run",
      "obligation_coverage"
    ])
    |> Map.put(
      "case_laws",
      Map.take(p.proof.report["laws"] || %{}, Enum.map(p.case.laws, &elem(&1, 0)))
    )
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <p :if={@error} id="review-error" role="alert">{@error}</p>
      <%= if @s do %>
        <div class="review-heading">
          <div>
            <p class="eyebrow">Investigate a contract</p><h1>{@s.packet.case.title}</h1>
          </div><.link navigate={~p"/review"}>All cases</.link>
        </div>
        <p class="snapshot">
          Snapshot {String.slice(@s.packet.packet_sha256, 0, 16)} · checkout {String.slice(
            @s.packet.git_head,
            0,
            10
          )} · dirty: {to_string(@s.packet.dirty?)}
        </p>
        <p :if={@s.stale?} id="stale-source" role="alert">
          Sources changed. Reload for a new packet; this review cannot accept stale evidence.
        </p>
        <div class="workbench-grid">
          <section class="panel">
            <p class="eyebrow">From source</p><h2>Required behavior</h2><p>
              {@s.packet.case.question}
            </p>
            <button
              id="open-policy"
              phx-click="open_anchor"
              phx-value-id={@s.packet.case.id<>".policy"}
            >Open governing policy</button>
            <p>
              Policy and committed traces govern; agreement between Ledger and Spec does not settle policy.
            </p>
          </section>
          <section class="panel">
            <p class="eyebrow">Computed case</p><h2>Ledger workbench</h2><h3>Before</h3><pre>{inspect(@s.packet.case.before)}</pre><h3>
              Event
            </h3><pre>{inspect(@s.packet.case.event)}</pre>
            <%= if is_nil(@s.prediction) do %>
              <p>Predict before revealing the result. What should happen?</p>
              <.form for={@prediction_form} id="prediction-form" phx-submit="predict">
                <.input
                  field={@prediction_form[:note]}
                  type="textarea"
                  label="Your reason (optional)"
                  maxlength="500"
                />
                <button
                  :for={
                    choice <-
                      if(@s.packet.case.id == "exact_fit",
                        do: ~w(admit reject uncertain),
                        else: ~w(retain release uncertain)
                      )
                  }
                  id={"predict-"<>choice}
                  name="choice"
                  value={choice}
                >{choice}</button>
              </.form>
            <% else %>
              <p id="prediction-record">Your prediction: {@s.prediction} · {@s.note}</p>
              <div id="actual-output">
                <h3>Actual after / result / effects</h3><pre>{inspect(@s.packet.facts.actual,pretty: true)}</pre>
              </div>
              <p :if={@s.packet.facts.disputed?} role="alert">
                Disputed source: Ledger, independent Spec or policy fixture disagree. Human reconciliation required.
              </p>
              <p>
                Before → after counters: {elem(@s.packet.case.before, 2)} / {elem(
                  @s.packet.case.before,
                  3
                )} → {elem(elem(@s.packet.facts.actual, 0), 2)} / {elem(
                  elem(@s.packet.facts.actual, 0),
                  3
                )}. Inspect entry statuses and effects above.
              </p>
            <% end %>
          </section>
          <section class="panel">
            <p class="eyebrow">Original claim / proof lens</p><h2>What is maintained?</h2>
            <div :for={{slug, _, _} <- @s.packet.case.laws} class="law-row">
              <strong>{slug}</strong><p>
                Domain for this input: {if @s.packet.facts.domains[slug],
                  do: "qualifies",
                  else: "outside scope — claim does not apply"}
              </p>
              <button
                id={"law-"<>slug}
                phx-click="open_anchor"
                phx-value-id={@s.packet.case.id<>".law."<>slug}
              >requires / expects</button>
              <button phx-click="open_anchor" phx-value-id={@s.packet.case.id<>".lean."<>slug}>Shared Lean theorem</button>
            </div>
            <p :if={@s.packet.case.id == "timeout_unknown"}>
              po_b1_timeout proves validity preservation. Retention below is a concrete policy challenge, not a stronger theorem attributed to that law.
            </p>
            <p id="proof-status" class="evidence-status">
              Formal evidence: {to_string(@s.packet.proof.status)}
            </p><p>{@s.packet.proof.detail}</p>
            <details :if={@s.packet.proof.report} id="proof-report-detail">
              <summary>Recorded report scope, commands and log references</summary>
              <pre>{Jason.encode!(report_summary(@s.packet), pretty: true)}</pre>
            </details>
          </section>
        </div>
        <%= if @s.prediction do %>
          <section class="panel challenge">
            <p class="eyebrow">Try to break it</p><h2>Compare a wrong alternative</h2>
            <div class="button-row">
              <button
                :for={id <- Map.keys(@s.packet.facts.candidates) |> Enum.sort()}
                id={"candidate-"<>id}
                aria-pressed={to_string(@s.candidate == id)}
                phx-click="select_candidate"
                phx-value-id={id}
              >{String.replace(id, "_", " ")}</button>
            </div>
            <p id="branch-label">
              {if @s.candidate == "correct",
                do: "Actual local branch",
                else: "Counterfactual local branch — not a verified remote trace"}
            </p>
            <pre id="candidate-output">{inspect(@s.packet.facts.candidates[@s.candidate],pretty: true)}</pre>
            <h3>Hypothetical contract comparison</h3><p>
              Toggle concrete conclusions. This does not edit the law or run Lean.
            </p>
            <div class="button-row">
              <button
                :for={claim <- @s.packet.case.claims}
                id={"claim-"<>claim}
                aria-pressed={to_string(claim in @s.selected)}
                phx-click="toggle_claim"
                phx-value-id={claim}
              >{claim}</button>
            </div>
            <table id="predicate-matrix">
              <caption>Concrete predicates, not universal proof results</caption><thead>
                <tr>
                  <th>Candidate</th><th :for={claim <- @s.packet.case.claims}>{claim}</th><th>
                    All selected
                  </th>
                </tr>
              </thead><tbody>
                <tr :for={{id, row} <- Enum.sort(@s.packet.facts.matrix)} id={"matrix-"<>id}>
                  <th>{id}</th><td :for={claim <- @s.packet.case.claims}>{to_string(row[claim])}</td><td>
                    {if Session.passing?(@s, id), do: "passes selected predicates", else: "excluded"}
                  </td>
                </tr>
              </tbody>
            </table>
            <button id="follow-event" phx-click="follow_event" phx-value-id="next">Apply {inspect(
              @s.packet.case.follow
            )}</button>
            <pre :if={@s.follow} id="follow-output">{inspect(@s.follow,pretty: true)}</pre>
          </section>
        <% end %>
        <section class="panel">
          <p class="eyebrow">From source</p><h2>Inspect definitions and evidence</h2>
          <div class="button-row">
            <button
              :for={{id, a} <- Enum.sort(@s.packet.anchors)}
              phx-click="open_anchor"
              phx-value-id={id}
            >{String.replace_prefix(id, @s.packet.case.id <> ".", "")} · {a.path}</button>
          </div>
          <.source_excerpt :if={@s.source} anchor={@s.packet.anchors[@s.source]} />
        </section>
        <%= if @s.prediction do %>
          <div class="workbench-grid two-columns">
            <section class="panel">
              <p class="eyebrow">Explanation / suggestions</p><h2>Question the assumption</h2>
              <.form for={@question_form} id="question-form" phx-submit="ask_explainer">
                <.input
                  field={@question_form[:question]}
                  label="Your question"
                  type="textarea"
                  maxlength="1000"
                /><button id="ask-explainer">Ask explainer</button>
              </.form>
              <p id="explanation-status" role="status">{to_string(@explanation_status)}</p>
              <p :if={@explanation_status == :unavailable}>
                Explainer unavailable. All evidence and review actions remain available.
              </p>
              <%= if @s.explanation do %>
                <p class="eyebrow">
                  {if @s.explanation.mode == "inference", do: "AI", else: "Scripted"} explanation · check every citation
                </p>
                <div :for={item <- @s.explanation.items} class="explanation-item">
                  <p>{item["text"]}</p><button
                    :for={id <- item["source_ids"]}
                    phx-click="open_anchor"
                    phx-value-id={id}
                  >{id}</button>
                </div>
                <button id="flag-explanation" phx-click="flag_explanation">Misleading / unsupported</button><p :if={
                  @s.feedback != []
                }>
                  Feedback recorded separately from source facts.
                </p>
              <% end %>
            </section>
            <section class="panel">
              <p class="eyebrow">Human judgment</p><h2>Record a decision</h2><p>
                A receipt records your judgment for this scope. It confers neither proof acceptance nor deployment authority.
              </p>
              <.form for={@decision_form} id="decision-form" phx-submit="record_review">
                <.input
                  field={@decision_form[:decision]}
                  type="select"
                  label="Decision"
                  options={Enum.map(Session.decisions(), &{String.replace(&1, "_", " "), &1})}
                />
                <.input
                  field={@decision_form[:rationale]}
                  type="textarea"
                  label="Your rationale / what is missing"
                  maxlength="2000"
                />
                <fieldset>
                  <legend>Evidence you consulted (required for acceptance/rejection)</legend><label :for={
                    id <- Packet.evidence_ids(@s.packet)
                  }><input type="checkbox" name="evidence[]" value={id} /> {id}</label>
                </fieldset>
                <label><input type="checkbox" name="formally_checked" value="true" />
                My scope explicitly claims formal checker acceptance</label>
                <%= if Application.get_env(:hold_ledger_review_web,:review_mode) == :source_review do %>
                  <.input field={@decision_form[:revision]} label="Reviewed revision (exact HEAD)" /><.input
                    field={@decision_form[:scope]}
                    label="Reviewed change or claim"
                  />
                <% end %>
                <button id="record-review">Record human review</button>
              </.form>
            </section>
          </div>
        <% end %>
      <% end %>
    </Layouts.app>
    """
  end
end
