defmodule HoldLedgerReviewWeb.ContrastComponents do
  @moduledoc false
  use HoldLedgerReviewWeb, :html
  alias HoldLedgerReviewWeb.{OutputDifferences, ReviewCopy}

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
        <span class="section-number">01</span><h2>Outputs</h2>
      </header>
      <div :if={@step && @step["output"]}>
        <p :if={@step["origin"] != "computed"} id="hypothetical-lineage" class="signal">
          Continuing from the alternative
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
            title="What if it returned…"
            output={@case["candidate"]}
            id="hypothetical-output"
            differences={@differences}
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
          <h3>Code result → editable alternative</h3>
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
          <p class="scope-note">
            A changed value is not a policy judgment. Repeated identities remain separate
            occurrences; ambiguous rows are not silently paired. This alternative is unsaved.
          </p>
        </details>
        <p :if={@invalid} id="invalid-candidate" role="alert">
          Enter a whole number or valid output JSON to check this alternative.
        </p>
        <button id="edit-candidate" phx-click="edit_candidate">Edit alternative</button>
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
      <h3>Change the result</h3>
      <div class="mutation-chips" id="candidate-mutations">
        <button phx-click="mutate_candidate" phx-value-kind="drop_effects">Remove requested actions</button>
        <button phx-click="mutate_candidate" phx-value-kind="zero_counters">Zero both totals</button>
        <button phx-click="mutate_candidate" phx-value-kind="change_identity">Change first identity</button>
        <button phx-click="candidate_recalculate" id="recalculate-inline">Recalculate totals</button>
      </div>
      <div class="action-row">
        <button phx-click="early_release" id="early-release">Release the hold</button><button phx-click="restore_candidate">Reset to code result</button><button
          phx-click="show_advanced"
          id="advanced-editor"
        >Full state / JSON editor</button><button
          phx-click="inspect_law"
          phx-value-slug="po_exposure_retain"
          id="inspect-retention"
        >Inspect retention</button>
      </div>
      <div class="action-row">
        <button
          phx-click="branch_candidate"
          id="branch-candidate"
          disabled={!@case || !@case["candidate_valid"]}
        >Continue from this alternative</button>
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
          phx-submit="check_candidate"
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
          <button class="primary" id="check-candidate">Check output</button>
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
    ~H"""
    <section id="verdict" class="verdict-panel" aria-label="Checks for this case">
      <h2>Checks for this case</h2>
      <p class="scope-note">
        Predicate outcomes describe the selected rule, not whether an alternative is desirable.
      </p>
      <div :if={@case} id="active-predicate-result" class="predicate-focus" role="status">
        <div class="predicate-heading">Selected rule · output satisfaction</div>
        <div class="predicate-pair">
          <div><span>Code result</span><strong>{ReviewCopy.code_acceptance(@case)}</strong></div>
          <div>
            <span>Alternative (not executed)</span><strong>{ReviewCopy.candidate_acceptance(@case)}</strong>
          </div>
        </div>
      </div>
      <table :if={@case} id="contrast-matrix">
        <thead>
          <tr>
            <th>Question</th><th>Code result</th><th>Alternative (not executed)</th>
          </tr>
        </thead>
        <tbody>
          <tr id="applicability-row">
            <th scope="row">Does the rule apply?</th>
            <td colspan="2">{ReviewCopy.applicability(@case)}</td>
          </tr>
          <tr id="selected-law-row">
            <th scope="row">Does the output satisfy the rule?</th>
            <td>{ReviewCopy.code_acceptance(@case)}</td>
            <td>{ReviewCopy.candidate_acceptance(@case)}</td>
          </tr>
          <tr id="validity-row">
            <th scope="row">Is accounting internally valid?</th>
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
              {if @case["comparison_actual"] === true, do: "Accepts code result", else: "Unavailable"}
            </td>
            <td>{ReviewCopy.candidate_acceptance(%{"law_status" => @case["comparison_status"]})}</td>
          </tr>
        </tbody>
      </table>
      <p :if={@case && ReviewCopy.candidate_acceptance(@case) == "Unavailable"} class="scope-note">
        Alternative check unavailable: {@case["law_reason"]}.
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
        label={String.replace(field, "_", " ")}
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

  def output(assigns) do
    ~H"""
    <article class="output" id={@id}>
      <h3>{@title}</h3>
      <div class="output-headline">
        <strong>{@output["after"]["used_amount"]}¢ reserved</strong>
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
      <dl class="output-fields">
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
          >{ReviewCopy.state(entry["status"])}</button>
          <span :if={@id != "hypothetical-output"} class="status-pill" title={entry["status"]}>
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
        aria-label="Entries absent from alternative"
      >
        <li :for={ghost <- @differences.ghosts} class="comparison-ghost">
          <span>{ghost.entry["key"]} · {ghost.entry["amount"]}¢ · {ReviewCopy.state(
            ghost.entry["status"]
          )}</span>
          <small>Absent from alternative · original position {ghost.before_index + 1}</small>
        </li>
      </ul>
      <div class="effect-list">
        <strong>Next actions</strong>
        <p :if={@output["effects"] == []}>none</p>
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
          Action membership or order differs; see Full differences.
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

  defp slot_count(1), do: "1 slot"
  defp slot_count(value), do: "#{value} slots"

  defp nested_form(params, index, field, name),
    do: to_form(params, as: "#{name}[#{field}][#{index}]")
end
