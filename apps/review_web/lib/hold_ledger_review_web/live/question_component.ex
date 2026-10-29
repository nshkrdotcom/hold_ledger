defmodule HoldLedgerReviewWeb.QuestionComponent do
  @moduledoc false
  use HoldLedgerReviewWeb, :live_component
  alias HoldLedgerReview.{QuestionContext, Questions, Trace}

  @impl true
  def mount(socket) do
    {:ok,
     assign(socket,
       open: false,
       text: "",
       packet: nil,
       active: nil,
       consent: false,
       query: "",
       history: [],
       history_open: false,
       history_scope: "case",
       history_offset: 0,
       error: nil,
       composing: true,
       clearing: false,
       previous: [],
       followup_context: nil,
       actor: "local-operator:" <> Trace.token()
     )}
  end

  @impl true
  def update(%{context: context} = assigns, socket) do
    changed =
      socket.assigns[:context] &&
        QuestionContext.context_id(context) != QuestionContext.context_id(socket.assigns.context)

    old = socket.assigns[:context]

    if connected?(socket) && (is_nil(old) || old.doc["id"] != context.doc["id"]) do
      if old,
        do: Phoenix.PubSub.unsubscribe(HoldLedgerReview.PubSub, "questions:" <> old.doc["id"])

      Phoenix.PubSub.subscribe(HoldLedgerReview.PubSub, "questions:" <> context.doc["id"])
    end

    socket = socket |> assign(assigns) |> assign(:ready, connected?(socket))
    socket = if changed, do: assign(socket, packet: nil, consent: false), else: socket
    {:ok, socket}
  end

  def update(%{request_id: id}, socket) do
    socket =
      if socket.assigns.active && socket.assigns.active["id"] == id,
        do: assign(socket, active: Questions.get(id), composing: false),
        else: socket

    {:ok, socket}
  end

  @impl true
  def handle_event("open", _, socket),
    do: {:noreply, assign(socket, open: true, history_open: false)}

  def handle_event("close", _, socket),
    do: {:noreply, assign(socket, open: false, consent: false, clearing: false)}

  def handle_event("new", _, socket),
    do:
      {:noreply,
       assign(socket,
         open: true,
         composing: true,
         history_open: false,
         text: "",
         packet: nil,
         consent: false,
         previous: [],
         followup_context: nil,
         error: nil
       )}

  def handle_event("text", %{"question" => %{"text" => text}}, socket),
    do: {:noreply, assign(socket, text: text, packet: nil, consent: false)}

  def handle_event("prepare", %{"question" => %{"text" => text}}, socket) do
    with {:ok, packet} <-
           QuestionContext.prepare(
             text,
             socket.assigns.followup_context || socket.assigns.context,
             socket.assigns.actor,
             socket.assigns.previous
           ),
         {:ok, row} <- Questions.prepare(packet) do
      {:noreply,
       assign(socket,
         text: text,
         packet: packet,
         active: row,
         consent: false,
         open: true,
         history_open: false,
         error: nil,
         composing: true
       )}
    else
      _ ->
        {:noreply,
         assign(socket,
           open: true,
           error: "Couldn't prepare this question. Check the source context and local log."
         )}
    end
  end

  def handle_event("consent", %{"question" => values}, socket),
    do: {:noreply, assign(socket, consent: values["consent"] == "true")}

  def handle_event("send", _, socket) do
    packet = socket.assigns.packet

    with true <- socket.assigns.consent and is_map(packet),
         true <-
           packet["context_id"] ==
             QuestionContext.context_id(socket.assigns.followup_context || socket.assigns.context),
         :ok <- Questions.ask(socket.assigns.active["id"], packet["digest"], true) do
      {:noreply,
       assign(socket,
         active: Questions.get(socket.assigns.active["id"]),
         consent: false,
         composing: false,
         error: nil
       )}
    else
      _ ->
        {:noreply,
         assign(socket,
           consent: false,
           error:
             "This question wasn't sent. Prepare the current case and authorize that request."
         )}
    end
  end

  def handle_event("cancel", _, socket) do
    Questions.cancel(socket.assigns.active["id"])
    {:noreply, assign(socket, active: Questions.get(socket.assigns.active["id"]), consent: false)}
  end

  def handle_event("history", _, socket) do
    {:noreply,
     load_history(
       assign(socket,
         open: true,
         composing: false,
         history_open: true,
         history_offset: 0,
         clearing: false,
         error: nil
       )
     )}
  end

  def handle_event("search", %{"history" => %{"query" => query}}, socket),
    do: {:noreply, load_history(assign(socket, query: query, history_offset: 0))}

  def handle_event("history_scope", %{"scope" => scope}, socket) when scope in ["case", "all"],
    do: {:noreply, load_history(assign(socket, history_scope: scope, history_offset: 0))}

  def handle_event("history_page", %{"offset" => offset}, socket) do
    case Integer.parse(offset) do
      {n, ""} when n >= 0 -> {:noreply, load_history(assign(socket, history_offset: n))}
      _ -> {:noreply, socket}
    end
  end

  def handle_event("recall", %{"id" => id}, socket),
    do:
      {:noreply,
       assign(socket,
         active: Questions.get(id),
         packet: nil,
         composing: false,
         consent: false,
         history_open: false,
         history: [],
         error: nil
       )}

  def handle_event("followup", _, socket) do
    row = socket.assigns.active

    previous = [
      %{
        "question" => row["packet"]["question"],
        "answer" => row["answer"],
        "context_id" => row["packet"]["context_id"]
      }
    ]

    case historical_context(row) do
      nil ->
        {:noreply,
         assign(socket,
           error: "The original case is unavailable. Use the current case for a new question."
         )}

      context ->
        {:noreply,
         assign(socket,
           text: "",
           packet: nil,
           composing: true,
           consent: false,
           previous: previous,
           followup_context: context
         )}
    end
  end

  def handle_event("clear", _, socket), do: {:noreply, assign(socket, clearing: true)}
  def handle_event("keep", _, socket), do: {:noreply, assign(socket, clearing: false)}

  def handle_event("confirm_clear", _, socket) do
    case Questions.clear() do
      :ok ->
        {:noreply,
         assign(socket,
           history: [],
           active: nil,
           packet: nil,
           consent: false,
           clearing: false,
           composing: true
         )}

      _ ->
        {:noreply,
         assign(socket, error: "History couldn't be cleared while a question is running.")}
    end
  end

  defp load_history(socket) do
    conversation = if socket.assigns.history_scope == "case", do: socket.assigns.context.doc["id"]

    assign(socket,
      history:
        Questions.list(
          socket.assigns.query,
          Questions,
          conversation,
          socket.assigns.history_offset
        )
    )
  end

  defp historical_context(row) do
    packet = row["packet"]

    case Trace.get(packet["conversation"]) do
      {:ok, doc} ->
        %{
          doc: doc,
          slug: packet["context"]["slug"],
          case: packet["context"]["case"],
          basis: packet["context"]["basis"],
          binding_index: packet["context"]["binding_index"],
          selection: nil,
          package: packet["context"]["comparison"]
        }

      _ ->
        nil
    end
  end

  defp running?(row), do: row && row["status"] == "running"
  defp answer?(row), do: row && is_map(row["answer"])

  defp source_url(packet, source),
    do: "/claims/#{packet["context"]["slug"]}/source/#{source["id"]}/#{source["sha256"]}"

  defp export(row),
    do:
      "data:application/json;charset=utf-8," <>
        URI.encode(Jason.encode!(row), &URI.char_unreserved?/1)

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns,
        health: Questions.health(),
        earlier:
          assigns.active &&
            assigns.active["packet"]["context_id"] != QuestionContext.context_id(assigns.context)
      )

    ~H"""
    <div
      id="question-assistant"
      class="question-assistant"
      phx-hook="QuestionPanel"
      data-target={@myself}
    >
      <div class="question-bar">
        <button
          :if={answer?(@active) && !@composing}
          id="question-preview"
          class="question-preview"
          phx-click="open"
          phx-target={@myself}
          title={@active["answer"]["summary"]}
        >
          <span>{@active["answer"]["summary"]}</span><span aria-hidden="true">↗</span>
        </button>
        <button :if={running?(@active)} class="question-preview" phx-click="open" phx-target={@myself}>Answering…</button>
        <.form
          :if={@composing && !running?(@active)}
          for={to_form(%{}, as: :question)}
          id="header-question-form"
          phx-submit="prepare"
          phx-change="text"
          phx-target={@myself}
        >
          <.input
            type="text"
            name="question[text]"
            value={@text}
            label="Question about this case"
            placeholder="Ask about this case…"
            disabled={!@ready}
            maxlength="4096"
          />
          <button type="submit" phx-disable-with="Preparing…">Ask</button>
        </.form>
        <button class="question-mobile-open" phx-click="new" phx-target={@myself}>Ask</button>
        <button
          :if={!@composing && !running?(@active)}
          phx-click="new"
          phx-target={@myself}
          aria-label="Ask another question"
        >+</button>
        <button
          id="question-history"
          disabled={!@ready}
          phx-click="history"
          phx-target={@myself}
          aria-controls="question-panel"
          aria-expanded={to_string(@open)}
        >History</button>
      </div>
      <section
        :if={@open}
        id="question-panel"
        class="question-panel"
        aria-label="Ask about this case"
        tabindex="-1"
        data-open="true"
      >
        <header>
          <h2>Ask about this case</h2><button
            id="question-close"
            phx-click="close"
            phx-target={@myself}
            aria-label="Close answer"
          >Close</button>
        </header>
        <p :if={@health != :ok} role="alert">
          The local question log is unavailable. Questions won't be sent.
        </p>
        <p :if={@error} role="alert">{@error}</p>
        <div :if={@active && !@composing && !@history_open} id="question-answer">
          <h3>{@active["packet"]["question"]}</h3>
          <p :if={@earlier} id="question-earlier" class="scope-note">Answer to an earlier case</p>
          <p :if={running?(@active)} role="status">
            Answering… <button phx-click="cancel" phx-target={@myself}>Cancel</button>
          </p>
          <div :if={answer?(@active)} class="answer-body">
            <strong>{@active["answer"]["summary"]}</strong>
            <p class="answer-explanation">{@active["answer"]["explanation"]}</p>
            <ul :if={@active["answer"]["limits"] != []}>
              <li :for={limit <- @active["answer"]["limits"]}>{limit}</li>
            </ul>
            <nav class="answer-sources" aria-label="Answer sources">
              <a
                :for={source <- @active["packet"]["context"]["sources"]}
                :if={source["id"] in @active["answer"]["source_ids"]}
                href={source_url(@active["packet"], source)}
                target="_blank"
                rel="noopener"
              >{source["path"]}</a>
            </nav>
            <span class="scope-note">AI answer</span>
          </div>
          <p :if={@active["error"]} role="status">{@active["status"]}: {@active["error"]}</p>
          <p :if={@active["persistence_error"]} role="alert">
            This answer couldn't be saved. Copy it before closing.
          </p>
          <div class="question-actions">
            <button :if={answer?(@active)} phx-click="followup" phx-target={@myself}>Ask a follow-up</button>
            <button phx-click="new" phx-target={@myself}>Ask using current case</button>
            <a href={export(@active)} download={"question-#{@active["id"]}.json"}>Export this question</a>
            <button
              :if={answer?(@active)}
              type="button"
              data-copy-answer={@active["packet"]["question"] <> "\n\n" <> @active["answer"]["summary"] <> "\n\n" <> @active["answer"]["explanation"] <> "\n\nContext: " <> @active["packet"]["digest"]}
            >Copy</button>
          </div>
        </div>
        <.form
          :if={@composing}
          for={to_form(%{}, as: :question)}
          id="panel-question-form"
          phx-submit="prepare"
          phx-change="text"
          phx-target={@myself}
        >
          <.input
            type="textarea"
            name="question[text]"
            value={@text}
            label="Your question"
            maxlength="4096"
          />
          <p :if={@previous != []} class="scope-note">
            The selected earlier question and generated answer will be included, using that question’s case. Review Context before sending.
          </p>
          <button type="submit">Prepare question</button>
        </.form>
        <details :if={(@packet || @active) && !@history_open} id="question-context">
          <summary>Context · {(@packet || @active["packet"])["model"]} · medium</summary>
          <p>
            Shares the question, selected case, policy, core source and reviewed proof passages listed here. Logs remain local.
          </p>
          <p><code>{(@packet || @active["packet"])["digest"]}</code></p>
          <p :for={source <- (@packet || @active["packet"])["context"]["sources"]}>
            <strong>{source["path"]}</strong> <code>{source["sha256"]}</code>
          </p>
          <details>
            <summary>Exact application prompt</summary><pre>{Jason.encode!((@packet || @active["packet"])["messages"], pretty: true)}</pre>
          </details>
          <p>
            Other repository sources, external attestations and private review notes are not included.
          </p>
        </details>
        <.form
          :if={@packet && @active && @active["status"] == "prepared" && !@history_open}
          for={to_form(%{}, as: :question)}
          id="question-consent-form"
          phx-submit="send"
          phx-change="consent"
          phx-target={@myself}
        >
          <.input
            type="checkbox"
            id="question-consent"
            name="question[consent]"
            checked={@consent}
            value="true"
            label="Share this question, source and case with Codex"
          />
          <button
            id="question-send"
            type="submit"
            disabled={!@consent || @health != :ok}
            phx-disable-with="Sending…"
          >Send to Codex</button>
        </.form>
        <section :if={@history_open} id="question-history-list">
          <h3>Local history</h3>
          <nav class="question-actions" aria-label="History scope">
            <button
              phx-click="history_scope"
              phx-value-scope="case"
              phx-target={@myself}
              aria-pressed={to_string(@history_scope == "case")}
            >This session</button>
            <button
              phx-click="history_scope"
              phx-value-scope="all"
              phx-target={@myself}
              aria-pressed={to_string(@history_scope == "all")}
            >All questions</button>
          </nav>
          <.form for={to_form(%{}, as: :history)} phx-change="search" phx-target={@myself}>
            <.input
              name="history[query]"
              value={@query}
              type="search"
              label="Search questions and answers"
              phx-debounce="200"
            />
          </.form>
          <ul>
            <li :for={row <- @history}>
              <button phx-click="recall" phx-value-id={row["id"]} phx-target={@myself}>{row["packet"][
                "question"
              ]}</button>
              <small>{row["created_at"]} · {row["status"]}</small>
              <p :if={row["answer"]}>{row["answer"]["summary"]}</p>
            </li>
          </ul>
        </section>
        <div :if={@history_open} class="question-actions">
          <button
            :if={@history_offset > 0}
            phx-click="history_page"
            phx-value-offset={max(0, @history_offset - 50)}
            phx-target={@myself}
          >Newer questions</button>
          <button
            :if={length(@history) == 50}
            phx-click="history_page"
            phx-value-offset={@history_offset + 50}
            phx-target={@myself}
          >Older questions</button>
        </div>
        <p :if={@history_open && @history == []} class="scope-note">
          No local questions yet.
        </p>
        <div :if={@history_open} class="question-actions">
          <button phx-click="new" phx-target={@myself}>New question</button>
          <button phx-click="clear" phx-target={@myself}>Clear history…</button>
        </div>
        <div :if={@clearing} class="clear-question-history">
          <p>
            Delete all local question prompts and answers? Saved cases and review notes are unchanged.
          </p>
          <button phx-click="confirm_clear" phx-target={@myself}>Delete question history</button><button
            phx-click="keep"
            phx-target={@myself}
          >Keep history</button>
        </div>
      </section>
      <span id="question-announcement" class="sr-only" aria-live="polite">{if answer?(@active),
        do: "Answer ready"}</span>
    </div>
    """
  end
end
