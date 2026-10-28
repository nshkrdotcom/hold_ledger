defmodule HoldLedgerReviewWeb.ScrubberComponents do
  @moduledoc false
  use HoldLedgerReviewWeb, :html
  import HoldLedgerReviewWeb.DissectorComponents, only: [term: 1]
  alias HoldLedgerReview.Trace
  alias HoldLedgerReviewWeb.ReviewCopy

  attr :doc, :map, required: true
  attr :cursor, :string, required: true
  attr :preview, :any, default: nil
  attr :saved, :map, required: true

  def timeline(assigns) do
    parent =
      if assigns.preview,
        do: Enum.find_index(assigns.doc["steps"], &(&1["id"] == assigns.preview["parent"]))

    assigns =
      assign(assigns,
        parent_label: if(is_integer(parent), do: "step #{parent + 1}", else: "Start")
      )

    ~H"""
    <section id="trace-rail" class="trace-rail">
      <nav id="timeline" aria-label="Trace steps">
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
        >
          {index}. {event_label(step["event"])}{if step["origin"] != "computed", do: " · hypothetical"}
        </button>
        <span :if={@preview} id="transient-branch" aria-current="step">↳ {event_label(
          @preview["event"]
        )} · trying from {@parent_label}</span>
      </nav>
      <p id="trace-revision" data-revision={@saved["revision"]} class="scope-note">
        Choose a step to continue from it.
      </p>
    </section>
    """
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
          <button class="primary" id="apply-event" disabled={!Trace.current?(@doc)}>Run event</button>
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
