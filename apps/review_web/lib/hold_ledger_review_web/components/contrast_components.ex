defmodule HoldLedgerReviewWeb.ContrastComponents do
  @moduledoc false
  use HoldLedgerReviewWeb, :html
  alias HoldLedgerReviewWeb.{OutputDifferences, ReviewCopy}

  attr :case, :map, default: nil
  attr :step, :map, default: nil
  attr :invalid, :boolean, default: false

  def case_summary(assigns) do
    event = (assigns.case && assigns.case["event"]) || (assigns.step && assigns.step["event"])
    output = (assigns.case && assigns.case["actual"]) || (assigns.step && assigns.step["output"])

    assigns =
      assign(assigns,
        event_label: case_event_label(event),
        result_label: case_result_label(output, event),
        check_label:
          if(assigns.case && !assigns.invalid,
            do: ReviewCopy.candidate_acceptance(assigns.case),
            else: "Check unavailable"
          )
      )

    ~H"""
    <section
      id="case-current-summary"
      class="case-current-summary"
      role="status"
      aria-live="polite"
      aria-atomic="true"
    >
      <h2>What this case shows</h2>
      <p><strong>{@event_label}</strong><span>{@result_label}</span></p>
      <p class="case-summary-check">Claim check: <strong>{@check_label}</strong></p>
      <small>The claim check covers this input and proposed output.</small>
    </section>
    """
  end

  defp case_event_label(%{"type" => "request", "key" => key, "amount" => amount}),
    do: "Request #{key} asks for #{amount}¢."

  defp case_event_label(%{"type" => type, "key" => key}) do
    label =
      Map.get(
        %{
          "dispatch" => "Send authorization",
          "timeout" => "Missing reply",
          "retry" => "Retry authorization",
          "void" => "Request cancellation",
          "void_confirmed" => "Confirm cancellation",
          "processor_result" => "Record processor result",
          "transport_ack" => "Record transport acknowledgment"
        },
        type,
        String.replace(type, "_", " ")
      )

    "#{label} for request #{key}."
  end

  defp case_event_label(nil), do: "Starting account."

  defp case_event_label(event),
    do: HoldLedgerReviewWeb.ScrubberComponents.event_label(event)

  defp case_result_label(%{"result" => result}, _event) when is_binary(result),
    do: "Code returned: #{ReviewCopy.result(result)}."

  defp case_result_label(_, nil), do: "Choose an event to inspect its result."

  defp case_result_label(nil, _event),
    do: "Read the local ledger and modeled processor records for this event."

  defp case_result_label(_, _event), do: "No computed output is available for this event."

  attr :case, :map, default: nil
  attr :step, :map, default: nil
  attr :slug, :string, required: true
  attr :editor, :string, default: nil
  attr :candidate_form, :any, default: nil
  attr :initial_form, :any, default: nil
  attr :invalid, :boolean, default: false

  def contrast(assigns) do
    differences =
      if assigns.case,
        do: OutputDifferences.between(assigns.case["actual"], assigns.case["candidate"]),
        else: nil

    assigns = assign(assigns, differences: differences)

    ~H"""
    <section class="instrument" id="contrast">
      <header>
        <span class="section-number">Outputs</span><h2>Compare what happened</h2>
      </header>
      <div :if={@step && @step["output"]}>
        <p :if={@step["origin"] != "computed"} id="hypothetical-lineage" class="signal">
          Continuing from the proposed output
        </p>
        <div class="output-pair">
          <.output
            title="Code returned"
            output={if @case, do: @case["actual"], else: @step["output"]}
            id="ledger-output"
            differences={nil}
          />
          <.output
            :if={@case}
            title="Proposed output · not run"
            output={@case["candidate"]}
            id="hypothetical-output"
            differences={@differences}
            editable={true}
          />
        </div>
        <p :if={@differences && @differences.same?} id="same-output" class="scope-note">
          Same as code result.
        </p>
        <details
          :if={@differences && !@differences.same?}
          id="output-differences"
          class="output-differences"
        >
          <summary>
            Full differences · {@differences.field_count} changed fields, {@differences.other_count} other rows
          </summary>
          <h3>Code returned → proposed output</h3>
          <ol>
            <li
              :for={{difference, index} <- Enum.with_index(@differences.rows)}
              id={"difference-#{index}"}
            >
              <strong>{difference.label}</strong>
              <span>{difference.before}
              <span aria-label="changed to">→</span> {difference.after}{difference.delta}</span>
            </li>
          </ol>
        </details>
        <p :if={@invalid} id="invalid-candidate" role="alert">
          Enter a whole number or valid output JSON to check this proposed output.
        </p>
      </div>
      <p :if={@step && !@step["output"]}>Coupled model step. Remote records are shown below.</p>
    </section>
    """
  end

  attr :case, :map, default: nil
  attr :step, :map, default: nil
  attr :preview, :any, default: nil

  def draft_tools(assigns) do
    ~H"""
    <section id="draft-tools">
      <h3>Edit the proposed output</h3>
      <p class="scope-note">
        Describe a different result for this input, then check whether the claim would accept it.
        Continue from this output to run later events from the state you proposed.
      </p>
      <div class="mutation-chips" id="candidate-mutations">
        <button phx-click="mutate_candidate" phx-value-kind="drop_effects">Remove requested effects</button>
        <button phx-click="mutate_candidate" phx-value-kind="zero_counters">Zero both totals</button>
        <button phx-click="mutate_candidate" phx-value-kind="change_identity">Change first identity</button>
        <button phx-click="candidate_recalculate" id="recalculate-inline">Recalculate totals</button>
      </div>
      <div class="action-row">
        <button phx-click="restore_candidate">Reset to code result</button><button
          phx-click="show_advanced"
          id="advanced-editor"
        >Full state / JSON editor</button>
      </div>
      <div class="action-row">
        <button
          phx-click="branch_candidate"
          id="branch-candidate"
          disabled={!@case || !@case["candidate_valid"]}
        >Continue from this output</button>
      </div>
    </section>
    """
  end

  attr :case, :map, default: nil
  attr :editor, :string, default: nil
  attr :candidate_form, :any, default: nil
  attr :initial_form, :any, default: nil
  attr :json_form, :any, default: nil

  def editors(assigns) do
    json = if assigns.case, do: Jason.encode!(assigns.case["candidate"], pretty: true), else: ""
    assigns = assign(assigns, :json_form, assigns.json_form || to_form(%{"json" => json}))

    ~H"""
    <section id="structured-editors">
      <div :if={@editor == "candidate" && @candidate_form} id="candidate-editor">
        <.form
          for={@candidate_form}
          id="candidate-form"
          phx-change="candidate_change"
        >
          <.state_fields form={@candidate_form} />
          <.input
            field={@candidate_form[:result]}
            type="select"
            label="Result"
            options={HoldLedgerReview.TermCodec.results()}
          />
          <div :for={{index, effect} <- @candidate_form.params["effects"] || %{}} class="form-row">
            <.input
              field={nested_form(effect, index, "effects", "output")[:type]}
              type="select"
              label="Effect"
              options={~w(authorize void)}
            />
            <.input
              field={nested_form(effect, index, "effects", "output")[:key]}
              type="number"
              label="Identity"
            />
            <.input
              field={nested_form(effect, index, "effects", "output")[:amount]}
              type="number"
              label="Amount (¢)"
            />
          </div>
          <p class="editor-live-status" role="status">Fields check as you edit.</p>
        </.form>
        <div class="action-row">
          <button phx-click="candidate_recalculate" id="recalculate">Recalculate totals</button><button phx-click="candidate_add_entry">Add entry</button><button phx-click="candidate_add_effect">Add void effect</button><button phx-click="candidate_clear_effects">Clear effects</button>
        </div>
        <section id="json-editor">
          <h3>Output JSON</h3>
          <.form
            for={@json_form}
            id="candidate-json-form"
            phx-submit="candidate_json"
          >
            <.input
              field={@json_form[:json]}
              type="textarea"
              label="Typed output"
              id="candidate-json"
            />
            <button>Check JSON</button>
          </.form>
        </section>
      </div>
      <div :if={@editor == "initial" && @initial_form} id="starting-editor">
        <.form
          for={@initial_form}
          id="starting-form"
          phx-change="initial_change"
          phx-submit="save_initial"
        >
          <.state_fields form={@initial_form} /><button class="primary" id="save-starting">Run from this state</button>
        </.form>
        <div class="action-row">
          <button phx-click="initial_add_entry">Add entry</button><button phx-click="initial_recalculate">Recalculate totals</button>
        </div>
      </div>
    </section>
    """
  end

  attr :case, :map, default: nil
  attr :slug, :string, required: true

  def verdict(assigns) do
    signal = if assigns.case, do: verdict_signal(assigns.case)
    assigns = assign(assigns, :signal, signal)

    ~H"""
    <section id="verdict" class="verdict-panel" aria-label="Checks for this case">
      <div class="verdict-heading">
        <h2>Checks for this case</h2>
        <span :if={@case} class="verdict-event" id="verdict-event">
          {@slug} · {HoldLedgerReviewWeb.DissectorComponents.term(@case["event"])}
        </span>
      </div>
      <div
        :if={@signal}
        id="verdict-signal"
        class={["verdict-signal", "verdict-" <> @signal.state]}
        data-state={@signal.state}
      >
        <strong>{@signal.title}</strong>
        <span>{@signal.detail}</span>
      </div>
      <div :if={@case} id="active-predicate-result">
        <table id="contrast-matrix">
          <caption class="sr-only">
            Coverage, output acceptance and accounting for the selected case
          </caption>
          <thead>
            <tr>
              <th scope="col">Check</th><th scope="col">Code returned</th><th scope="col">
                Proposed output · not run
              </th>
            </tr>
          </thead>
          <tbody>
            <tr id="applicability-row">
              <th scope="row">
                <button type="button" class="edu-term-button" data-edu-term="coverage">
                  Does the claim cover this input?
                </button>
              </th>
              <td colspan="2">{ReviewCopy.applicability(@case)}</td>
            </tr>
            <tr
              id="selected-law-row"
              class={ReviewCopy.output_check_unavailable?(@case) && "check-unavailable"}
            >
              <th scope="row">
                <button type="button" class="edu-term-button" data-edu-term="expects">
                  Does the output satisfy the claim?
                </button>
              </th>
              <td>{ReviewCopy.code_acceptance(@case)}</td>
              <td class={["candidate-verdict", "candidate-" <> @signal.state]}>
                <strong>{ReviewCopy.candidate_acceptance(@case)}</strong>
              </td>
            </tr>
            <tr id="validity-row">
              <th scope="row">
                <button type="button" class="edu-term-button" data-edu-term="invariant">
                  Do the totals and holds agree?
                </button>
              </th>
              <td>{ReviewCopy.accounting(@case["actual_valid"])}</td>
              <td>{ReviewCopy.accounting(@case["candidate_valid"])}</td>
            </tr>
            <tr :if={@case["comparison_law"] != @slug && @case["comparison_status"] != "not_probed"}>
              <th scope="row">
                <button
                  class="text-button"
                  phx-click="inspect_law"
                  phx-value-slug={@case["comparison_law"]}
                >
                  {ReviewCopy.title(%{"slug" => @case["comparison_law"]})}
                </button>
              </th>
              <td>
                {if @case["comparison_actual"] === true,
                  do: "Accepts code result",
                  else: "Unavailable"}
              </td>
              <td>
                {ReviewCopy.candidate_acceptance(%{"law_status" => @case["comparison_status"]})}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
      <p :if={@case && ReviewCopy.candidate_acceptance(@case) == "Unavailable"} class="scope-note">
        {ReviewCopy.probe_reason(@case["law_reason"], @slug)}
      </p>
      <p :if={!@case} id="checks-unavailable" role="status">
        Checks unavailable for the current input or alternative. Correct the editing error, or select an executable case.
      </p>
    </section>
    """
  end

  attr :form, :any, required: true

  def state_fields(assigns) do
    ~H"""
    <div class="form-row">
      <.input
        :for={field <- ~w(amount_limit hold_limit used_amount used_holds)}
        field={@form[field]}
        type="number"
        min="0"
        max="1000000"
        label={
          %{
            "amount_limit" => "Amount limit (¢)",
            "hold_limit" => "Hold slot limit",
            "used_amount" => "Reserved amount (¢)",
            "used_holds" => "Hold slots used"
          }[field]
        }
      />
    </div>
    <div :for={{index, entry} <- @form.params["entries"] || %{}} class="form-row">
      <.input
        field={nested_form(entry, index, "entries", @form.name)[:key]}
        type="number"
        label="Identity"
      />
      <.input
        field={nested_form(entry, index, "entries", @form.name)[:amount]}
        type="number"
        label="Amount (¢)"
      />
      <.input
        field={nested_form(entry, index, "entries", @form.name)[:status]}
        type="select"
        label="Status"
        options={HoldLedgerReview.TermCodec.statuses()}
      />
    </div>
    """
  end

  attr :title, :string, required: true
  attr :output, :map, required: true
  attr :id, :string, required: true
  attr :differences, :any, default: nil
  attr :editable, :boolean, default: false

  def output(assigns) do
    ~H"""
    <article class="output" id={@id}>
      <div class="output-heading">
        <h3>{@title}</h3>
        <button
          type="button"
          class="output-explanation edu-term-button"
          data-edu-term={if(@editable, do: "hypothetical", else: "pointwise")}
          aria-label={if(@editable, do: "About proposed outputs", else: "About computed outputs")}
        >?</button>
        <button :if={@editable} id="edit-candidate" phx-click="edit_candidate" class="text-button">
          More edits
        </button>
      </div>
      <div
        :if={@editable}
        class="quick-alternative"
        id="quick-alternative"
        phx-hook="InlineAlternative"
      >
        <.form
          for={to_form(%{"result" => @output["result"]})}
          id="alternative-result"
          phx-change="alternative_result"
        >
          <.input
            id="alternative-result-select"
            name="result"
            value={@output["result"]}
            type="select"
            label="Result"
            options={HoldLedgerReview.TermCodec.results()}
          />
        </.form>
        <.form
          for={to_form(%{"amount" => @output["after"]["used_amount"]})}
          id="alternative-counter"
          phx-change="alternative_total"
        >
          <.input
            id="alternative-reserved-input"
            name="amount"
            value={@output["after"]["used_amount"]}
            type="number"
            min="0"
            max="1000000"
            phx-debounce="300"
            label="Reserved (¢)"
          />
        </.form>
      </div>
      <div class="output-headline">
        <strong>{@output["after"]["used_amount"]}¢ reserved</strong>
        <small>{ReviewCopy.dollar_gloss(@output["after"]["used_amount"])}</small>
        <.field_delta change={OutputDifferences.at(@differences, ["after", "used_amount"])} />
      </div>
      <meter
        class="money-bar"
        min="0"
        max={max(@output["after"]["amount_limit"], 1)}
        value={@output["after"]["used_amount"]}
        aria-label={@title <> ": reserved money"}
      ></meter>
      <p class="output-headline">
        {slot_count(@output["after"]["used_holds"])} · {ReviewCopy.result(@output["result"])}
        <.field_delta change={OutputDifferences.at(@differences, ["after", "used_holds"])} />
        <.field_delta change={OutputDifferences.at(@differences, ["result"])} />
      </p>
      <details
        class="output-fields-detail"
        open={
          OutputDifferences.at(@differences, ["after", "amount_limit"]) != nil ||
            OutputDifferences.at(@differences, ["after", "hold_limit"]) != nil
        }
      >
        <summary>Output fields</summary><dl class="output-fields">
          <div>
            <dt>Amount limit</dt><dd>
              {@output["after"]["amount_limit"]}¢
              <.field_delta change={OutputDifferences.at(@differences, ["after", "amount_limit"])} />
            </dd>
          </div>
          <div>
            <dt>Hold limit</dt><dd>
              {slot_count(@output["after"]["hold_limit"])}
              <.field_delta change={OutputDifferences.at(@differences, ["after", "hold_limit"])} />
            </dd>
          </div>
          <div>
            <dt>Used hold slots</dt><dd>
              {@output["after"]["used_holds"]}
              <.field_delta change={OutputDifferences.at(@differences, ["after", "used_holds"])} />
            </dd>
          </div>
          <div>
            <dt>Result</dt><dd>
              {@output["result"]}
              <.field_delta change={OutputDifferences.at(@differences, ["result"])} />
            </dd>
          </div>
        </dl>
      </details>
      <ul class="output-entries">
        <li :for={{entry, index} <- Enum.with_index(@output["after"]["entries"])}>
          <span>{entry["key"]} · {entry["amount"]}¢</span>
          <.field_delta change={
            OutputDifferences.at(@differences, ["after", "entries", index, "amount"])
          } />
          <button
            :if={@id == "hypothetical-output"}
            class="status-pill"
            phx-click="cycle_status"
            phx-value-index={index}
            title={entry["status"]}
            data-edu-hint={ReviewCopy.state_hint(entry["status"])}
          >{ReviewCopy.state(entry["status"])}</button>
          <span
            :if={@id != "hypothetical-output"}
            class="status-pill"
            title={entry["status"]}
            tabindex="0"
            data-edu-hint={ReviewCopy.state_hint(entry["status"])}
          >
            {ReviewCopy.state(entry["status"])}
          </span>
          <.field_delta change={
            OutputDifferences.at(@differences, ["after", "entries", index, "status"])
          } />
        </li>
      </ul>
      <ul
        :if={@differences && @differences.ghosts != []}
        class="comparison-ghosts"
        aria-label="Entries absent from the proposed output"
      >
        <li :for={ghost <- @differences.ghosts} class="comparison-ghost">
          <span>{ghost.entry["key"]} · {ghost.entry["amount"]}¢ · {ReviewCopy.state(
            ghost.entry["status"]
          )}</span>
          <small>Absent from proposed output · original position {ghost.before_index + 1}</small>
        </li>
      </ul>
      <div class="effect-list">
        <strong>
          <button type="button" class="edu-term-button" data-edu-term="effect-intent">
            Requested effects
          </button>
        </strong>
        <p :if={@output["effects"] == []}>No outside work requested</p>
        <ul :if={@output["effects"] != []}>
          <li :for={{effect, index} <- Enum.with_index(@output["effects"])}>
            {ReviewCopy.action(effect)}
            <.field_delta change={OutputDifferences.at(@differences, ["effects", index, "amount"])} />
          </li>
        </ul>
        <small :if={
          @differences &&
            Enum.any?(
              @differences.rows,
              &(&1.kind in [:added, :removed, :order_change] && hd(&1.path) == "effects")
            )
        }>
          Requested effects or their order differ; see Full differences.
        </small>
      </div>
    </article>
    """
  end

  attr :change, :any, default: nil

  def field_delta(assigns) do
    ~H"""
    <small :if={@change} class="field-delta" data-change-kind="field_change">
      {OutputDifferences.annotation(@change)}
    </small>
    """
  end

  defp verdict_signal(case_data) do
    same? =
      OutputDifferences.between(case_data["actual"], case_data["candidate"]).same?

    case case_data["law_status"] do
      "allows_here" when same? ->
        %{
          state: "same",
          title: "Claim accepts the code result",
          detail: "The proposed output matches what the code returned."
        }

      "allows_here" ->
        %{
          state: "permits",
          title: "Claim would accept this output. Intended?",
          detail:
            "Compare the output with the policy, then inspect the conditions that accepted it."
        }

      "catches" ->
        %{
          state: "rejects",
          title: "Claim rejects this output",
          detail: "The proposed output fails the claim on this input."
        }

      "doesnt_apply" ->
        %{
          state: "unavailable",
          title: "Claim says nothing about this input",
          detail: "Its starting condition is false, so its promise is not checked here."
        }

      "not_probed" ->
        %{
          state: "unavailable",
          title: "No check wired up for this event",
          detail: "Read the source for its scope."
        }

      _ ->
        %{
          state: "unavailable",
          title: "Check unavailable",
          detail: "Check the input and source details before trying again."
        }
    end
  end

  defp slot_count(1), do: "1 slot"
  defp slot_count(value), do: "#{value} slots"

  defp nested_form(params, index, field, name),
    do: to_form(params, as: "#{name}[#{field}][#{index}]")
end
