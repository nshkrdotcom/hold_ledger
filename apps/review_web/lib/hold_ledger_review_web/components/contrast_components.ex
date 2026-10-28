defmodule HoldLedgerReviewWeb.ContrastComponents do
  @moduledoc false
  use HoldLedgerReviewWeb, :html
  import HoldLedgerReviewWeb.DissectorComponents, only: [truth: 1, term: 1]

  attr :case, :map, default: nil
  attr :step, :map, default: nil
  attr :slug, :string, required: true
  attr :editor, :string, default: nil
  attr :candidate_form, :any, default: nil
  attr :initial_form, :any, default: nil
  attr :invalid, :boolean, default: false

  def contrast(assigns) do
    ~H"""
    <section class="instrument" id="contrast">
      <header>
        <span class="section-number">01</span><h2>Concrete contrast</h2>
      </header>
      <div :if={@step && @step["output"]}>
        <p class="case-input" id="case-input">
          {term(@step["before"])}<br /><strong>{term(@step["event"])}</strong>
        </p>
        <ul class="starting-entries">
          <li :for={entry <- @step["before"]["entries"]}>{term(entry)}</li>
        </ul>
        <p :if={@step["origin"] != "computed"} id="hypothetical-lineage" class="signal">
          Hypothetical continuation
        </p>
        <div class="output-pair">
          <.output
            title="Ledger"
            output={if @case, do: @case["actual"], else: @step["output"]}
            id="ledger-output"
          />
          <.output
            :if={@case}
            title="Hypothetical"
            output={@case["candidate"]}
            id="hypothetical-output"
          />
        </div>
        <p :if={@invalid} id="invalid-candidate" role="alert">
          Invalid candidate. No candidate verdict is shown.
        </p>
        <table :if={@case} id="contrast-matrix">
          <thead>
            <tr>
              <th>Check</th><th>Ledger</th><th>Hypothetical</th>
            </tr>
          </thead><tbody>
            <tr id="validity-row">
              <td><code>Spec.valid?(after)</code></td><td>
                <.truth value={@case["actual_valid"]} />
              </td><td><.truth value={@case["candidate_valid"]} /></td>
            </tr>
            <tr id="selected-law-row">
              <td><code>{@slug}</code></td><td>{actual_result(@case)}</td><td class={
                candidate_class(@case)
              }>
                {candidate_result(@case)}
              </td>
            </tr>
            <tr :if={@case["comparison_law"] != @slug && @case["comparison_status"] != "not_probed"}>
              <td>
                <button
                  class="text-button"
                  phx-click="inspect_law"
                  phx-value-slug={@case["comparison_law"]}
                >{@case["comparison_law"]}</button>
              </td><td>{if @case["comparison_actual"] == true, do: "true", else: "unprobed"}</td><td>
                {status(@case["comparison_status"])}
              </td>
            </tr>
          </tbody>
        </table>
        <div class="action-row">
          <button phx-click="early_release" id="early-release">Early release</button><button phx-click="restore_candidate">Use Ledger output</button><button
            phx-click="edit_candidate"
            id="edit-candidate"
          >Edit hypothetical output</button><button
            phx-click="inspect_law"
            phx-value-slug="po_exposure_retain"
            id="inspect-retention"
          >Inspect retention</button>
        </div>
        <p class="scope-note">
          Reference: {@step["oracle"]["result"]}. Hypothetical output ≠ observed behavior.
        </p>
      </div>
      <p :if={@step && !@step["output"]}>Coupled model step. Remote records are shown below.</p>
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
          <button phx-click="candidate_recalculate" id="recalculate">Recalculate totals</button><button phx-click="candidate_add_entry">Add entry</button><button phx-click="candidate_add_effect">Add void effect</button><button phx-click="candidate_clear_effects">Clear effects</button><button
            phx-click="branch_candidate"
            id="branch-candidate"
            disabled={!@case || !@case["candidate_valid"]}
          >Continue hypothetical branch</button>
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
      <h3>{@title}</h3><strong>{@output["after"]["used_amount"]}¢ reserved</strong><p>
        {@output["after"]["used_holds"]} slots · {@output["result"]}
      </p><ul>
        <li :for={entry <- @output["after"]["entries"]}>{term(entry)}</li>
      </ul><p class="effect-list">
        Effects: {if @output["effects"] == [],
          do: "none",
          else: Enum.map_join(@output["effects"], ", ", &term/1)}
      </p>
    </article>
    """
  end

  defp nested_form(params, index, field, name),
    do: to_form(params, as: "#{name}[#{field}][#{index}]")

  defp status("allows_here"), do: "true"
  defp status("catches"), do: "false"
  defp status("doesnt_apply"), do: "outside domain"
  defp status(_), do: "unresolved"

  defp actual_result(case_data) do
    values = Enum.map(case_data["explanation"]["bindings"], &get_in(&1, ["actual", "value"]))

    cond do
      false in values -> "false"
      true in values -> "true"
      true -> "outside domain / unprobed"
    end
  end

  defp candidate_result(case_data), do: status(case_data["law_status"])
  defp candidate_class(%{"law_status" => "catches"}), do: "no"
  defp candidate_class(%{"law_status" => "allows_here"}), do: "yes"
  defp candidate_class(_), do: "muted"
end
