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
       query: "",
       history: [],
       history_open: false,
       history_scope: "case",
       history_offset: 0,
       error: nil,
       error_detail: nil,
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
    socket = if changed, do: assign(socket, packet: nil), else: socket
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
    do: {:noreply, assign(socket, open: false, clearing: false)}

  def handle_event("new", _, socket),
    do:
      {:noreply,
       assign(socket,
         open: true,
         composing: true,
         history_open: false,
         text: "",
         packet: nil,
         previous: [],
         followup_context: nil,
         error: nil
       )}

  def handle_event("text", %{"question" => %{"text" => text}}, socket),
    do: {:noreply, assign(socket, text: text, packet: nil)}

  def handle_event("inspect_context", _, socket) do
    context = socket.assigns.followup_context || socket.assigns.context

    case QuestionContext.prepare(
           socket.assigns.text,
           context,
           socket.assigns.actor,
           socket.assigns.previous
         ) do
      {:ok, packet} ->
        {:noreply, assign(socket, packet: packet, open: true, history_open: false, error: nil)}

      {:error, reason} ->
        {:noreply,
         assign(socket,
           open: true,
           history_open: false,
           error: context_error(reason),
           error_detail: inspect(reason)
         )}
    end
  end

  def handle_event("ask", %{"question" => %{"text" => text, "context_id" => context_id}}, socket) do
    context = socket.assigns.followup_context || socket.assigns.context

    with {:ready, true} <-
           {:ready, socket.assigns.composing and not running?(socket.assigns.active)},
         {:case, true} <- {:case, context_id == QuestionContext.context_id(context)},
         {:packet, {:ok, packet}} <-
           {:packet,
            QuestionContext.prepare(text, context, socket.assigns.actor, socket.assigns.previous)},
         {:log, {:ok, row}} <- {:log, Questions.prepare(packet)},
         {:dispatch, :ok} <- {:dispatch, Questions.ask(row["id"], packet["digest"], true)} do
      {:noreply,
       assign(socket,
         text: text,
         packet: packet,
         active: Questions.get(row["id"]),
         open: true,
         history_open: false,
         error: nil,
         composing: false
       )}
    else
      failure ->
        {:noreply,
         assign(socket,
           text: text,
           open: true,
           error: submission_error(failure),
           error_detail: inspect(failure)
         )}
    end
  end

  def handle_event("cancel", _, socket) do
    Questions.cancel(socket.assigns.active["id"])
    {:noreply, assign(socket, active: Questions.get(socket.assigns.active["id"]))}
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
           clearing: false,
           composing: true
         )}

      _ ->
        {:noreply,
         assign(socket,
           error:
             "Question history could not be cleared. A question may still be running, " <>
               "or the history files may be unavailable."
         )}
    end
  end

  defp submission_error({:case, false}),
    do:
      "Your question wasn't sent because the case changed. Check this case and press Ask an assistant again."

  defp submission_error({:ready, false}),
    do:
      "Your question wasn't sent. Cancel the current request or choose Ask using current case to start another."

  defp submission_error({:packet, {:error, reason}}), do: context_error(reason)

  defp submission_error({:log, _}),
    do:
      "Your question wasn't sent because its local history could not be saved or its source packet is stale. See technical details."

  defp submission_error({:dispatch, _}),
    do:
      "Your question wasn't sent. Another request may be running, or the prepared source packet is no longer current. See technical details."

  defp context_error(:empty_question), do: "Enter a question before sending."

  defp context_error(:question_too_long),
    do: "The question exceeds 4,096 bytes. Shorten it before sending."

  defp context_error(:question_context_too_large),
    do:
      "Nothing was sent: the included case and conversation exceed the 96 KiB context limit. Start a new question without earlier answers or use a smaller case."

  defp context_error(:stale_case_sources),
    do: "The source files changed since this case was opened. Reopen the claim before sending."

  defp context_error(_),
    do:
      "Your question wasn't sent because its source could not be read. Reopen the claim. Technical details are below."

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

  defp running?(row), do: is_map(row) and row["status"] == "running"
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
        send_context_id: QuestionContext.context_id(assigns.followup_context || assigns.context),
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
          phx-submit="ask"
          phx-change="text"
          phx-target={@myself}
        >
          <.input
            type="text"
            name="question[text]"
            value={@text}
            label="Question about this case"
            placeholder="What does this case tell us?"
            disabled={!@ready}
            maxlength="4096"
          />
          <input type="hidden" name="question[context_id]" value={@send_context_id} />
          <button
            type="submit"
            aria-describedby="question-sharing question-provider"
            disabled={!@ready || @health != :ok}
            phx-disable-with="Sending…"
          >Ask an assistant</button>
        </.form>
        <button
          :if={@composing}
          id="question-sharing"
          class="question-sharing"
          phx-click="inspect_context"
          phx-target={@myself}
        >Shares case + source</button>
        <span id="question-provider" class="question-provider">Uses Codex</span>
        <button class="question-mobile-open" phx-click="new" phx-target={@myself}>Ask an assistant</button>
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
          Question history is unavailable, so the app cannot send a question.
        </p>
        <p :if={@error} role="alert">{@error}</p>
        <p class="question-local-help">
          For local reference, <a href="/glossary">look up a term</a>
          or <a href="/proofs">read a claim</a>. Opening a guide sends nothing.
        </p>
        <details :if={@error && @error_detail} id="question-error-details">
          <summary>Technical details</summary><code>{@error_detail}</code>
        </details>
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
            <span class="scope-note">Generated explanation · check the cited source and verification records</span>
          </div>
          <p :if={@active["error"]} role="status">{@active["status"]}: {@active["error"]}</p>
          <p :if={@active["persistence_error"]} role="alert">
            This answer couldn't be saved. Copy it before closing.
          </p>
          <div class="question-actions">
            <button :if={answer?(@active)} phx-click="followup" phx-target={@myself}>Ask a follow-up</button>
            <button phx-click="new" phx-target={@myself}>Ask using current case</button>
            <a href={export(@active)} download={"question-#{@active["id"]}.json"}>Export question and answer</a>
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
          phx-submit="ask"
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
            Uses the earlier case, question and answer. Inspect context before sending this follow-up.
          </p>
          <input type="hidden" name="question[context_id]" value={@send_context_id} />
          <p class="scope-note">Sends this question, case and included source to Codex.</p>
          <div class="question-actions">
            <button
              id="question-send"
              type="submit"
              disabled={!@ready || @health != :ok}
              phx-disable-with="Sending…"
            >Send question</button>
            <button type="button" phx-click="inspect_context" phx-target={@myself}>Inspect context</button>
          </div>
        </.form>
        <details :if={(@packet || @active) && !@history_open} id="question-context">
          <summary>Context · {(@packet || @active["packet"])["model"]} · medium</summary>
          <p>
            Sending shares your question, the selected case and these sources with Codex. The app saves the question and response locally.
          </p>
          <p><code>{(@packet || @active["packet"])["digest"]}</code></p>
          <p :for={source <- (@packet || @active["packet"])["context"]["sources"]}>
            <strong>{source["path"]}</strong> <code>{source["sha256"]}</code>
            <span :if={source["truncated"]}>Excerpt: lines {source["start_line"]}–{source["end_line"]}; later proof lines are omitted.</span>
          </p>
          <details>
            <summary>Exact application prompt</summary><pre>{Jason.encode!((@packet || @active["packet"])["messages"], pretty: true)}</pre>
          </details>
          <p>
            Only the listed sources are included. Private review notes stay out of the request.
          </p>
        </details>
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
          No questions match this search. Try another phrase or choose All questions.
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
