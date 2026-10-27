defmodule HoldLedgerReviewWeb.WorkbenchLive do
  @moduledoc """One deterministic, question-first LiveView. No model or remote processor is required."""
  use HoldLedgerReviewWeb, :live_view
  alias HoldLedgerReview.{Adversarial, Dossier, ReviewStore}

  @draft_fields ~w(before_json event_json output_json follow_on_json)
  @submit_fields @draft_fields ++ ~w(request_id expected_human_revision card_id packet_digest revealed_before_answer reason choice)

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket
      |> assign(:review, nil)
      |> assign(:reviews, [])
      |> assign(:draft, %{})
      |> assign(:draft_form, to_form(%{}, as: :draft))
      |> assign(:evaluation, nil)
      |> assign(:details, nil)
      |> assign(:draft_error, nil)
      |> assign(:selected_card_id, nil)
      |> assign(:request_id, request_id())
      |> assign(:revealed, false)
      |> assign(:matrix_open, false)
      |> assign(:map_open, false)
      |> assign(:source_open, false)
      |> assign(:selected_source, nil)
      |> assign(:finish_form, to_form(%{}, as: :finish))
      |> assign(:answer_form, to_form(%{}, as: :judgment))}
  end

  @impl true
  def handle_params(%{"id" => id}, _url, socket) do
    case ReviewStore.get(id) do
      {:ok, review} ->
        seed = case List.last(review["pinned_probes"]) do
          nil -> elem(Adversarial.seed(review["seed_id"]), 1)
          probe -> probe["witness"]
        end
        socket = socket |> assign(:review, review) |> assign(:selected_card_id, "core.#{String.downcase(review["seed_id"])}.escape")
          |> load_witness(seed)
        {:noreply, socket}
      {:error, _} ->
        {:noreply, socket |> put_flash(:error, "Review not available or corrupt; no recovery or approval inferred")
          |> push_navigate(to: "/workbench")}
    end
  end

  def handle_params(_, _, socket) do
    reviews = case ReviewStore.list() do
      {:ok, list} -> list
      _ -> []
    end
    {:noreply, socket |> assign(:review, nil) |> assign(:reviews, reviews)}
  end

  @impl true
  def handle_event("new_review", %{"seed" => seed}, socket) do
    case ReviewStore.create(seed) do
      {:ok, review, _} -> {:noreply, push_navigate(socket, to: "/workbench/#{review["id"]}")}
      {:error, reason} -> {:noreply, put_flash(socket, :error, "Cannot create review: #{inspect(reason)}")}
    end
  end

  def handle_event("select_card", %{"id" => id}, socket) do
    if Enum.any?(cards(socket.assigns.review), &(&1["id"] == id)) do
      {:noreply, socket |> assign(:selected_card_id, id) |> assign(:request_id, request_id()) |> assign(:revealed, false)}
    else
      {:noreply, put_flash(socket, :error, "Unknown card")}
    end
  end

  def handle_event("choose_seed", %{"seed" => id}, socket) do
    # Changing the selected policy case creates a new stable source-bound dossier.
    # Existing answers and cards keep their original identities in the old review.
    case ReviewStore.create(id) do
      {:ok, review, _witness} -> {:noreply, push_navigate(socket, to: "/workbench/#{review["id"]}")}
      {:error, reason} -> {:noreply, put_flash(socket, :error, "Cannot start scenario: #{inspect(reason)}")}
    end
  end

  def handle_event("draft_changed", %{"draft" => input}, socket) do
    draft = Map.merge(socket.assigns.draft, Map.take(input, @draft_fields))
    {:noreply, change_draft(socket, draft)}
  end

  def handle_event("answer_escape", %{"draft" => input}, socket) do
    review = socket.assigns.review
    card = active_card(socket)
    input = Map.put_new(input, "choice", "")
    if not is_map(review) or not is_map(card) or
       card["kind"] != "escape" or Enum.sort(Map.keys(input)) != Enum.sort(@submit_fields) or
       input["card_id"] != card["id"] or input["packet_digest"] != review["source"]["packet_digest"] do
      {:noreply, put_flash(socket, :error, "Invalid submitted answer")}
    else
      raw = Map.take(input, @draft_fields)
      socket = change_draft(socket, raw)
      with {:ok, parsed} <- Adversarial.from_form(raw),
           {:ok, witness} <- Adversarial.encode(parsed) do
        command = %{"request_id" => input["request_id"],
          "expected_human_revision" => integer(input["expected_human_revision"]),
          "card_id" => input["card_id"], "packet_digest" => input["packet_digest"],
          "witness" => witness, "choice" => input["choice"], "reason" => input["reason"],
          "revealed_before_answer" => input["revealed_before_answer"] == "true"}
        result = if input["choice"] == "pin_only" do
          pin = Map.take(command, ~w(request_id expected_human_revision packet_digest witness))
          ReviewStore.pin_candidate(review["id"], pin)
        else
          ReviewStore.answer_escape(review["id"], command)
        end
        case result do
          {:ok, %{review: updated}} -> {:noreply, saved(socket, updated, "Hypothetical pinned")}
          {:error, reason} -> {:noreply, put_flash(socket, :error, "Not saved: #{inspect(reason)}")}
        end
      else
        _ -> {:noreply, socket |> assign(:draft_error, "Invalid submitted draft; nothing saved")
          |> put_flash(:error, "Invalid submitted draft; no answer or probe was persisted")}
      end
    end
  end

  def handle_event("answer_card", %{"judgment" => input}, socket) do
    card = active_card(socket)
    review = socket.assigns.review
    if is_map(card) and card["kind"] != "escape" and Enum.sort(Map.keys(input)) == Enum.sort(~w(choice reason)) do
      command = %{"request_id" => socket.assigns.request_id, "expected_human_revision" => review["human_revision"],
        "card_id" => card["id"], "choice" => input["choice"], "reason" => input["reason"],
        "evidence_ids" => card["source_ids"], "revealed_before_answer" => socket.assigns.revealed}
      case ReviewStore.answer_card(review["id"], command) do
        {:ok, %{review: updated}} -> {:noreply, saved(socket, updated, "Human answer recorded")}
        {:error, reason} -> {:noreply, put_flash(socket, :error, "Not saved: #{inspect(reason)}")}
      end
    else
      {:noreply, put_flash(socket, :error, "Invalid card answer")}
    end
  end

  def handle_event("finish_review", %{"finish" => input}, socket) do
    review = socket.assigns.review
    if Enum.sort(Map.keys(input)) == Enum.sort(~w(outcome scope rationale)) do
      evidence = review["pinned_probes"] |> Enum.map(& &1["id"]) |> Enum.take(10)
      command = %{"request_id" => socket.assigns.request_id, "expected_human_revision" => review["human_revision"],
        "outcome" => input["outcome"], "scope" => input["scope"], "rationale" => input["rationale"],
        "evidence_ids" => evidence, "confirmed" => true}
      case ReviewStore.finish_review(review["id"], command) do
        {:ok, %{review: updated}} -> {:noreply, saved(socket, updated, "Scoped human conclusion confirmed")}
        {:error, reason} -> {:noreply, put_flash(socket, :error, "Not concluded: #{inspect(reason)}")}
      end
    else
      {:noreply, put_flash(socket, :error, "Invalid confirmation")}
    end
  end

  def handle_event("reveal", _, socket), do: {:noreply, assign(socket, :revealed, true)}
  def handle_event("toggle_matrix", _, socket), do: {:noreply, update(socket, :matrix_open, &(!&1))}
  def handle_event("toggle_map", _, socket), do: {:noreply, update(socket, :map_open, &(!&1))}
  def handle_event("toggle_source", _, socket), do: {:noreply, update(socket, :source_open, &(!&1))}
  def handle_event("source_select", %{"id" => id}, socket), do: {:noreply, assign(socket, :selected_source, id)}

  defp load_witness(socket, witness) do
    socket |> change_draft(Adversarial.form(witness)) |> assign(:request_id, request_id())
  end

  defp change_draft(socket, raw) do
    form = to_form(raw, as: :draft)
    socket = socket |> assign(:draft, raw) |> assign(:draft_form, form)
    if socket.assigns.review["status"] != "in_progress" do
      socket |> assign(:draft_error, "Stale or concluded review: start a new review to evaluate")
        |> assign(:evaluation, nil) |> assign(:details, nil)
    else
      with {:ok, parsed} <- Adversarial.from_form(raw),
           {:ok, encoded} <- Adversarial.encode(parsed),
           {:ok, evaluation, details} <- Adversarial.evaluate(encoded) do
        socket |> assign(:draft_error, nil) |> assign(:evaluation, evaluation) |> assign(:details, details)
      else
        {:error, :stale_source} -> assign(socket, :draft_error, "Source generation drift: start a new review after rebuilding")
        _ -> assign(socket, :draft_error, "Invalid bounded JSON: inspect before/event/output/follow-on fields (0..1,000,000, ≤8 entries/effects)")
      end
    end
  end

  defp saved(socket, doc, message) do
    socket |> assign(:review, doc) |> assign(:request_id, request_id()) |> put_flash(:info, message)
  end

  defp integer(value) when is_integer(value), do: value
  defp integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} -> n
      _ -> nil
    end
  end
  defp integer(_), do: nil
  defp cards(nil), do: []
  defp cards(doc), do: doc["core_cards"] ++ doc["accepted_ai_cards"]
  defp active_card(socket), do: Enum.find(cards(socket.assigns.review), &(&1["id"] == socket.assigns.selected_card_id))
  defp request_id, do: :crypto.strong_rand_bytes(18) |> Base.url_encode64(padding: false)

  defp last_answer(review, id) do
    review["answers"] |> Enum.reverse() |> Enum.find(&(&1["card_id"] == id))
  end

  defp source_for(review, source_id), do: Enum.find(review["graph_snapshot"]["excerpts"], &(&1["id"] == source_id))

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :current_card, if(assigns.review, do: Enum.find(cards(assigns.review), &(&1["id"] == assigns.selected_card_id)), else: nil))
    ~H"""
    <Layouts.app flash={@flash}>
      <%= if is_nil(@review) do %>
        <section class="workbench-intro">
          <p class="eyebrow">SOURCE-ANCHORED REVIEW / LOCAL ONLY</p>
          <h1>Decide what the ledger <em>should</em> guarantee.</h1>
          <p>Choose a concrete policy situation. Explore the pure reducer, independent oracle, exact source claims and a hypothetical outcome. Your judgment—not a model—owns the conclusion.</p>
          <div class="seed-grid" id="new-review-choices">
            <button :for={{seed, title, detail} <- [{"P01", "Pending authorized void", "Is release without confirmation acceptable?"}, {"P03", "Uncertain timeout", "Does unknown exposure keep capacity?"}, {"P04", "Exact-fit request", "Must an eligible request be admitted?"}]} type="button" class="seed-card" phx-click="new_review" phx-value-seed={seed}>
              <span class="eyebrow">{seed} · NEW REVIEW</span><strong>{title}</strong><span>{detail}</span>
            </button>
          </div>
          <h2>Existing review files</h2>
          <p class="muted">Answers, probes and revisions are durable on this checkout. Draft edits are not saved until pinned or answered.</p>
          <ul id="existing-reviews" class="review-list">
            <li :for={r <- @reviews}><.link navigate={"/workbench/#{r["id"]}"}>{r["id"]}</.link> <span>{r["status"]} · {r["updated_at_utc"]}</span></li>
          </ul>
        </section>
      <% else %>
        <div class="workbench-top" id="workbench-top">
          <div>
            <p class="eyebrow">POINTWISE INVESTIGATION · {String.upcase(@review["seed_id"])} / DOCUMENT {@review["document_revision"]} · HUMAN {@review["human_revision"]}</p>
            <h1>Hold Ledger <span class="text-subtle">/ decision workbench</span></h1>
            <p class="muted">Pure reducer and source claims, not remote execution or formal checker proof.</p>
          </div>
          <nav class="top-actions" aria-label="Workbench actions">
            <.link navigate="/workbench">Reviews</.link>
            <button id="map-toggle" type="button" phx-click="toggle_map" aria-expanded={@map_open}>Design map</button>
            <.link href={"/workbench/#{@review["id"]}/export.md"}>Export .md</.link>
            <.link href={"/workbench/#{@review["id"]}/export.json"}>Export .json</.link>
          </nav>
        </div>
        <p :if={@review["status"] != "in_progress"} class="notice-alert" role="alert">{@review["status"]}: saved history is read-only. Start a new review on the current checkout for new evaluations.</p>
        <section :if={@map_open} id="design-map" class="map-panel" aria-label="Complete design and proof map">
          <h2>Design → reducer/oracle → claims → Lean → outside-world premises</h2>
          <p class="muted">A dashed/inferred edge is a navigation suggestion, not a proved entailment. All registered DSL and native Lean obligations are listed; only relevant supported DSL rows enter the active matrix.</p>
          <div class="map-columns">
            <div>
              <h3>Policy rows and boundaries</h3>
              <ul><li :for={node <- @review["graph_snapshot"]["nodes"], node["kind"] in ~w(policy_row boundary)}>
                <button type="button" phx-click="source_select" phx-value-id={hd(node["source_ids"])}>{node["id"]}</button> {node["title"]}
              </li></ul>
            </div>
            <div>
              <h3>Law catalog (DSL + native)</h3>
              <ul><li :for={node <- @review["graph_snapshot"]["nodes"], node["kind"] in ~w(law lean)}>
                <button type="button" phx-click="source_select" phx-value-id={hd(node["source_ids"])}>{node["id"]}</button>
                <span :if={node["kind"] == "lean"} class="neutral-tag">Not a pointwise DSL probe</span>
                <small>{node["title"]}</small>
              </li></ul>
            </div>
          </div>
          <h3>Source-backed and inferred edges</h3>
          <ol id="graph-edges" class="edge-list"><li :for={e <- @review["graph_snapshot"]["edges"]}>
            <span>{e["from_id"]} → {e["to_id"]}</span> <b>{e["provenance"]}</b> <small>{e["kind"]} · {e["reason"]}</small>
          </li></ol>
        </section>
        <div class="review-grid">
          <aside class="pane guarantee" aria-labelledby="claim-heading">
            <p class="eyebrow">01 / GUARANTEE & BOUNDARY</p>
            <h2 id="claim-heading">Source, not paraphrase</h2>
            <p><b>Loaded evaluator:</b> <code>{String.slice(@review["source"]["evaluator_id"], 0, 16)}…</code></p>
            <p><b>Formal checker:</b> <span class="neutral-tag">{@review["source"]["proof_report_snapshot"]["status"]}</span></p>
            <p class="muted">The checker status is independent of the hypothetical matrix and human intent. Remote fencing and journal truthfulness are premises, not proofs.</p>
            <button type="button" id="source-toggle" phx-click="toggle_source" aria-expanded={@source_open}>Browse source evidence</button>
            <div :if={@source_open} id="source-panel" class="source-panel">
              <p>Choose a source anchor to inspect exact checkout bytes and digest. The map shows inferred associations separately.</p>
              <ul>
                <li :for={s <- @review["graph_snapshot"]["excerpts"]}>
                  <button type="button" phx-click="source_select" phx-value-id={s["id"]}>{s["path"]}</button>
                  <.link href={"/workbench/#{@review["id"]}/source/#{s["id"]}"} target="_blank">Full source</.link>
                </li>
              </ul>
            </div>
            <div :if={@selected_source && source_for(@review, @selected_source)} id="selected-source" class="source-selected">
              <p><b>{source_for(@review, @selected_source)["path"]}</b></p>
              <p>SHA-256 <code>{source_for(@review, @selected_source)["sha256"]}</code></p>
              <pre>{source_for(@review, @selected_source)["text"]}</pre>
            </div>
            <h3>Three deliberate evidence boundaries</h3>
            <ul class="boundary-list">
              <li>Source AST determines Elixir pointwise law meaning.</li>
              <li>Independent Lean checker reports determine formal status, when supplied.</li>
              <li>Human + processor evidence determines adequacy and external premises.</li>
            </ul>
          </aside>
          <section class="pane arena" aria-labelledby="probe-heading">
            <p class="eyebrow">02 / ADVERSARIAL ARENA</p>
            <h2 id="probe-heading">What happens if…?</h2>
            <div class="fixture-strip" aria-label="Synthetic initial examples">
              <button :for={seed <- Adversarial.seeds()} type="button" phx-click="choose_seed" phx-value-seed={seed} id={"load-#{seed}"}>{seed}</button>
            </div>
            <p class="muted">Start a fresh source-bound dossier with a preset (the current review remains unchanged). Presets are synthetic, never observed mutant outputs. Direct edits are provisional until pinned or judged.</p>
            <.form for={@draft_form} id="candidate-form" phx-change="draft_changed" phx-submit="answer_escape">
              <div class="json-fields">
                <.input field={@draft_form[:before_json]} type="textarea" label="Before state (typed JSON)" rows="7" phx-debounce="100" />
                <.input field={@draft_form[:event_json]} type="textarea" label="Event (request amount / key)" rows="3" phx-debounce="100" />
                <.input field={@draft_form[:output_json]} type="textarea" label="What-if full output (after / result / effects)" rows="10" phx-debounce="100" />
                <.input field={@draft_form[:follow_on_json]} type="textarea" label="Follow-on event (or null)" rows="3" phx-debounce="100" />
              </div>
              <input type="hidden" name="draft[request_id]" value={@request_id} />
              <input type="hidden" name="draft[expected_human_revision]" value={@review["human_revision"]} />
              <input type="hidden" name="draft[packet_digest]" value={@review["source"]["packet_digest"]} />
              <input type="hidden" name="draft[card_id]" value={@selected_card_id} />
              <input type="hidden" name="draft[revealed_before_answer]" value={to_string(@revealed)} />
              <label for="escape-reason">Reason (optional; required for deferral)</label>
              <textarea id="escape-reason" name="draft[reason]" maxlength="600" rows="2"></textarea>
              <p :if={@draft_error} id="draft-error" role="alert" class="notice-alert">{@draft_error} · The matrix below, if shown, belongs to the last good input and is historical—not this invalid draft.</p>
              <p :if={@evaluation && !@draft_error} id="candidate-ok" role="status" class="neutral-tag">Bounded witness valid · after-state Spec.valid?: {@details.candidate_after_valid?} · actual equals oracle: {@details.actual_equals_oracle?}</p>
              <div :if={@current_card && @current_card["kind"] == "escape"} class="answer-actions" aria-label="Escape judgment">
                <button type="submit" name="draft[choice]" value="acceptable" disabled={@draft_error != nil} id="escape-acceptable">Acceptable</button>
                <button type="submit" name="draft[choice]" value="unacceptable" disabled={@draft_error != nil} id="escape-unacceptable" class="primary">Unacceptable</button>
                <button type="submit" name="draft[choice]" value="unsure" disabled={@draft_error != nil} id="escape-unsure">Unsure</button>
                <button type="submit" name="draft[choice]" value="deferred" disabled={@draft_error != nil} id="escape-deferred">Defer</button>
                <button type="submit" name="draft[choice]" value="pin_only" disabled={@draft_error != nil} id="pin-candidate">Pin only</button>
              </div>
            </.form>
            <div :if={@evaluation} id="computed-contrast" class="comparison">
              <p :if={@draft_error} class="muted"><b>Historical last-good evaluation only</b> · not the draft currently shown</p>
              <div><b>Actual reducer</b><pre>{Jason.encode!(@evaluation["actual"], pretty: true)}</pre></div>
              <div><b>Independent Spec oracle</b><pre>{Jason.encode!(@evaluation["oracle"], pretty: true)}</pre></div>
              <div><b>Hypothetical (not executed)</b><pre>{if @draft_error, do: "Invalid draft; hypothetical unavailable", else: @draft["output_json"]}</pre></div>
              <div :if={@details && !@draft_error} id="diff-panel">
                <b>Changed output dimensions</b>
                <ul><li :for={diff <- @details.changed_fields}>{diff["field"]}: reducer ≠ what-if</li></ul>
                <p :if={@details.request_eligible? != nil}>Spec.request_eligible? at this input: <b>{@details.request_eligible?}</b> (fresh request only)</p>
              </div>
            </div>
            <section id="follow-on-area" aria-label="Second-Event Consequence">
              <h3>Second-Event Consequence</h3>
              <%= if @evaluation && @evaluation["follow_on_actual"] == nil && @evaluation["follow_on_candidate"] == nil && (@details == nil || @details.follow_reason == :no_follow_on_event) do %>
                <p id="no-follow-on" class="muted">No follow-on event selected for this probe.</p>
              <% else %>
                <%= if @evaluation do %>
                  <p>Pure follow-on from actual: <code>{Jason.encode!(@evaluation["follow_on_actual"])}</code></p>
                  <p>Pure follow-on from candidate: <code>{Jason.encode!(@evaluation["follow_on_candidate"])}</code></p>
                  <p :if={@evaluation["follow_on_candidate"] == nil} class="muted">A Spec-invalid hypothetical cannot be stepped further; no second call was made.</p>
                <% end %>
              <% end %>
            </section>
            <section id="catcher-matrix" class="matrix">
              <h3>Active supported DSL pointwise checks</h3>
              <p class="muted">Catches · Allows here · Doesn't apply · Can't check. Every result is for named bindings only; the rest of the full catalog is unexamined.</p>
              <table><thead><tr><th>Original law</th><th>Candidate here</th><th>Bindings</th></tr></thead>
                <tbody><tr :for={row <- if(@evaluation, do: @evaluation["law_rows"], else: [])}>
                  <td>{row["slug"]}</td><td><span class={"status status-#{row["label"]}"}>{status_label(row["label"])}</span><small>{row["reason"]}</small></td><td>{row["bindings_tested"]} · complete: {row["exhaustive_for_source_domain"]}</td>
                </tr></tbody>
              </table>
              <button id="matrix-toggle" type="button" phx-click="toggle_matrix" aria-expanded={@matrix_open}>All matrix diagnostics</button>
              <pre :if={@matrix_open && @details} id="matrix-diagnostics">{inspect(@details.checks, pretty: true, limit: 500)}</pre>
              <p class="muted">Formal native Lean obligations are <b>not a pointwise DSL probe</b>; open the design map for the full remainder and independent checker state.</p>
            </section>
          </section>
          <aside class="pane decision" aria-labelledby="decision-heading">
            <p class="eyebrow">03 / HUMAN DECISION</p>
            <h2 id="decision-heading">Your judgment</h2>
            <p class="muted">One focused question at a time. Every answer is attributed to a human, with supersession and a pinned witness when required.</p>
            <nav id="question-nav" aria-label="Review questions" class="card-nav">
              <button :for={card <- cards(@review)} id={"card-#{card["kind"]}"} type="button" class={if(card["id"] == @selected_card_id, do: "selected", else: "")}
                phx-click="select_card" phx-value-id={card["id"]}>
                <span>{card["kind"]} {if(card["mandatory"], do: "· required", else: "")}</span>
                <small>{if(last_answer(@review, card["id"]), do: last_answer(@review, card["id"])["choice"], else: "open")}</small>
              </button>
            </nav>
            <%= if @current_card do %>
              <article id="active-question" class="active-question">
                <p class="eyebrow">{@current_card["kind"]} · {if(@current_card["critical"], do: "critical: #{@current_card["critical_reason"]}", else: "scoped review")}</p>
                <h3>{@current_card["question"]}</h3>
                <p>Source node: {@current_card["target_node_id"]}</p>
                <button id="reveal-analysis" type="button" phx-click="reveal">Reveal analysis first</button>
                <p :if={@revealed} class="neutral-tag">Analysis was revealed before this answer.</p>
                <p :if={last_answer(@review, @current_card["id"])} id="latest-answer"><b>Latest:</b> {last_answer(@review, @current_card["id"])["choice"]} (you may revise; history remains)</p>
                <%= if @current_card["kind"] == "escape" do %>
                  <p>Answer using the current whole witness form in the arena. A changed output and its computed law result will be committed together in one write.</p>
                <% else %>
                  <.form for={@answer_form} id="card-answer-form" phx-submit="answer_card">
                    <label for="card-reason">Reason / source correction</label>
                    <.input field={@answer_form[:reason]} id="card-reason" type="textarea" rows="3" maxlength="600" />
                    <div class="answer-actions">
                      <button :for={choice <- Dossier.choices(@current_card["kind"])} type="submit" name="judgment[choice]" value={choice}>{choice}</button>
                    </div>
                  </.form>
                <% end %>
              </article>
            <% end %>
            <section id="review-summary" class="review-summary">
              <h3>Scoped review conclusion</h3>
              <p>Review can be exported unfinished. Mandatory/critical questions must be answered or explicitly deferred before concluding. Material deferrals cannot support a positive outcome.</p>
              <.form for={@finish_form} id="finish-form" phx-submit="finish_review">
                <.input field={@finish_form[:scope]} type="textarea" label="Named policy scope" rows="2" value={Enum.join(@review["target_policy_nodes"], ", ")} />
                <.input field={@finish_form[:rationale]} type="textarea" label="Human rationale (required)" rows="2" />
                <label for="review-outcome">Choose one explicit outcome</label>
                <select id="review-outcome" name="finish[outcome]">
                  <option value="needs_policy_or_evidence">Needs policy or evidence</option>
                  <option value="needs_design_change">Needs design change</option>
                  <option value="meets_intent_in_reviewed_scope">Meets intent in reviewed scope</option>
                </select>
                <button type="submit" disabled={@review["status"] != "in_progress"} id="confirm-finish">Confirm human conclusion</button>
              </.form>
              <p :if={@review["review_conclusion"]}><b>Human conclusion:</b> {@review["review_conclusion"]["outcome"]}</p>
            </section>
          </aside>
        </div>
      <% end %>
    </Layouts.app>
    """
  end

  defp status_label("catches"), do: "Catches"
  defp status_label("allows_here"), do: "Allows here"
  defp status_label("does_not_apply"), do: "Doesn't apply"
  defp status_label(_), do: "Can't check"
end
