defmodule HoldLedgerReviewWeb.ScrubberComponents do
  @moduledoc false
  use HoldLedgerReviewWeb, :html
  import HoldLedgerReviewWeb.DissectorComponents, only: [term: 1]
  alias HoldLedgerReview.Trace

  attr :doc, :map, required: true
  attr :cursor, :string, required: true
  attr :event_form, :any, required: true
  attr :path, :list, required: true

  def scrubber(assigns) do
    {:ok, state} = Trace.state_at(assigns.doc, assigns.cursor)

    assigns =
      assign(assigns,
        state: state,
        ledger: if(assigns.doc["mode"] == "ledger", do: state, else: state["ledger"])
      )

    ~H"""
    <section class="machine" id="state-machine">
      <header class="section-heading">
        <h2>Recorded state & timeline</h2><div class="action-row">
          <button :if={@doc["mode"] == "ledger"} phx-click="edit_initial" id="edit-start">Adjust starting state</button><button
            phx-click="coupled"
            id="coupled-model"
          >Coupled processor model</button>
        </div>
      </header>
      <nav id="timeline" aria-label="Trace steps">
        <button
          phx-click="select_step"
          phx-value-id="start"
          aria-current={if @cursor == "start", do: "step", else: "false"}
        >Start</button><button
          :for={{step, index} <- Enum.with_index(@doc["steps"], 1)}
          phx-click="select_step"
          phx-value-id={step["id"]}
          aria-current={if @cursor == step["id"], do: "step", else: "false"}
        >{index}. {event_label(step["event"])}{if step["origin"] != "computed", do: " · hypothetical"}</button>
      </nav>
      <div class="scrub-row">
        <button phx-click="previous" id="previous-step" disabled={@cursor == "start"}>Previous</button><form
          id="scrubber"
          phx-change="scrub"
        >
          <label for="position">Trace position</label><input
            id="position"
            type="range"
            name="position"
            min="0"
            max={length(@path)}
            value={length(Trace.path(@doc, @cursor))}
          />
        </form><button phx-click="next" id="next-step">Next</button>
      </div>
      <div class="capacity-grid">
        <div>
          <span>Reserved / limit</span><strong id="amount-counter">{@ledger["used_amount"]}¢ / {@ledger[
            "amount_limit"
          ]}¢</strong><meter
            min="0"
            max={max(@ledger["amount_limit"], 1)}
            value={@ledger["used_amount"]}
          />
        </div><div>
          <span>Slots used / limit</span><strong id="slot-counter">{@ledger["used_holds"]} / {@ledger[
            "hold_limit"
          ]}</strong><meter min="0" max={max(@ledger["hold_limit"], 1)} value={@ledger["used_holds"]} />
        </div>
      </div>
      <table id="entries">
        <thead>
          <tr>
            <th>Identity</th><th>Amount</th><th>Local status</th>
          </tr>
        </thead><tbody>
          <tr :for={entry <- @ledger["entries"]}>
            <td>{entry["key"]}</td><td>{entry["amount"]}¢</td><td>{entry["status"]}</td>
          </tr><tr :if={@ledger["entries"] == []}>
            <td colspan="3">No entries</td>
          </tr>
        </tbody>
      </table>
      <div :if={@doc["mode"] == "exposure"} id="remote-state">
        <h3>Modeled remote records</h3><table>
          <thead>
            <tr>
              <th>Identity</th><th>Amount</th><th>Remote status</th>
            </tr>
          </thead><tbody>
            <tr :for={entry <- @state["remote"]}>
              <td>{entry["key"]}</td><td>{entry["amount"]}¢</td><td>{entry["status"]}</td>
            </tr>
          </tbody>
        </table><p>Pending voids: {length(@state["obligations"])}</p>
      </div>
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
          label="Append event after selected step"
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
        <button class="primary" id="apply-event" disabled={!Trace.current?(@doc)}>Append event</button>
      </.form>
      <p class="scope-note" id="trace-revision">
        Revision {@doc["revision"]}. Applying an event at an earlier step creates a branch.
      </p>
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
