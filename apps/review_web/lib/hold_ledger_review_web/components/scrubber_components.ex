defmodule HoldLedgerReviewWeb.ScrubberComponents do
  @moduledoc false
  use HoldLedgerReviewWeb, :html
  import HoldLedgerReviewWeb.DissectorComponents, only: [term: 1]
  alias HoldLedgerReview.Trace
  alias HoldLedgerReviewWeb.{ReviewCopy, TraceFork}

  attr :doc, :map, required: true
  attr :cursor, :string, required: true
  attr :preview, :any, default: nil
  attr :saved, :map, required: true
  attr :fork, :any, default: nil

  def timeline(assigns) do
    fork = assigns.fork || TraceFork.project(assigns.doc, assigns.cursor)

    shown_ids =
      if fork do
        (fork.shared ++ fork.code ++ fork.alternative)
        |> Enum.map(& &1["id"])
        |> MapSet.new()
      else
        MapSet.new()
      end

    other_steps =
      if fork,
        do: Enum.reject(assigns.doc["steps"], &MapSet.member?(shown_ids, &1["id"])),
        else: []

    assigns =
      assign(assigns,
        fork: fork,
        other_steps: other_steps,
        parent_label: preview_parent_label(assigns.doc, assigns.preview)
      )

    ~H"""
    <section id="trace-rail" class="trace-rail" aria-label="Case timeline">
      <header class="timeline-heading">
        <h2>Case timeline</h2>
        <span id="trace-revision" data-revision={@saved["revision"]}>
          {if @preview || @doc["revision"] != @saved["revision"],
            do: "Unsaved experiment",
            else: "Saved history"}
        </span>
      </header>
      <nav :if={!@fork} id="timeline" class="linear-timeline" aria-label="Trace steps">
        <button
          phx-click="select_step"
          phx-value-id="start"
          aria-current={if @cursor == "start" && !@preview, do: "step", else: "false"}
        >Start</button>
        <button
          :for={{step, index} <- Enum.with_index(@doc["steps"], 1)}
          phx-click="select_step"
          phx-value-id={step["id"]}
          aria-current={if @cursor == step["id"] && !@preview, do: "step", else: "false"}
        >{index}. {event_label(step["event"])}{if step["origin"] != "computed", do: " · alternative"}</button>
        <span :if={@preview} id="transient-branch" aria-current="step">
          ↳ {event_label(@preview["event"])} · trying from {@parent_label}
        </span>
      </nav>
      <div :if={@fork} id="timeline" class="fork-timeline" role="group" aria-label="Code and alternative timeline">
        <div class="shared-history" aria-label="Shared history before the fork">
          <span class="timeline-caption">Shared history</span>
          <button phx-click="select_step" phx-value-id="start"
            aria-current={if @cursor == "start" && !@preview, do: "step", else: "false"}>Start</button>
          <.timeline_step :for={{step, index} <- Enum.with_index(@fork.shared, 1)}
            step={step} index={index} cursor={@cursor} preview={@preview} />
          <.timeline_preview :if={@preview && (@preview["parent"] == "start" ||
            @preview["parent"] in Enum.map(@fork.shared, & &1["id"]))} step={@preview} />
        </div>
        <p class="fork-label" id="fork-origin">
          Two recorded outcomes from the same event. Select any step to inspect its state and rule checks.
        </p>
        <div class="timeline-branches">
          <section class="timeline-branch code-branch" id="code-branch" aria-label="Code path">
            <h3><span class="branch-marker" aria-hidden="true">A</span> Code path</h3>
            <div class="branch-steps">
              <.timeline_step :for={{step, index} <- Enum.with_index(@fork.code, length(@fork.shared) + 1)}
                step={step} index={index} cursor={@cursor} preview={@preview} />
              <.timeline_preview :if={@preview && @preview["parent"] in Enum.map(@fork.code, & &1["id"])}
                step={@preview} />
            </div>
          </section>
          <section class="timeline-branch alternative-branch" id="alternative-branch" aria-label="Alternative path">
            <h3><span class="branch-marker" aria-hidden="true">B</span> Alternative path</h3>
            <div class="branch-steps">
              <.timeline_step :for={{step, index} <- Enum.with_index(@fork.alternative, length(@fork.shared) + 1)}
                step={step} index={index} cursor={@cursor} preview={@preview} />
              <.timeline_preview :if={@preview && @preview["parent"] in Enum.map(@fork.alternative, & &1["id"])}
                step={@preview} />
            </div>
          </section>
        </div>
        <details :if={@other_steps != []} id="other-trace-steps" class="other-trace-steps"
          open={Enum.any?(@other_steps, &(&1["id"] == @cursor))}>
          <summary>Other recorded steps · {length(@other_steps)}</summary>
          <div class="other-step-list">
            <.timeline_step :for={{step, index} <- Enum.with_index(@other_steps, 1)}
              step={step} index={index} cursor={@cursor} preview={@preview} />
          </div>
        </details>
      </div>
      <p class="timeline-hint">Select a step to inspect it. New events run from the selected step; the other path stays visible.</p>
    </section>
    """
  end

  attr :step, :map, required: true
  attr :index, :integer, required: true
  attr :cursor, :string, required: true
  attr :preview, :any, default: nil

  defp timeline_step(assigns) do
    output = assigns.step["output"]
    after_state = if output, do: output["after"]

    assigns = assign(assigns, output: output, after_state: after_state)

    ~H"""
    <button class="timeline-step" phx-click="select_step" phx-value-id={@step["id"]}
      aria-current={if @cursor == @step["id"] && !@preview, do: "step", else: "false"}
      data-origin={@step["origin"]}>
      <span class="timeline-step-event">{@index}. {event_label(@step["event"])}</span>
      <strong :if={@output} class="timeline-step-result">{ReviewCopy.result(@output["result"])}</strong>
      <span :if={!@output} class="timeline-step-result">Coupled state updated</span>
      <span :if={@after_state} class="timeline-step-amount">
        {@after_state["used_amount"]}¢ reserved · {max(@after_state["amount_limit"] - @after_state["used_amount"], 0)}¢ available
      </span>
      <meter :if={@after_state} min="0" max={max(@after_state["amount_limit"], 1)}
        value={@after_state["used_amount"]} aria-label="Reserved money after step"></meter>
    </button>
    """
  end

  attr :step, :map, required: true

  defp timeline_preview(assigns) do
    ~H"""
    <span class="timeline-preview" id="transient-branch">
      Trying {event_label(@step["event"])} · not saved
      <strong :if={@step["output"]}>{ReviewCopy.result(@step["output"]["result"])}</strong>
    </span>
    """
  end

  defp preview_parent_label(_doc, nil), do: "Start"

  defp preview_parent_label(doc, preview) do
    case Enum.find_index(doc["steps"], &(&1["id"] == preview["parent"])) do
      nil -> "Start"
      index -> "step #{index + 1}"
    end
  end

  attr :doc, :map, required: true
  attr :cursor, :string, required: true
  attr :step, :any, default: nil

  def active_state(assigns) do
    {:ok, recorded} = Trace.state_at(assigns.doc, assigns.cursor)
    before = if assigns.step, do: assigns.step["before"], else: recorded
    ledger = if assigns.doc["mode"] == "ledger", do: before, else: before["ledger"]
    assigns = assign(assigns, before: before, ledger: ledger, recorded: recorded)

    ~H"""
    <section id="active-state" class="before-state">
      <header>
        <h2>Before this event</h2><button
          :if={@doc["mode"] == "ledger"}
          id="edit-start"
          phx-click="edit_initial"
        >Edit starting state</button>
      </header>
      <p class="available-money">
        <strong>{@ledger["amount_limit"] - @ledger["used_amount"]}¢</strong> available
      </p><meter
        class="money-bar"
        min="0"
        max={max(@ledger["amount_limit"], 1)}
        value={@ledger["used_amount"]}
        aria-label="Money reserved before this event"
      ></meter>
      <div class="capacity-grid">
        <strong id="amount-counter">{@ledger["used_amount"]}¢ / {@ledger["amount_limit"]}¢</strong><span>reserved / limit</span><strong id="slot-counter">{@ledger[
          "used_holds"
        ]} / {@ledger["hold_limit"]}</strong><span>slots</span>
      </div>
      <table :if={@ledger["entries"] != []} id="entries">
        <thead>
          <tr>
            <th>Identity</th><th>Amount</th><th>Status</th>
          </tr>
        </thead><tbody>
          <tr :for={entry <- @ledger["entries"]}>
            <td>{entry["key"]}</td><td>{entry["amount"]}¢</td><td>
              {ReviewCopy.state(entry["status"])}
            </td>
          </tr>
          <tr :if={@ledger["entries"] == []}>
            <td colspan="3">No entries</td>
          </tr>
        </tbody>
      </table>
      <p :if={@ledger["entries"] == []} id="entries">No entries</p>
      <div :if={@doc["mode"] == "exposure"} id="remote-state">
        <h3>After selected coupled event</h3>
        <p id="coupled-amount-counter">
          {@recorded["ledger"]["used_amount"]}¢ / {@recorded["ledger"]["amount_limit"]}¢ reserved · {length(
            @recorded["obligations"]
          )} pending voids
        </p>
        <table id="coupled-local-after">
          <caption>Local result</caption><thead>
            <tr>
              <th>Identity</th><th>Amount</th><th>Status</th>
            </tr>
          </thead><tbody>
            <tr :for={entry <- @recorded["ledger"]["entries"]}>
              <td>{entry["key"]}</td><td>{entry["amount"]}¢</td><td>
                {ReviewCopy.state(entry["status"])}
              </td>
            </tr>
          </tbody>
        </table>
        <table id="coupled-remote-after">
          <caption>Modeled processor</caption><thead>
            <tr>
              <th>Identity</th><th>Amount</th><th>Status</th>
            </tr>
          </thead><tbody>
            <tr :for={entry <- @recorded["remote"]}>
              <td>{entry["key"]}</td><td>{entry["amount"]}¢</td><td>
                {ReviewCopy.state(entry["status"])}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>
    """
  end

  attr :doc, :map, required: true
  attr :event_form, :any, required: true
  attr :step, :any, default: nil
  attr :preview, :any, default: nil

  attr :builder_open, :boolean, required: true
  attr :fork, :any, default: nil

  def event_controls(assigns) do
    ~H"""
    <section id="next-actions">
      <div id="event-builder">
        <.form
          for={@event_form}
          id="next-event"
          phx-change="event_change"
          phx-submit="apply_event"
          class="form-row"
        >
          <.input
            field={@event_form[:type]}
            type="select"
            label="Next event"
            options={event_options(@doc["mode"])}
          />
          <.input
            field={@event_form[:key]}
            type="number"
            disabled={@event_form[:type].value == "restart"}
            label="Identity"
            min="0"
            max="1000000"
          />
          <.input
            field={@event_form[:amount]}
            type="number"
            disabled={@event_form[:type].value != "request"}
            label="Amount (¢)"
            min="1"
            max="1000000"
          />
          <.input
            field={@event_form[:outcome]}
            type="select"
            disabled={@event_form[:type].value not in ~w(authorize processor_result)}
            label="Outcome"
            options={~w(approved declined)}
          />
          <button class="primary" id="apply-event" disabled={!Trace.current?(@doc)}>Run on selected path</button>
          <button :if={@fork && @doc["mode"] == "ledger"} type="button" id="apply-event-pair"
            phx-click="apply_event_pair" disabled={!Trace.current?(@doc)}>
            Run on both paths
          </button>
        </.form>
      </div>
      <button id="coupled-model" phx-click="coupled" class="text-button">Open coupled processor case</button>
    </section>
    """
  end

  def event_label(%{"kind" => "local", "event" => event}), do: "local " <> term(event)
  def event_label(%{"kind" => kind, "key" => key}), do: "remote #{kind}(#{key})"
  def event_label(event), do: term(event)

  defp event_options("ledger"),
    do:
      ~w(request dispatch timeout restart retry processor_result transport_ack void void_confirmed)

  defp event_options("exposure"),
    do: [
      {"Local request", "request"},
      {"Local dispatch", "dispatch"},
      {"Local timeout", "timeout"},
      {"Local retry", "retry"},
      {"Local restart", "restart"},
      {"Local void", "void"},
      {"Remote authorize", "authorize"},
      {"Observe approval/decline", "observe"},
      {"Remote void", "remote_void"},
      {"Observe terminal confirmation", "confirm"}
    ]
end
