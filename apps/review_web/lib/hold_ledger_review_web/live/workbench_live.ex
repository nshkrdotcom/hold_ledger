defmodule HoldLedgerReviewWeb.WorkbenchLive do
  @moduledoc "Source-owned, human-CAS review with optional opted-in AI proposals."
  use HoldLedgerReviewWeb, :live_view
  alias HoldLedgerReview.{Adversarial, AI, AIJobs, Dossier, ReviewStore}

  alias HoldLedgerReviewWeb.{Explain, Glossary, ReviewProgress}

  @draft_fields ~w(before_json event_json output_json follow_on_json)
  @submit_fields @draft_fields ++
                   ~w(request_id expected_human_revision card_id packet_digest revealed_before_answer reason choice)

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
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
     |> assign(:ai_consent, false)
     |> assign(:ai_capability, match?({:ok, _}, AI.available?()))
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
        if connected?(socket),
          do: Phoenix.PubSub.subscribe(HoldLedgerReview.PubSub, "review:" <> id)

        seed =
          case List.last(review["pinned_probes"]) do
            nil -> elem(Adversarial.seed(review["seed_id"]), 1)
            probe -> probe["witness"]
          end

        socket =
          socket
          |> assign(:review, review)
          |> assign(:selected_card_id, "core.#{String.downcase(review["seed_id"])}.escape")
          |> load_witness(seed)

        {:noreply, socket}

      {:error, _} ->
        {:noreply,
         socket
         |> put_flash(:error, "Review not available or corrupt; no recovery or approval inferred")
         |> push_navigate(to: "/workbench")}
    end
  end

  def handle_params(_, _, socket) do
    reviews =
      case ReviewStore.list() do
        {:ok, list} -> list
        _ -> []
      end

    {:noreply, socket |> assign(:review, nil) |> assign(:reviews, reviews)}
  end

  @impl true
  def handle_event("new_review", %{"seed" => seed}, socket) do
    case ReviewStore.create(seed) do
      {:ok, review, _} ->
        {:noreply, push_navigate(socket, to: "/workbench/#{review["id"]}")}

      {:error, reason} ->
        {:noreply, error_flash(socket, reason, "Cannot create review: #{inspect(reason)}")}
    end
  end

  def handle_event("select_card", %{"id" => id}, socket) do
    if Enum.any?(cards(socket.assigns.review), &(&1["id"] == id)) do
      {:noreply,
       socket
       |> assign(:selected_card_id, id)
       |> assign(:request_id, request_id())
       |> assign(:revealed, false)
       |> assign(:matrix_open, false)}
    else
      {:noreply, put_flash(socket, :error, "Unknown card")}
    end
  end

  def handle_event("choose_seed", %{"seed" => id}, socket) do
    # Changing the selected policy case creates a new stable source-bound dossier.
    # Existing answers and cards keep their original identities in the old review.
    case ReviewStore.create(id) do
      {:ok, review, _witness} ->
        {:noreply, push_navigate(socket, to: "/workbench/#{review["id"]}")}

      {:error, reason} ->
        {:noreply, error_flash(socket, reason, "Cannot start scenario: #{inspect(reason)}")}
    end
  end

  def handle_event("reset_draft", _params, socket) do
    case Adversarial.seed(socket.assigns.review["seed_id"]) do
      {:ok, witness} -> {:noreply, load_witness(socket, witness)}
      {:error, reason} -> {:noreply, error_flash(socket, reason, inspect(reason))}
    end
  end

  @impl true
  def handle_event("draft_changed", %{"draft" => input}, socket) do
    draft = Map.merge(socket.assigns.draft, Map.take(input, @draft_fields))
    {:noreply, change_draft(socket, draft)}
  end

  def handle_event("answer_escape", %{"draft" => input}, socket) do
    review = socket.assigns.review
    card = active_card(socket)
    input = Map.put_new(input, "choice", "")

    if valid_escape_submission?(review, card, input) do
      submit_escape(socket, review, input)
    else
      {:noreply, put_flash(socket, :error, "Invalid submitted answer")}
    end
  end

  def handle_event("answer_card", %{"judgment" => input}, socket) do
    card = active_card(socket)
    review = socket.assigns.review

    if is_map(card) and card["kind"] != "escape" and
         Enum.sort(Map.keys(input)) == Enum.sort(~w(choice reason)) do
      command = %{
        "request_id" => socket.assigns.request_id,
        "expected_human_revision" => review["human_revision"],
        "card_id" => card["id"],
        "choice" => input["choice"],
        "reason" => input["reason"],
        "evidence_ids" => card["source_ids"],
        "revealed_before_answer" => socket.assigns.revealed
      }

      case ReviewStore.answer_card(review["id"], command) do
        {:ok, %{review: updated}} ->
          {:noreply, saved(socket, updated, "Human answer recorded")}

        {:error, reason} ->
          {:noreply, error_flash(socket, reason, "Not saved: #{inspect(reason)}")}
      end
    else
      {:noreply, put_flash(socket, :error, "Invalid card answer")}
    end
  end

  def handle_event("finish_review", %{"finish" => input}, socket) do
    review = socket.assigns.review

    if Enum.sort(Map.keys(input)) == Enum.sort(~w(outcome scope rationale)) do
      evidence = review["pinned_probes"] |> Enum.map(& &1["id"]) |> Enum.take(10)

      command = %{
        "request_id" => socket.assigns.request_id,
        "expected_human_revision" => review["human_revision"],
        "outcome" => input["outcome"],
        "scope" => input["scope"],
        "rationale" => input["rationale"],
        "evidence_ids" => evidence,
        "confirmed" => true
      }

      case ReviewStore.finish_review(review["id"], command) do
        {:ok, %{review: updated}} ->
          {:noreply, saved(socket, updated, "Scoped human conclusion confirmed")}

        {:error, reason} ->
          {:noreply, error_flash(socket, reason, "Not concluded: #{inspect(reason)}")}
      end
    else
      {:noreply, put_flash(socket, :error, "Invalid confirmation")}
    end
  end

  def handle_event("reveal", _, socket), do: {:noreply, assign(socket, :revealed, true)}

  def handle_event("toggle_matrix", _, socket),
    do: {:noreply, socket |> update(:matrix_open, &(!&1)) |> assign(:revealed, true)}

  def handle_event("toggle_map", _, socket), do: {:noreply, update(socket, :map_open, &(!&1))}

  def handle_event("toggle_source", _, socket),
    do: {:noreply, update(socket, :source_open, &(!&1))}

  def handle_event("source_select", %{"id" => id}, socket),
    do: {:noreply, assign(socket, :selected_source, id)}

  @impl true
  def handle_event("toggle_ai_consent", _, socket),
    do: {:noreply, update(socket, :ai_consent, &(!&1))}

  def handle_event("ai_request", %{"kind" => kind}, socket)
      when kind in ~w(deck challenge followup) do
    review = socket.assigns.review
    card = active_card(socket)

    if review && card && socket.assigns.ai_consent && review["status"] == "in_progress" do
      request_ai(socket, review, card, kind)
    else
      {:noreply,
       put_flash(socket, :error, "Explicit AI consent and a current review are required")}
    end
  end

  def handle_event("accept_ai_card", %{"id" => id}, socket) do
    review = socket.assigns.review

    command = %{
      "request_id" => request_id(),
      "expected_human_revision" => review["human_revision"],
      "card_id" => id
    }

    case ReviewStore.accept_ai_card(review["id"], command) do
      {:ok, %{review: updated}} ->
        {:noreply,
         socket
         |> saved(updated, "AI question accepted by human")
         |> assign(:selected_card_id, id)}

      {:error, reason} ->
        {:noreply, error_flash(socket, reason, "Question not accepted: #{inspect(reason)}")}
    end
  end

  def handle_event("try_ai_challenge", %{"job" => job_id}, socket) do
    review = socket.assigns.review
    job = Enum.find(review["ai_jobs"], &(&1["job_id"] == job_id))
    proposed = if job && job["status"] == "complete", do: job["validated_output"], else: nil
    witness = get_in(proposed || %{}, ["challenge", "witness"])

    if witness do
      {:noreply,
       socket
       |> load_witness(witness)
       |> put_flash(:info, "AI proposal loaded as a draft only; no probe or answer was saved")}
    else
      {:noreply, put_flash(socket, :error, "No current valid AI challenge to try")}
    end
  end

  @impl true
  def handle_info({:review_updated, id}, socket) do
    if socket.assigns.review && socket.assigns.review["id"] == id do
      case ReviewStore.get(id) do
        {:ok, updated} -> {:noreply, assign(socket, :review, updated)}
        _ -> {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  defp request_ai(socket, review, card, kind) do
    witness = challenge_witness(socket, kind)

    if kind == "challenge" and is_nil(witness) do
      {:noreply,
       put_flash(socket, :error, "Correct the draft before sending a challenge request")}
    else
      result =
        AIJobs.request(review["id"], kind, card["id"], witness, review["human_revision"], true)

      ai_request_result(assign(socket, :ai_consent, false), result, kind)
    end
  end

  defp challenge_witness(socket, "challenge") do
    with {:ok, decoded} <- Adversarial.from_form(socket.assigns.draft),
         {:ok, encoded} <- Adversarial.encode(decoded) do
      encoded
    else
      _ -> nil
    end
  end

  defp challenge_witness(_socket, _kind), do: nil

  defp ai_request_result(socket, {:ok, updated, _job_id}, kind) do
    {:noreply,
     socket
     |> assign(:review, updated)
     |> put_flash(:info, "AI #{kind} request queued; no finding is assumed")}
  end

  defp ai_request_result(socket, {:error, reason}, _kind) do
    {:noreply, error_flash(socket, reason, "AI unavailable/request refused: #{inspect(reason)}")}
  end

  defp valid_escape_submission?(review, card, input) do
    is_map(review) and is_map(card) and card["kind"] == "escape" and
      Enum.sort(Map.keys(input)) == Enum.sort(@submit_fields) and
      input["card_id"] == card["id"] and
      input["packet_digest"] == review["source"]["packet_digest"]
  end

  defp submit_escape(socket, review, input) do
    raw = Map.take(input, @draft_fields)
    socket = change_draft(socket, raw)

    with {:ok, parsed} <- Adversarial.from_form(raw),
         {:ok, witness} <- Adversarial.encode(parsed) do
      command = %{
        "request_id" => input["request_id"],
        "expected_human_revision" => integer(input["expected_human_revision"]),
        "card_id" => input["card_id"],
        "packet_digest" => input["packet_digest"],
        "witness" => witness,
        "choice" => input["choice"],
        "reason" => input["reason"],
        "revealed_before_answer" => input["revealed_before_answer"] == "true"
      }

      escape_result(socket, save_escape(review, command))
    else
      _ ->
        {:noreply,
         socket
         |> assign(:draft_error, "Invalid submitted draft; nothing saved")
         |> put_flash(:error, "Invalid submitted draft; no answer or probe was persisted")}
    end
  end

  defp save_escape(review, %{"choice" => "pin_only"} = command) do
    ReviewStore.pin_candidate(
      review["id"],
      Map.take(command, ~w(request_id expected_human_revision packet_digest witness))
    )
  end

  defp save_escape(review, command), do: ReviewStore.answer_escape(review["id"], command)

  defp escape_result(socket, {:ok, %{review: updated}}),
    do: {:noreply, saved(socket, updated, "Hypothetical and human command saved")}

  defp escape_result(socket, {:error, reason}),
    do: {:noreply, error_flash(socket, reason, "Not saved: #{inspect(reason)}")}

  defp load_witness(socket, witness) do
    socket |> change_draft(Adversarial.form(witness)) |> assign(:request_id, request_id())
  end

  defp change_draft(socket, raw) do
    form = to_form(raw, as: :draft)
    socket = socket |> assign(:draft, raw) |> assign(:draft_form, form)

    if socket.assigns.review["status"] != "in_progress" do
      socket
      |> assign(:draft_error, "Stale or concluded review: start a new review to evaluate")
      |> assign(:evaluation, nil)
      |> assign(:details, nil)
    else
      with {:ok, parsed} <- Adversarial.from_form(raw),
           {:ok, encoded} <- Adversarial.encode(parsed),
           {:ok, evaluation, details} <- Adversarial.evaluate(encoded) do
        socket
        |> assign(:draft_error, nil)
        |> assign(:evaluation, evaluation)
        |> assign(:details, details)
      else
        {:error, :stale_source} ->
          assign(
            socket,
            :draft_error,
            "Source generation drift: start a new review after rebuilding"
          )

        _ ->
          assign(
            socket,
            :draft_error,
            draft_message(raw)
          )
      end
    end
  end

  defp draft_message(raw) do
    fields = [
      {"before_json", "Starting state"},
      {"event_json", "Event"},
      {"output_json", "What-if outcome"},
      {"follow_on_json", "Next event"}
    ]

    case Enum.find(fields, fn {key, _} -> match?({:error, _}, Jason.decode(raw[key] || "")) end) do
      {_, label} ->
        label <>
          " is not valid JSON. Check commas and quotes; for example, the next-event field may be null."

      nil ->
        "The JSON shape or starting state is invalid. Compare it with the starting example and see What do these fields mean?"
    end
  end

  defp saved(socket, doc, message) do
    socket
    |> assign(:review, doc)
    |> assign(:request_id, request_id())
    |> put_flash(:info, message)
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

  defp active_card(socket),
    do: Enum.find(cards(socket.assigns.review), &(&1["id"] == socket.assigns.selected_card_id))

  defp request_id, do: :crypto.strong_rand_bytes(18) |> Base.url_encode64(padding: false)

  defp last_answer(review, id) do
    review["answers"] |> Enum.reverse() |> Enum.find(&(&1["card_id"] == id))
  end

  defp source_for(review, source_id),
    do: Enum.find(review["graph_snapshot"]["excerpts"], &(&1["id"] == source_id))

  defp error_flash(socket, reason, raw) do
    socket |> put_flash(:error, Glossary.error(reason)) |> put_flash(:error_detail, raw)
  end

  defp implication(review, card) do
    answer = last_answer(review, card["id"])
    probe = Enum.find(review["pinned_probes"], &(&1["id"] == answer["probe_id"]))

    case Dossier.implication(
           card,
           answer["choice"],
           if(probe, do: probe["evaluation"], else: nil)
         ) do
      {:ok, text} -> text
      _ -> "Inspect the saved answer and its evidence before concluding."
    end
  end

  defp source_names(review, ids) do
    Enum.map_join(ids, ", ", fn id ->
      case source_for(review, id) do
        nil ->
          case Enum.find(review["graph_snapshot"]["nodes"], &(&1["id"] == id)) do
            nil ->
              "Source reference unavailable (see technical record)"

            node ->
              Enum.map_join(node["source_ids"], ", ", fn source_id ->
                source_for(review, source_id)["path"]
              end)
          end

        source ->
          source["path"]
      end
    end)
  end

  defp current_witness(%{draft_error: nil, draft: draft, review: review})
       when not is_nil(review) do
    Map.new(~w(before event output follow_on), fn key ->
      {key, Jason.decode!(draft[key <> "_json"])}
    end)
  end

  defp current_witness(_), do: nil

  attr :value, :any, required: true
  attr :kind, :string, default: "output"

  defp narrated(assigns) do
    ~H"""
    <p class="narrative">
      {case @kind do
        "state" -> Explain.state(@value)
        "event" -> Explain.event(@value)
        _ -> Explain.output(@value)
      end}
    </p>
    <details>
      <summary>Show raw JSON</summary><pre>{Jason.encode!(@value, pretty: true)}</pre>
    </details>
    """
  end

  attr :review, :map, required: true

  defp progress(assigns) do
    assigns = assign(assigns, :counts, ReviewProgress.counts(assigns.review))

    ~H"""
    <p class="progress-count">
      {@counts.answered} of {@counts.total} required questions answered
      <span :if={@counts.deferred > 0}>· {@counts.deferred} deferred, still unresolved</span>
    </p>
    """
  end

  @impl true
  def render(assigns) do
    assigns =
      assign(
        assigns,
        :current_card,
        if(assigns.review,
          do: Enum.find(cards(assigns.review), &(&1["id"] == assigns.selected_card_id)),
          else: nil
        )
      )

    assigns = assign(assigns, :current_witness, current_witness(assigns))

    ~H"""
    <Layouts.app flash={@flash}>
      <%= if is_nil(@review) do %>
        <section class="workbench-intro">
          <p class="eyebrow">Payment policy / human review</p>
          <h1>Decide what the ledger <em>should</em> guarantee.</h1>
          <p class="intro-lead">
            A payment hold reserves money while a processor decides what happens next. Hold Ledger tracks these reservations for one account, with limits on their total amount and count.
          </p>
          <p>
            Your job is to check whether the rules match the intended policy. A proof can establish a rule as written; it cannot choose the right rule. No Lean knowledge is needed, and this app does not run Lean.
          </p>
          <ol class="how-it-works" aria-label="How this works">
            <li><b>Choose a situation.</b> Read the starting state and event.</li>
            <li><b>Compare two outcomes.</b> See the real result and a proposed alternative.</li>
            <li><b>Judge the rules.</b> Predict first, then inspect what catches the alternative.</li>
            <li><b>Conclude within scope.</b> Record your decision and what still needs evidence.</li>
          </ol>
          <p>
            Work through one scenario at a time; you can pause and return to saved answers. Nothing leaves this machine unless you explicitly opt in for an AI request.
          </p>
          <nav class="help-links" aria-label="Getting started">
            <a
              href="https://github.com/nshkrdotcom/hold_ledger/blob/main/guides/interactive_review.md"
              target="_blank"
              rel="noreferrer"
            >Review walkthrough ↗</a>
            <a
              href="https://github.com/nshkrdotcom/hold_ledger/blob/main/guides/formal_verification_crash_course.md"
              target="_blank"
              rel="noreferrer"
            >Proofs, explained ↗</a>
          </nav>
          <h2>Choose a starting situation</h2>
          <div class="seed-grid" id="new-review-choices">
            <button
              :for={seed <- Adversarial.seeds()}
              type="button"
              class="seed-card"
              phx-click="new_review"
              phx-value-seed={seed}
            >
              <span class="eyebrow">{seed} <span :if={seed == "P01"}>/ Start here</span></span>
              <strong>{Glossary.scenario_title(seed)}</strong><span>{Glossary.scenario_question(seed)}</span>
            </button>
          </div>
          <h2>Existing review files</h2>
          <p class="muted">
            Answers and saved examples stay in this checkout. Editor changes stay temporary until you save the example or answer its question.
          </p>
          <p :if={@reviews == []}>No reviews yet — pick a scenario above.</p>
          <ul id="existing-reviews" class="review-list">
            <li :for={r <- @reviews}>
              <.link navigate={"/workbench/#{r["id"]}"}>{Glossary.review_title(r)}</.link>
              <span>{Glossary.label(r["status"])} · Updated {r["updated_at_utc"]}</span><small>{r[
                "id"
              ]}</small>
            </li>
          </ul>
        </section>
      <% else %>
        <div class="workbench-top" id="workbench-top">
          <div>
            <p class="eyebrow">Review / {@review["seed_id"]}</p>
            <h1>{Glossary.scenario_title(@review["seed_id"])}</h1><.progress review={@review} />
            <details>
              <summary>Review details</summary><p>
                Document revision {@review["document_revision"]} · Human revision {@review[
                  "human_revision"
                ]}
              </p><code>{@review["id"]}</code>
            </details>
            <details>
              <summary>Limits of this evidence</summary><p>
                Pure reducer and source claims, not remote execution or formal checker proof. Local calculations describe requested work; they do not perform a payment.
              </p>
            </details>
          </div>
          <nav class="top-actions" aria-label="Workbench actions">
            <.link navigate="/workbench">Reviews</.link>
            <button id="map-toggle" type="button" phx-click="toggle_map" aria-expanded={@map_open}>Design map</button>
            <.link href={"/workbench/#{@review["id"]}/export.md"}>Export .md</.link>
            <.link href={"/workbench/#{@review["id"]}/export.json"}>Export .json</.link>
          </nav>
        </div>
        <p :if={@review["status"] != "in_progress"} class="notice-alert" role="alert">
          This review is read-only. {Glossary.one_line(@review["status"])} Start a new review to keep evaluating.
        </p>
        <details class="orientation" open={@review["answers"] == [] && @review["pinned_probes"] == []}>
          <summary>Your job here</summary>
          <p>
            Check whether the rules protect the behavior you intend. Compare the real result with the alternative, decide whether the alternative is acceptable, then inspect which rules address it. You are checking whether the rules are right, not whether the proofs compile.
          </p>
        </details>
        <ol class="step-strip">
          <li
            :for={
              {label, number} <-
                Enum.with_index(
                  [
                    "Understand the scenario",
                    "Predict",
                    "Compare with the laws",
                    "Judge",
                    "Conclude"
                  ],
                  1
                )
            }
            aria-current={if ReviewProgress.step(@review, @revealed) == number, do: "step", else: nil}
          >
            {label}
          </li>
        </ol>
        <section id="scenario-brief" class="scenario-brief" aria-labelledby="scenario-heading">
          <h2 id="scenario-heading">The situation</h2>
          <p><strong>{Glossary.scenario_question(@review["seed_id"])}</strong></p>
          <p :if={@draft_error} class="notice-alert">
            The draft cannot be calculated. Correct it or reset to the starting example; no current scenario summary is shown.
          </p>
          <dl :if={@current_witness} class="scenario-facts">
            <div>
              <dt>Starting state</dt><dd>{Explain.state(@current_witness["before"])}</dd>
            </div>
            <div>
              <dt>What happens</dt><dd>{Explain.event(@current_witness["event"])}</dd>
            </div>
            <div>
              <dt>What the real ledger does</dt><dd>{Explain.output(@evaluation["actual"])}</dd>
            </div>
            <div>
              <dt>The proposed alternative</dt><dd>{Explain.output(@current_witness["output"])}</dd>
            </div>
          </dl>
          <p>
            The
            <.term key="what_if">what-if</.term>
            is an alternative behavior for you to judge. It is calculated locally; no remote payment operation is performed.
          </p>
        </section>
        <section
          :if={@map_open}
          id="design-map"
          class="map-panel"
          aria-label="Complete design and proof map"
        >
          <h2>How the policy connects to code and rules</h2>
          <p class="muted">
            A dashed/inferred edge is a navigation suggestion, not a proved entailment. All registered DSL and native Lean obligations are listed; only relevant supported DSL rows enter the active matrix.
          </p>
          <div class="map-columns">
            <div>
              <h3>Policy rows</h3>
              <ul>
                <li
                  :for={node <- @review["graph_snapshot"]["nodes"]}
                  :if={node["kind"] in ~w(policy_row boundary)}
                >
                  <button
                    type="button"
                    phx-click="source_select"
                    phx-value-id={hd(node["source_ids"])}
                  ><strong>{node["title"]}</strong><small>{node["id"]}</small></button>
                </li>
              </ul>
            </div>
            <div>
              <h3>Rules the ledger is proved against</h3>
              <ul>
                <li
                  :for={node <- @review["graph_snapshot"]["nodes"]}
                  :if={node["kind"] in ~w(law lean)}
                >
                  <button
                    type="button"
                    phx-click="source_select"
                    phx-value-id={hd(node["source_ids"])}
                    data-node-id={node["id"]}
                  ><strong>{Glossary.law_description(
                    node["id"]
                    |> String.replace_prefix("law.", "")
                    |> String.replace_prefix("lean.", "")
                  )}</strong><small>{node[
                    "id"
                  ]}</small></button>
                  <span
                    :if={node["kind"] == "lean"}
                    class="neutral-tag"
                    title={Glossary.one_line("native_lean")}
                  >Not a pointwise DSL probe</span>
                  <small>{node["title"]}</small>
                </li>
              </ul>
            </div>
          </div>
          <details>
            <summary>Technical connections: source-backed and inferred</summary><p>
              Source-backed means a direct source reference; inferred means a navigation suggestion, not a proved implication.
            </p>
            <ol id="graph-edges" class="edge-list">
              <li :for={e <- @review["graph_snapshot"]["edges"]}>
                <span>{e["from_id"]} → {e["to_id"]}</span> <b>{e["provenance"]}</b>
                <small>{e["kind"]} · {e["reason"]}</small>
              </li>
            </ol>
          </details>
        </section>
        <div class="review-grid">
          <aside class="pane guarantee" aria-labelledby="claim-heading">
            <p class="eyebrow">Reference</p>
            <h2 id="claim-heading">What the code and rules say</h2>
            <p>
              Use the exact source to check a reading. The
              <.term key="oracle">independent reference</.term>
              is a separate implementation of the policy.
            </p>
            <details>
              <summary>Technical status</summary>
              <p>
                <.term key="formal_checker">Independent proof report</.term>: {Glossary.one_line(
                  @review["source"]["proof_report_snapshot"]["status"]
                )}
              </p>
              <p>
                <.term key="sha256">Loaded evaluator fingerprint</.term>:
                <code>{@review["source"]["evaluator_id"]}</code>
              </p>
              <p>
                Proof status is separate from example checks and human intent. Processor fencing and storage durability remain outside-world assumptions.
              </p>
            </details>
            <button
              type="button"
              id="source-toggle"
              phx-click="toggle_source"
              aria-expanded={@source_open}
            >Browse source evidence</button>
            <div :if={@source_open} id="source-panel" class="source-panel">
              <p>
                Choose a source anchor to inspect exact checkout bytes and digest. The map shows inferred associations separately.
              </p>
              <ul>
                <li :for={s <- @review["graph_snapshot"]["excerpts"]}>
                  <button type="button" phx-click="source_select" phx-value-id={s["id"]}><strong>{Glossary.source_title(
                    s["path"]
                  )}</strong><small>{s["path"]}</small></button>
                  <.link href={"/workbench/#{@review["id"]}/source/#{s["id"]}"} target="_blank">Full source</.link>
                </li>
              </ul>
            </div>
            <div
              :if={@selected_source && source_for(@review, @selected_source)}
              id="selected-source"
              class="source-selected"
            >
              <p><b>{source_for(@review, @selected_source)["path"]}</b></p>
              <p>SHA-256 <code>{source_for(@review, @selected_source)["sha256"]}</code></p>
              <pre>{source_for(@review, @selected_source)["text"]}</pre>
            </div>
            <h3>What is checked by what</h3>
            <dl class="evidence-boundaries">
              <dt>What the rule means</dt><dd>The exact source expressions.</dd><dt>
                Whether the proof was checked
              </dt><dd>A separate Lean checker report, when attached.</dd><dt>
                Whether this is enough in practice
              </dt><dd>Your judgment and processor or storage evidence.</dd>
            </dl>
          </aside>
          <section class="pane arena" aria-labelledby="probe-heading">
            <p class="eyebrow">Test</p>
            <h2 id="probe-heading">Test the scenario</h2><p>
              Edit the example and see what the rules say.
            </p>
            <div class="fixture-strip" aria-label="Synthetic initial examples">
              <button
                :for={seed <- Adversarial.seeds()}
                type="button"
                phx-click="choose_seed"
                phx-value-seed={seed}
                id={"load-#{seed}"}
              >{Glossary.scenario_title(seed)} <small>{seed}</small></button>
            </div>
            <p class="muted">
              Switching scenario starts a new review; your current one is kept. These are invented examples, not observed failures. Edits are temporary until you save the example or answer its question.
            </p>
            <button
              id="reset-draft"
              type="button"
              phx-click="reset_draft"
              disabled={@review["status"] != "in_progress"}
            >Reset to the starting example</button>
            <details class="field-help">
              <summary>What do these fields mean?</summary>
              <p>
                All amounts are integer cents. A key is a remembered request identity and cannot be reused for a new hold.
              </p>
              <dl>
                <dt>Starting state</dt><dd>
                  <code>amount_limit</code>
                  and <code>hold_limit</code>
                  are the two limits; <code>used_amount</code>
                  and <code>used_holds</code>
                  are the totals in use. Each entry has a key, amount and status.
                </dd><dt>Event</dt><dd>A type and, when needed, a key, amount or result.</dd><dt>
                  Outcome
                </dt><dd>
                  <code>after</code>
                  is the next state; <code>result</code>
                  says what happened locally; <code>effects</code>
                  lists requests for outside work.
                </dd><dt>Next event</dt><dd>
                  Optional event calculated from both outcomes. Use <code>null</code> to skip it.
                </dd>
              </dl>
              <p>
                <.term
                  :for={status <- ~w(reserved sent unknown authorized voiding declined voided)}
                  key={status}
                />
              </p>
              <details>
                <summary>Editor limits</summary><p>
                  Typed JSON with integer values from 0 to 1,000,000 and at most eight entries or effects. Use the starting example as a template.
                </p>
              </details>
            </details>
            <.form
              for={@draft_form}
              id="candidate-form"
              phx-change="draft_changed"
              phx-submit="answer_escape"
            >
              <div class="json-fields">
                <.input
                  field={@draft_form[:before_json]}
                  type="textarea"
                  label="Starting state (typed JSON)"
                  rows="7"
                  phx-debounce="100"
                />
                <.input
                  field={@draft_form[:event_json]}
                  type="textarea"
                  label="The event (typed JSON)"
                  rows="3"
                  phx-debounce="100"
                />
                <.input
                  field={@draft_form[:output_json]}
                  type="textarea"
                  label="What-if outcome to judge (typed JSON)"
                  rows="10"
                  phx-debounce="100"
                />
                <.input
                  field={@draft_form[:follow_on_json]}
                  type="textarea"
                  label="Next event after that — optional (typed JSON)"
                  rows="3"
                  phx-debounce="100"
                />
              </div>
              <input type="hidden" name="draft[request_id]" value={@request_id} />
              <input
                type="hidden"
                name="draft[expected_human_revision]"
                value={@review["human_revision"]}
              />
              <input
                type="hidden"
                name="draft[packet_digest]"
                value={@review["source"]["packet_digest"]}
              />
              <input type="hidden" name="draft[card_id]" value={@selected_card_id} />
              <input type="hidden" name="draft[revealed_before_answer]" value={to_string(@revealed)} />
              <label for="escape-reason">Why? A reason helps the next reviewer. To defer, explain what is missing.</label>
              <textarea id="escape-reason" name="draft[reason]" maxlength="600" rows="2"></textarea>
              <p :if={@draft_error} id="draft-error" role="alert" class="notice-alert">
                {@draft_error} · The matrix below, if shown, belongs to the last good input and is historical—not this invalid draft.
              </p>
              <p
                :if={@evaluation && !@draft_error}
                id="candidate-ok"
                role="status"
                class="neutral-tag"
              >
                Your edited example is well-formed. Does the alternative end in a valid ledger state? {if @details.candidate_after_valid?,
                  do: "Yes.",
                  else: "No."} Does the real ledger match the reference? {if @details.actual_equals_oracle?,
                  do: "Yes.",
                  else: "No."}
              </p>
              <div
                :if={@current_card && @current_card["kind"] == "escape"}
                class="answer-actions"
                aria-label="Escape judgment"
              >
                <button
                  type="submit"
                  name="draft[choice]"
                  value="acceptable"
                  disabled={@draft_error != nil}
                  id="escape-acceptable"
                >Acceptable</button>
                <button
                  type="submit"
                  name="draft[choice]"
                  value="unacceptable"
                  disabled={@draft_error != nil}
                  id="escape-unacceptable"
                  class="primary"
                >Unacceptable</button>
                <button
                  type="submit"
                  name="draft[choice]"
                  value="unsure"
                  disabled={@draft_error != nil}
                  id="escape-unsure"
                >Not sure</button>
                <button
                  type="submit"
                  name="draft[choice]"
                  value="deferred"
                  disabled={@draft_error != nil}
                  id="escape-deferred"
                >Defer</button>
                <button
                  type="submit"
                  name="draft[choice]"
                  value="pin_only"
                  disabled={@draft_error != nil}
                  id="pin-candidate"
                >Save example only</button>
              </div>
            </.form>
            <dl class="choice-legend">
              <div :for={choice <- ~w(acceptable unacceptable unsure deferred pin_only)}>
                <dt>{Glossary.label(choice)}</dt><dd>{Glossary.one_line(choice)}</dd>
              </div>
            </dl>
            <div :if={@evaluation} id="computed-contrast" class="comparison">
              <p :if={@draft_error} class="muted">
                <b>Historical last-good evaluation only</b> · not the draft currently shown
              </p>
              <div>
                <b>What the real ledger does (reducer)</b><.narrated value={@evaluation["actual"]} />
              </div>
              <div>
                <b>What the independent reference says (Spec/oracle)</b><.narrated value={
                  @evaluation["oracle"]
                } />
              </div>
              <div>
                <b>The what-if you are judging (locally calculated)</b>
                <%= if @current_witness do %>
                  <.narrated value={@current_witness["output"]} />
                <% else %>
                  <p>Invalid draft; hypothetical unavailable.</p>
                <% end %>
              </div>
              <div :if={@details && !@draft_error} id="diff-panel">
                <b>These outcomes differ in:</b>
                <ul>
                  <li :for={diff <- @details.changed_fields}>
                    <strong>{case diff["field"] do
                      "after" -> "Ledger state"
                      "result" -> "Local result"
                      "effects" -> "Outside-work requests"
                    end}</strong><p>Real ledger: {Explain.value(diff["field"], diff["actual"])}</p><p>
                      Alternative: {Explain.value(diff["field"], diff["hypothetical"])}
                    </p><details>
                      <summary>Exact changed values</summary><pre>{Jason.encode!(diff, pretty: true)}</pre>
                    </details>
                  </li>
                </ul>
                <details :if={@details.request_eligible? != nil}>
                  <summary>
                    Can this fresh request be admitted? {if @details.request_eligible?,
                      do: "Yes",
                      else: "No"}
                  </summary><p>
                    Spec.request_eligible? at this input: <b>{@details.request_eligible?}</b>
                    (fresh request only)
                  </p>
                </details>
              </div>
            </div>
            <section id="follow-on-area" aria-label="Second-Event Consequence">
              <h3>What happens next?</h3><p>
                We calculate one more event from each outcome to see the knock-on effect, such as whether a new request can be admitted.
              </p>
              <%= if @evaluation && @evaluation["follow_on_actual"] == nil && @evaluation["follow_on_candidate"] == nil && (@details == nil || @details.follow_reason == :no_follow_on_event) do %>
                <p id="no-follow-on" class="muted">No follow-on event selected for this probe.</p>
              <% else %>
                <%= if @evaluation do %>
                  <div>
                    After the real outcome: <.narrated value={@evaluation["follow_on_actual"]} />
                  </div>
                  <div>
                    After the alternative: <.narrated value={@evaluation["follow_on_candidate"]} />
                  </div>
                  <p :if={@evaluation["follow_on_candidate"] == nil} class="muted">
                    A Spec-invalid hypothetical cannot be stepped further; no second call was made.
                  </p>
                <% end %>
              <% end %>
            </section>
            <section id="catcher-matrix" class="matrix">
              <h3>What the rules say about this example</h3><button type="button" phx-click="reveal">I’ve made my prediction — show what the rules say</button><p>
                Recording whether you looked first helps keep your judgment honest.
              </p><dl class="matrix-legend">
                <div :for={key <- ~w(catches allows_here does_not_apply cant_check)}>
                  <dt>{status_label(key)}</dt><dd>{Glossary.one_line(key)}</dd>
                </div>
              </dl>
              <p class="muted">
                Catches · Allows here · Doesn't apply · Can't check. Every result is for named bindings only; the rest of the full catalog is unexamined.
              </p>
              <table :if={@revealed || @matrix_open}>
                <thead>
                  <tr>
                    <th>Original law</th><th>Candidate here</th><th>Bindings</th>
                  </tr>
                </thead>
                <tbody>
                  <tr :for={row <- if(@evaluation, do: @evaluation["law_rows"], else: [])}>
                    <td>
                      <strong>{Glossary.law_description(row["slug"])}</strong><small>{row["slug"]}</small>
                    </td><td>
                      <span class={"status status-#{row["label"]}"}>{status_label(row["label"])}</span><details>
                        <summary>Why this result?</summary><code>{row["reason"]}</code>
                      </details>
                    </td><td>
                      Tested {row["bindings_tested"]} combinations of values · {if row[
                                                                                     "exhaustive_for_source_domain"
                                                                                   ],
                                                                                   do:
                                                                                     "covers all of them",
                                                                                   else:
                                                                                     "only some of them"}
                    </td>
                  </tr>
                </tbody>
              </table>
              <button
                id="matrix-toggle"
                type="button"
                phx-click="toggle_matrix"
                aria-expanded={@matrix_open}
              >Raw technical output (also reveals analysis)</button>
              <pre :if={@matrix_open && @details} id="matrix-diagnostics">{inspect(@details.checks, pretty: true, limit: 500)}</pre>
              <p class="muted">
                Formal native Lean obligations are <b>not a pointwise DSL probe</b>; open the design map for the full remainder and independent checker state.
              </p>
            </section>
          </section>
          <aside class="pane decision" aria-labelledby="decision-heading">
            <p class="eyebrow">03 / HUMAN DECISION</p>
            <h2 id="decision-heading">Your judgment</h2>
            <p>Answer one question at a time. Revisions keep the earlier answer in your history.</p>
            <%= if @current_card do %>
              <article id="active-question" class="active-question">
                <p class="eyebrow">
                  {Glossary.label(@current_card["kind"])} · {if(@current_card["critical"],
                    do: "critical: #{@current_card["critical_reason"]}",
                    else: "scoped review"
                  )}
                </p>
                <h3>{@current_card["question"]}</h3>
                <p>{Glossary.one_line(@current_card["kind"])}</p><p>
                  <b>Why it matters:</b> {if @current_card["critical"],
                    do: @current_card["critical_reason"],
                    else: "Your answer defines what this review can conclude."}
                </p><p>
                  Look at the scenario, computed comparison and exact source in the reference pane.
                </p><details>
                  <summary>Question reference</summary><code>{@current_card["target_node_id"]}</code>
                </details>
                <button id="reveal-analysis" type="button" phx-click="reveal">I’ve made my prediction — show what the rules say</button>
                <p :if={@revealed} class="neutral-tag">Analysis was revealed before this answer.</p>
                <div
                  :if={last_answer(@review, @current_card["id"])}
                  id="latest-answer"
                  data-choice={last_answer(@review, @current_card["id"])["choice"]}
                >
                  <b>Latest: {Glossary.label(last_answer(@review, @current_card["id"])["choice"])}</b>
                  <p>{implication(@review, @current_card)}</p><small>{last_answer(
                    @review,
                    @current_card["id"]
                  )["choice"]} · You may revise; history remains.</small>
                </div>
                <%= if @current_card["kind"] == "escape" do %>
                  <p>
                    Use the buttons under the example in Test the scenario. Your answer saves the complete example and its computed results together.
                  </p>
                <% else %>
                  <.form for={@answer_form} id="card-answer-form" phx-submit="answer_card">
                    <label for="card-reason">Reason / source correction</label>
                    <.input
                      field={@answer_form[:reason]}
                      id="card-reason"
                      type="textarea"
                      rows="3"
                      maxlength="600"
                    />
                    <div class="answer-actions">
                      <button
                        :for={choice <- Dossier.choices(@current_card["kind"])}
                        type="submit"
                        name="judgment[choice]"
                        value={choice}
                      >{Glossary.label(choice)}</button>
                    </div>
                    <dl class="choice-legend">
                      <div :for={choice <- Dossier.choices(@current_card["kind"])}>
                        <dt>{Glossary.label(choice)}</dt><dd>{Glossary.one_line(choice)}</dd>
                      </div>
                    </dl>
                  </.form>
                <% end %>
              </article>
            <% end %>
            <nav id="question-nav" aria-label="Review questions" class="card-nav">
              <button
                :for={card <- cards(@review)}
                id={
                  if(card["origin"] == "deterministic",
                    do: "card-#{card["kind"]}",
                    else: "card-#{card["id"]}"
                  )
                }
                type="button"
                class={if(card["id"] == @selected_card_id, do: "selected", else: "")}
                phx-click="select_card"
                phx-value-id={card["id"]}
              >
                <strong>{Glossary.label(card["kind"])}</strong><span>{if(card["mandatory"],
                  do: "Required",
                  else: "Optional"
                )} <small>{card["kind"]}</small></span>
                <small>{if(last_answer(@review, card["id"]),
                  do: "Answered: " <> Glossary.label(last_answer(@review, card["id"])["choice"]),
                  else: "Not answered"
                )}</small>
              </button>
            </nav>
            <section id="review-summary" class="review-summary">
              <h3>Conclude this review</h3><.progress review={@review} /><p>
                Confirming locks this review and includes your scoped conclusion in the export. You can export an unfinished review too.
              </p><dl class="choice-legend">
                <div :for={
                  outcome <-
                    ~w(needs_policy_or_evidence needs_design_change meets_intent_in_reviewed_scope)
                }>
                  <dt>{Glossary.label(outcome)}</dt><dd>{Glossary.one_line(outcome)}</dd>
                </div>
              </dl><ul class="required-checklist">
                <li :for={card <- cards(@review)} :if={card["mandatory"]}>
                  Required: {Glossary.label(card["kind"])} — {if last_answer(@review, card["id"]),
                    do: Glossary.label(last_answer(@review, card["id"])["choice"]),
                    else: "Not answered"}
                </li>
              </ul>
              <p>
                Review can be exported unfinished. Mandatory/critical questions must be answered or explicitly deferred before concluding. A positive outcome also requires the optional questions to be resolved, saved supporting evidence, and no computed conflicts. Deferrals stay open.
              </p>
              <p>
                This conclusion covers: {Glossary.review_title(@review)}. Edit the references below if your scope differs.
              </p>
              <.form for={@finish_form} id="finish-form" phx-submit="finish_review">
                <.input
                  field={@finish_form[:scope]}
                  type="textarea"
                  label="What this conclusion covers (policy references below)"
                  rows="2"
                  value={Enum.join(@review["target_policy_nodes"], ", ")}
                />
                <.input
                  field={@finish_form[:rationale]}
                  type="textarea"
                  label="Human rationale (required)"
                  rows="2"
                />
                <label for="review-outcome">Choose one explicit outcome</label>
                <select id="review-outcome" name="finish[outcome]">
                  <option value="needs_policy_or_evidence">Needs policy or evidence</option>
                  <option value="needs_design_change">Needs design change</option>
                  <option value="meets_intent_in_reviewed_scope">
                    Meets intent in reviewed scope
                  </option>
                </select>
                <button
                  type="submit"
                  disabled={@review["status"] != "in_progress"}
                  id="confirm-finish"
                >Confirm human conclusion</button>
              </.form>
              <p :if={@review["review_conclusion"]}>
                <b>Human conclusion:</b> {Glossary.label(@review["review_conclusion"]["outcome"])}
                <small>{@review["review_conclusion"]["outcome"]}</small>
              </p>
            </section>
            <details
              id="ai-collaboration"
              class="ai-panel"
              aria-label="Optional configured model assistance"
            >
              <summary>Optional: ask an AI to suggest questions or counter-examples</summary>
              <p class="muted">
                Source-only discovery precedes answers; challenge sends the displayed draft;
                follow-up sends the selected card's recorded human answer and computed evidence.
                The configured external inference provider receives data only on your explicit opt-in.
                Model suggestions never certify a proof or change your answer.
              </p>
              <p :if={!@ai_capability} class="notice-alert" id="ai-unavailable">
                AI unavailable: configured provider or JSON Schema capability is not ready.
                All deterministic checks and human decisions remain available.
              </p>
              <label class="ai-consent-label" for="ai-consent">
                <input
                  id="ai-consent"
                  type="checkbox"
                  checked={@ai_consent}
                  phx-click="toggle_ai_consent"
                />
                Opt in to sending selected source and, for challenge/follow-up, draft or reviewer data
                to the configured inference service for this one request.
              </label>
              <div class="ai-actions">
                <button
                  id="ai-deck"
                  type="button"
                  phx-click="ai_request"
                  phx-value-kind="deck"
                  disabled={!@ai_consent || !@ai_capability || @review["status"] != "in_progress"}
                >Discover questions</button>
                <button
                  id="ai-challenge"
                  type="button"
                  phx-click="ai_request"
                  phx-value-kind="challenge"
                  disabled={
                    !@ai_consent || !@ai_capability || @draft_error != nil ||
                      @review["status"] != "in_progress"
                  }
                >Propose what-if</button>
                <button
                  id="ai-followup"
                  type="button"
                  phx-click="ai_request"
                  phx-value-kind="followup"
                  disabled={
                    !@ai_consent || !@ai_capability || @review["status"] != "in_progress" ||
                      is_nil(last_answer(@review, @selected_card_id))
                  }
                >Challenge my answer</button>
              </div>
              <p class="muted">
                Failed or interrupted jobs need an explicit new request. There is no automatic retry.
              </p>
              <ol id="ai-job-history" class="ai-job-list">
                <li :for={job <- @review["ai_jobs"]} id={"ai-job-#{job["job_id"]}"}>
                  <strong>{job["request_kind"]}</strong>
                  · <.term key={job["status"]} />
                  <span :if={job["error_class"]}>· {job["error_class"]}</span>
                  <%= if job["status"] == "complete" && is_map(job["validated_output"]) do %>
                    <div :if={job["request_kind"] == "deck"} class="ai-results">
                      <h4>Computed predictions (shown before AI paraphrases)</h4>
                      <ul :for={check <- job["validated_output"]["reading_checks"]}>
                        <li :for={p <- check["predictions"]}>
                          <b>{check["claim_slug"]} / {p["probe_id"]}</b>: {p["verification"]}; predicted {p[
                            "predicted_status"
                          ]}, computed {p["actual_status"] || "unsupported"}
                          <details>
                            <summary>Computed witness</summary><pre>{Jason.encode!(p["computed_example"], pretty: true)}</pre>
                          </details>
                        </li>
                      </ul>
                      <h4>Model hypotheses and readings · unapproved proposals</h4>
                      <p :for={item <- job["validated_output"]["deck"]["intent_hypotheses"]}>
                        <b>{item["statement"]}</b> — {item["distinguishing_question"]}
                        <small>Sources: {source_names(@review, item["source_ids"])}</small>
                      </p>
                      <p :for={reading <- job["validated_output"]["deck"]["readings"]}>
                        <b>{reading["claim_slug"]}</b>: {reading["summary"]}
                        <small>Not asserted: {reading["not_claimed"]}. Sources: {source_names(
                          @review,
                          reading["source_ids"]
                        )}</small>
                      </p>
                      <div
                        :for={unknown <- job["validated_output"]["deck"]["uncertainties"]}
                        class="muted"
                      >
                        Open: {unknown["question"]} · Needed: {unknown["missing_evidence"]}.
                        Sources: {source_names(@review, unknown["source_ids"])}
                      </div>
                      <p class="muted">
                        Duplicate suggestions withheld: {job["validated_output"]["deduplicated_count"]}.
                      </p>
                    </div>
                    <div :if={job["request_kind"] == "challenge"} class="ai-results">
                      <h4>Typed AI hypothetical · not pinned</h4>
                      <p>{job["validated_output"]["challenge"]["selection_reason"]}</p>
                      <p class="muted">
                        Sources: {source_names(
                          @review,
                          job["validated_output"]["challenge"]["source_ids"]
                        )}
                      </p>
                      <p>Computed result is pointwise, not a proof verdict.</p>
                      <pre>{Jason.encode!(job["validated_output"]["evaluation"]["law_rows"], pretty: true)}</pre>
                      <button
                        type="button"
                        phx-click="try_ai_challenge"
                        phx-value-job={job["job_id"]}
                        disabled={@review["status"] != "in_progress"}
                      >Try proposal in draft (no save)</button>
                    </div>
                    <div :if={job["request_kind"] == "followup"} class="ai-results">
                      <h4>Model's response to the recorded human choice</h4>
                      <p>{job["validated_output"]["followup"]["question"]}</p>
                      <p>{job["validated_output"]["followup"]["explanation"]}</p>
                      <p class="muted">{job["validated_output"]["followup"]["uncertainty"]}</p>
                      <p class="muted">
                        Sources: {source_names(
                          @review,
                          job["validated_output"]["followup"]["source_ids"]
                        )}
                      </p>
                    </div>
                  <% end %>
                </li>
              </ol>
              <%= if @review["suggested_ai_cards"] != [] do %>
                <h4>Suggestions (AI) · accept deliberately</h4>
                <ul id="ai-suggestions" class="ai-job-list">
                  <li :for={card <- @review["suggested_ai_cards"]} id={"suggest-#{card["id"]}"}>
                    <b>{Glossary.label(card["kind"])}</b>
                    · {card["question"]}
                    <p class="muted">Source: {source_names(@review, card["source_ids"])}</p>
                    <button
                      type="button"
                      phx-click="accept_ai_card"
                      phx-value-id={card["id"]}
                      disabled={@review["status"] != "in_progress"}
                    >Accept question into human review</button>
                  </li>
                </ul>
              <% end %>
            </details>
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
