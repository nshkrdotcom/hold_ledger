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
          />
          <.output
            :if={@case}
            title="What if it returned…"
            output={@case["candidate"]}
            id="hypothetical-output"
          />
        </div>
        <section :if={@differences} id="output-differences" class="output-differences" aria-live="polite">
          <h3>Code result → editable alternative</h3>
          <p :if={@differences.same?} id="same-output">Same as code result.</p>
          <ol :if={!@differences.same?}>
            <li :for={{difference, index} <- Enum.with_index(@differences.rows)} id={"difference-#{index}"}>
              <strong>{difference.label}</strong>
              <span>{difference.before} <span aria-label="changed to">→</span> {difference.after}{difference.delta}</span>
            </li>
          </ol>
          <p :if={!@differences.same?} class="scope-note">
            Repeated identities are shown as occurrences, not presumed to be the same entry.
            This is an unsaved alternative, not observed execution or a source-version comparison.
          </p>
        </section>
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

  def editors(assigns) do
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
        <section :if={@case} id="json-editor">
          <h3>Output JSON</h3>
          <.form
            for={to_form(%{"json" => Jason.encode!(@case["candidate"], pretty: true)})}
            id="candidate-json-form"
            phx-submit="candidate_json"
          >
            <.input
              name="json"
              value={Jason.encode!(@case["candidate"], pretty: true)}
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
      <p class="scope-note">Predicate outcomes describe the selected rule, not whether an alternative is desirable.</p>
      <table :if={@case} id="contrast-matrix">
        <thead><tr><th>Question</th><th>Code result</th><th>Alternative (not executed)</th></tr></thead>
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
              <button class="text-button" phx-click="inspect_law" phx-value-slug={@case["comparison_law"]}>
                {ReviewCopy.title(%{"slug" => @case["comparison_law"]})}
              </button>
            </th>
            <td>{if @case["comparison_actual"] === true, do: "Accepts code result", else: "Unavailable"}</td>
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

  def output(assigns) do
    ~H"""
    <article class="output" id={@id}>
      <h3>{@title}</h3><strong>{@output["after"]["used_amount"]}¢ reserved</strong><meter
        class="money-bar"
        min="0"
        max={max(@output["after"]["amount_limit"], 1)}
        value={@output["after"]["used_amount"]}
        aria-label={@title <> ": reserved money"}
      ></meter><p>
        {@output["after"]["used_holds"]} slots · {ReviewCopy.result(@output["result"])}
      </p>
      <dl class="output-fields">
        <div><dt>Amount limit</dt><dd>{@output["after"]["amount_limit"]}¢</dd></div>
        <div><dt>Hold limit</dt><dd>{@output["after"]["hold_limit"]} slots</dd></div>
        <div><dt>Used hold slots</dt><dd>{@output["after"]["used_holds"]}</dd></div>
        <div><dt>Result</dt><dd>{@output["result"]}</dd></div>
      </dl>
      <ul>
        <li :for={{entry, index} <- Enum.with_index(@output["after"]["entries"])}>
          <span>{entry["key"]} · {entry["amount"]}¢</span>
          <button
            :if={@id == "hypothetical-output"}
            class="status-pill"
            phx-click="cycle_status"
            phx-value-index={index}
            title={entry["status"]}
          >{ReviewCopy.state(entry["status"])}</button>
          <span :if={@id != "hypothetical-output"} class="status-pill" title={entry["status"]}>{ReviewCopy.state(
            entry["status"]
          )}</span>
        </li>
      </ul><p class="effect-list">
        Next action: {if @output["effects"] == [],
          do: "none",
          else: Enum.map_join(@output["effects"], ", ", &ReviewCopy.action/1)}
      </p>
    </article>
    """
  end

  defp nested_form(params, index, field, name),
    do: to_form(params, as: "#{name}[#{field}][#{index}]")

end
