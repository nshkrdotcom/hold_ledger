defmodule HoldLedgerReviewWeb.ReviewComponents do
  @moduledoc false
  use HoldLedgerReviewWeb, :html
  alias HoldLedgerReview.ReviewWorkspace
  import HoldLedgerReviewWeb.DissectorComponents, only: [term: 1]

  attr :reading, :map, required: true
  attr :case, :map, default: nil
  attr :step, :map, default: nil
  attr :package, :map, default: nil
  attr :delta, :map, required: true
  attr :preview, :any, default: nil
  attr :compare_form, :any, required: true
  attr :snapshots, :list, required: true
  attr :show_sources, :boolean, required: true
  attr :doc, :map, required: true

  def comparison(assigns) do
    example =
      if assigns.step && assigns.reading["slug"] == "po_a2",
        do: ReviewWorkspace.example(assigns.step)

    rows =
      if assigns.package && assigns.case,
        do: ReviewWorkspace.replay_rows(assigns.package, assigns.case, assigns.reading["slug"]),
        else: []

    assigns = assign(assigns, example: example, rows: rows)

    ~H"""
    <section id="review-comparison" class="review-surface">
      <header class="review-section-heading">
        <div>
          <span class="eyebrow">Contract change under review</span><h2>{@reading["title"]}</h2>
        </div><button phx-click="show_sources" id="choose-sources">{if @package,
          do: "Change source pair",
          else: "Choose local source pair"}</button>
      </header>
      <div :if={@show_sources} id="source-comparison" class="source-chooser">
        <p>
          Select terminal-staged, operator-trusted sources. Exact content identities are validated before execution.
        </p>
        <.form for={@compare_form} id="compare-form" phx-submit="compare" class="form-row">
          <.input
            field={@compare_form[:baseline]}
            type="select"
            label="Baseline"
            options={@snapshots}
            prompt="Choose baseline snapshot"
          />
          <.input
            field={@compare_form[:proposal]}
            type="select"
            label="Proposal"
            options={@snapshots}
            prompt="Choose proposal snapshot"
          />
          <button class="primary">Attach pair</button>
        </.form>
      </div>
      <p :if={!@package && @example} class="example-label" id="example-provenance">
        Example proposal · illustrates changing ≤ to &lt; · not a checked source revision
      </p>
      <p :if={!@package && !@example} class="example-label">
        Current checkout · no proposal attached
      </p>
      <div :if={@package} class="source-pair-label" id="attached-sources">
        <span title={@package["baseline"]["snapshot_id"]}>Baseline {String.slice(
          @package["baseline"]["snapshot_id"],
          0,
          12
        )}</span><span title={@package["proposal"]["snapshot_id"]}>Proposal {String.slice(
          @package["proposal"]["snapshot_id"],
          0,
          12
        )}</span><span>Exact source pair · pointwise replay required</span>
      </div>
      <div class="review-pair">
        <section class="contract-pane" id="contract-diff">
          <h3>{if @package, do: "Changed conditions / promises", else: "Eligibility condition"}</h3>
          <div :if={!@package && @example} class="diff-lines">
            <div class="removed">
              <span>−</span><code>requires amount <del>&lt;=</del> remaining</code>
            </div>
            <div class="added">
              <span>+</span><code>requires amount <ins>&lt;</ins> remaining</code>
            </div>
            <p>
              The example excludes equality; other eligibility checks remain. Compare coverage with the actual result.
            </p>
          </div>
          <div :if={!@package && !@example} class="diff-lines">
            <code>{@reading["contract"]["requires"] || "Native Lean statement"}</code><p>
              Select a real source pair to inspect changes.
            </p>
          </div>
          <article
            :for={change <- if(@package, do: @package["source_changes"], else: [])}
            class="source-change"
          >
            <h4>{change["path"]}</h4>
            <div
              :for={expression <- (@delta[change["id"]] || %{})["expressions"] || []}
              class="diff-expression"
            >
              <small>{expression["field"]} · {expression["status"]}</small>
              <div class="removed">
                <span>−</span><code><span :for={chunk <- expression["baseline"]} class={chunk["kind"]}>{chunk[
                  "text"
                ]}</span></code>
              </div>
              <div class="added">
                <span>+</span><code><span :for={chunk <- expression["proposal"]} class={chunk["kind"]}>{chunk[
                  "text"
                ]}</span></code>
              </div>
            </div>
            <p :if={((@delta[change["id"]] || %{})["expressions"] || []) == []}>
              No supported normalized claim comparison. Read the changed source.
            </p>
            <div class="source-links">
              <a
                :for={side <- ~w(baseline proposal)}
                href={"/comparisons/#{@package["id"]}/source/#{side}/#{change["id"]}"}
                target="_blank"
                rel="noopener"
              >Read {side} source ↗</a>
            </div>
          </article>
          <.input_strip case={@case} preview={@preview} />
        </section>
        <section class="boundary-pane" id="boundary-fork">
          <h3>Same input, separate questions</h3>
          <p :if={@case} class="boundary-input">
            <strong>{term(@case["event"])}</strong><span>Before: {@case["before"]["used_amount"]}¢ reserved / {@case[
              "before"
            ]["amount_limit"]}¢ limit</span>
          </p>
          <table>
            <thead>
              <tr>
                <th>Question</th><th>Baseline</th><th>Proposal</th>
              </tr>
            </thead><tbody>
              <tr :if={!@package && @example} id="coverage-row">
                <th>Precondition applies?</th><td>{answer(@example.baseline)}</td><td class={
                  if @example.baseline && !@example.proposal, do: "no", else: ""
                }>
                  {answer(@example.proposal)}
                </td>
              </tr>
              <tr :if={@package} id="pair-applicability">
                <th>Any binding applies?</th><td :for={row <- @rows}>{answer(row.requires)}</td>
              </tr>
              <tr :if={@package} id="pair-candidate">
                <th>Candidate promise?</th><td :for={row <- @rows}>{answer(row.candidate)}</td>
              </tr>
              <tr :if={@package} id="pair-execution">
                <th>Actual source result</th><td :for={row <- @rows}>
                  {row.actual || "Not available"}
                </td>
              </tr>
              <tr :if={@package}>
                <th>Replay status</th><td :for={row <- @rows}>{row.status}</td>
              </tr>
              <tr :if={@case} id="execution-row">
                <th>Actual checkout Ledger</th><td colspan="2">
                  {@case["actual"]["result"]} · {@case["actual"]["after"]["used_amount"]}¢ reserved
                </td>
              </tr>
              <tr :if={@case} id="candidate-row">
                <th>Hypothetical output</th><td colspan="2">
                  {@case["candidate"]["result"]} · {@case["candidate"]["after"]["used_amount"]}¢ reserved · {@case[
                    "law_status"
                  ]}
                </td>
              </tr>
            </tbody>
          </table>
          <p
            :if={@example && !@package && @example.baseline && !@example.proposal}
            class="boundary-callout"
            id="lost-guarantee"
          >
            The example proposal makes no promise here. The actual implementation still admits the request.
          </p>
          <p :if={@package} class="scope-note">
            Applicability means at least one evaluated binding applies; candidate failure means at least one evaluated promise fails. Inspect individual bindings in Clauses. Unresolved values stay unresolved.
          </p>
          <p class="scope-note">
            A failed precondition is not an implementation rejection. A permitted hypothetical output is not an observed bug.
          </p>
          <div class="action-row">
            <button id="replay-pair" phx-click="replay" disabled={!@package || !@case}>Replay scratch input on both sources</button><button
              phx-click="workspace_view"
              phx-value-view="outputs"
            >Edit hypothetical output</button>
          </div>
          <p :if={@preview} class="scratch-label" id="scratch-status">
            Scratch input · not appended to the recorded trace
          </p>
          <div
            :for={attempt <- if(@package, do: @package["replay_attempts"], else: [])}
            class="attempt"
          >
            <span>{attempt["status"]}</span><button
              :if={attempt["status"] in ~w(queued running)}
              phx-click="cancel"
              phx-value-id={attempt["id"]}
            >Cancel</button>
          </div>
        </section>
      </div>
    </section>
    <section class="review-surface decision-docket" id="decision-docket">
      <header>
        <h2>Review disposition</h2><span class="scope-note">{if @package,
          do: "Stored evidence · revision #{@package["human_revision"]}",
          else: "Example review · local note only"}</span>
      </header>
      <p :if={!@package}>Does this proposed condition still express the required behavior?</p>
      <article
        :for={evidence <- if(@package, do: @package["evidence"], else: [])}
        class="pair-evidence"
      >
        <strong>{evidence["kind"]}</strong><p>{evidence["note"]}</p><a href={"/comparisons/#{@package["id"]}/repair/#{evidence["id"]}.json"}>Download local repair packet</a><div class="decision-actions">
          <button
            :for={
              {action, label} <- [
                {"design", "Request repair"},
                {"policy", "Needs policy / evidence decision"},
                {"considered", "Considered in scope"}
              ]
            }
            phx-click="review_decision"
            phx-value-action={action}
            phx-value-evidence={evidence["id"]}
          >{label}</button>
        </div>
      </article>
      <div :if={!@package} class="decision-actions">
        <button id="request-repair" phx-click="review_decision" phx-value-action="design">Request repair</button><button
          phx-click="review_decision"
          phx-value-action="policy"
        >Needs policy / evidence decision</button><button
          phx-click="review_decision"
          phx-value-action="considered"
        >Considered in scope</button>
      </div>
      <p class="scope-note">
        Records a scoped reviewer action. Does not merge/block a PR, authorize policy or grant formal acceptance.
      </p>
      <p
        :for={finding <- if(@package, do: @package["human_findings"], else: [])}
        class="disposition-history"
      >
        {finding["rationale"]}
      </p>
      <p :for={note <- @doc["notes"]} class="disposition-history">{note["text"]}</p>
    </section>
    """
  end

  attr :case, :map, default: nil
  attr :preview, :any, default: nil

  def input_strip(assigns) do
    request = assigns.case && assigns.case["event"]["type"] == "request"

    assigns =
      assign(assigns,
        request: request,
        amount: if(request, do: assigns.case["event"]["amount"], else: "")
      )

    ~H"""
    <div class="selected-input" id="selected-input">
      <div>
        <strong>Explore selected input</strong><small>{if @request,
          do: "Recomputes this case without writing history",
          else: "This event has no amount parameter"}</small>
      </div>
      <.form for={to_form(%{"amount" => @amount})} id="amount-preview" phx-change="preview_amount">
        <.input
          name="amount"
          id="review-amount"
          value={@amount}
          type="number"
          min="1"
          max="1000000"
          label="Amount (¢)"
          disabled={!@request}
        />
      </.form>
      <div class="boundary-buttons">
        <button phx-click="boundary" phx-value-offset="-1" disabled={!@request}>Below</button><button
          phx-click="boundary"
          phx-value-offset="0"
          disabled={!@request}
        >Exact fit</button><button phx-click="boundary" phx-value-offset="1" disabled={!@request}>Above</button>
      </div>
      <button phx-click="apply_preview" disabled={!@preview} id="append-preview">Append this case to trace</button>
    </div>
    """
  end

  attr :reading, :map, required: true
  attr :stage, :integer, required: true

  def proof_source(assigns) do
    selected = Enum.at(assigns.reading["proof_steps"], assigns.stage)
    declaration = List.first(assigns.reading["declarations"])
    assigns = assign(assigns, selected: selected, declaration: declaration)

    ~H"""
    <section class="review-surface" id="proof-source-workspace">
      <header class="review-section-heading">
        <h2>Proof source & reasoning</h2><span class="type-badge">Source reading · not a captured goal state</span>
      </header>
      <nav class="proof-source-stages">
        <button
          :for={{step, index} <- Enum.with_index(@reading["proof_steps"])}
          phx-click="proof_stage"
          phx-value-index={index}
          aria-current={if index == @stage, do: "step", else: "false"}
        >{index + 1}. {step["title"]}</button>
      </nav>
      <div class="proof-source-pair">
        <div class="numbered-proof" id="proof-script" phx-hook="ProofSource" data-stage={@stage}>
          <div
            :for={
              {line, n} <-
                Enum.with_index(
                  String.split(@declaration["text"] || "", "\n"),
                  @declaration["line"] || 1
                )
            }
            class={
              if @selected && n >= @selected["line"] && n < @selected["line"] + 7,
                do: "active-proof-line",
                else: ""
            }
          >
            <span>{n}</span><code>{line}</code>
          </div>
        </div>
        <aside>
          <h3>Statement</h3><pre>{@declaration["header"]}</pre><h3 :if={@selected}>
            {@selected["title"]}
          </h3><p :if={@selected}>{@selected["reason"]}</p><p :if={!@selected}>
            No source-guided stages for this obligation. Read the actual declaration or inline law proof.
          </p><pre :if={@reading["inline_proof"]}>{@reading["inline_proof"]["text"]}</pre>
        </aside>
      </div>
      <section id="lean-bridge">
        <h3>Lynx producer artifacts</h3><p>
          Focused elaboration: <span id="focused-status">{@reading["focused"]["status"]}</span>. Full gate: <span id="formal-status">{@reading["formal"]["status"]}</span>.
        </p><ul id="generated-artifacts">
          <li :for={item <- @reading["focused"]["artifacts"] || []}>
            <a
              href={"/claims/#{@reading["slug"]}/generated/#{item["sha256"]}"}
              target="_blank"
              rel="noopener"
            >{Path.basename(item["path"])} ↗</a>
          </li>
        </ul><div id="lemma-links">
          <span :for={ref <- @reading["references"]}><a
            :for={d <- ref["declarations"]}
            href={HoldLedgerReviewWeb.DissectorComponents.source_url(@reading, d["path"])}
            target="_blank"
            rel="noopener"
          >{ref["name"]} ↗</a></span>
        </div>
      </section>
    </section>
    """
  end

  attr :case, :map, default: nil
  attr :fencing, :boolean, required: true

  def premise(assigns) do
    key = if assigns.case, do: assigns.case["event"]["key"]

    result =
      if assigns.case,
        do: ReviewWorkspace.premise(assigns.case["actual"]["after"], key, assigns.fencing),
        else: %{status: "not_applicable"}

    assigns = assign(assigns, result: result)

    ~H"""
    <section class="review-surface" id="premise-comparison">
      <header class="review-section-heading">
        <h2>External premise: terminal fencing</h2><span class="type-badge">Current-entry illustration</span>
      </header>
      <p :if={@result.status == "not_applicable"}>
        Select an authorized or voiding entry to examine delayed delivery after its terminal confirmation.
      </p>
      <div :if={@result.status != "not_applicable"}>
        <p>
          Identity #{@result.key} · {@result.amount}¢ · hypothetical terminal confirmation, then delayed authorization.
        </p>
        <button
          role="switch"
          id="fencing-toggle"
          aria-checked={to_string(@fencing)}
          phx-click="toggle_assumption"
          phx-value-name="fencing"
        >Terminal fencing {if @fencing, do: "on", else: "off"}</button>
        <table>
          <thead>
            <tr>
              <th>Same identity</th><th>After delayed delivery</th>
            </tr>
          </thead><tbody>
            <tr>
              <th>Local retained capacity for this key</th><td id="premise-local">
                {@result.local}¢
              </td>
            </tr><tr>
              <th>Remote authorization for this key</th><td id="premise-remote">{@result.remote}¢</td>
            </tr><tr>
              <th>Identity remains covered?</th><td id="premise-covered">
                {answer(@result.covered)}
              </td>
            </tr>
          </tbody>
        </table>
        <p class="scope-note">
          {@result.provenance}. This view does not change your recorded state or validate a real processor.
        </p>
      </div>
    </section>
    """
  end

  defp answer(true), do: "Yes"
  defp answer(false), do: "No"
  defp answer(_), do: "Unresolved / not run"
end
