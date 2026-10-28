defmodule HoldLedgerReviewWeb.ReviewComponents do
  @moduledoc false
  use HoldLedgerReviewWeb, :html
  alias HoldLedgerReview.ReviewWorkspace
  alias HoldLedgerReviewWeb.ReviewCopy
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

    policy_source =
      Enum.find(assigns.reading["sources"], &(&1["path"] == "guides/specification.md"))

    assigns = assign(assigns, example: example, policy_source: policy_source)

    ~H"""
    <section id="review-comparison" class="rule-summary">
      <div class="section-heading">
        <span class="eyebrow">Rule</span><button phx-click="show_sources" id="choose-sources">Compare versions</button>
      </div>
      <h1>{ReviewCopy.title(@reading)}</h1>
      <p id="policy-anchor">
        {ReviewCopy.policy(@reading)}
        <button
          :if={@policy_source}
          class="text-button"
          id="policy-source"
          phx-click="inspect_registered_source"
          phx-value-id={@policy_source["id"]}
          phx-value-sha={@policy_source["sha256"]}
        >Read requirement</button>
      </p>
      <div :if={@show_sources} id="source-comparison" class="source-chooser">
        <p>Choose two trusted local versions to run the same case against each.</p><.form
          for={@compare_form}
          id="compare-form"
          phx-submit="compare"
          class="form-row"
        >
          <.input
            field={@compare_form[:baseline]}
            type="select"
            label="Before"
            options={@snapshots}
            prompt="Choose version"
          /><.input
            field={@compare_form[:proposal]}
            type="select"
            label="After"
            options={@snapshots}
            prompt="Choose version"
          /><button>Compare</button>
        </.form><p :if={@package} class="source-pair-label">
          Before {@package["baseline"]["snapshot_id"]} · After {@package["proposal"]["snapshot_id"]}
        </p>
      </div>
      <section id="contract-diff">
        <span :if={!@package && @example} id="example-provenance" class="example-label">Example change</span>
        <div :if={!@package && @example} class="diff-lines">
          <div class="removed"><span>Before</span><code>amount <del>&lt;=</del> remaining</code></div><div class="added">
            <span>After</span><code>amount <ins>&lt;</ins> remaining</code>
          </div>
        </div>
        <code :if={!@package && !@example}>{@reading["contract"]["requires"] || "Lean statement"}</code>
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
      </section>
    </section>
    """
  end

  attr :case, :map, default: nil
  attr :reading, :map, required: true
  attr :step, :map, default: nil
  attr :package, :map, default: nil
  attr :preview, :any, default: nil

  def pair_results(assigns) do
    example =
      if assigns.step && assigns.reading["slug"] == "po_a2",
        do: ReviewWorkspace.example(assigns.step)

    rows =
      if assigns.package && assigns.case,
        do: ReviewWorkspace.replay_rows(assigns.package, assigns.case, assigns.reading["slug"]),
        else: []

    assigns = assign(assigns, example: example, rows: rows)

    ~H"""
    <section :if={@package || @example} class="boundary-pane" id="boundary-fork">
      <h3>
        {cond do
          @package -> "Compare versions"
          @example -> "Example: changing ≤ to <"
          true -> ""
        end}
      </h3>
      <p :if={@case} class="boundary-input">
        <strong>{term(@case["event"])}</strong><span>Before: {@case["before"]["used_amount"]}¢ reserved / {@case[
          "before"
        ]["amount_limit"]}¢ limit</span>
      </p>
      <dl id="source-coverage" class="coverage-list">
        <div :if={!@package && @example} id="coverage-row">
          <dt>Old rule covers this request</dt><dd id="coverage-baseline">
            {answer(@example.baseline)}
          </dd><dt>Changed rule covers it</dt><dd id="coverage-proposal">
            {answer(@example.proposal)}
          </dd>
        </div>
        <div :if={@package} id="pair-applicability">
          <dt>Does the rule cover this case?</dt><dd :for={row <- @rows}>
            <strong>{row.side}</strong> {answer(row.requires)}
          </dd>
        </div>
        <div :if={@package} id="pair-candidate">
          <dt>Would the rule accept this alternative?</dt><dd :for={row <- @rows}>
            <strong>{row.side}</strong> {answer(row.candidate)}
          </dd>
        </div>
        <div :if={@package} id="pair-execution">
          <dt>Code returned</dt><dd :for={row <- @rows}>
            <strong>{row.side}</strong> {row.actual || "Not run for this input"}
          </dd>
        </div>
        <div :if={@package}>
          <dt>Run status</dt><dd :for={row <- @rows}><strong>{row.side}</strong> {row.status}</dd>
        </div>
      </dl>
      <p
        :if={@example && !@package && @example.baseline && !@example.proposal}
        class="boundary-callout"
        id="lost-guarantee"
      >
        The changed rule no longer covers this request. The code still accepts it.
      </p>
      <div class="action-row">
        <button :if={@package} id="replay-pair" phx-click="replay" disabled={!@case}>Run on both versions</button><button
          :if={!@package}
          id="choose-replay-sources"
          phx-click="show_sources"
        >Compare source versions</button>
      </div>
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
    """
  end

  attr :package, :map, default: nil
  attr :doc, :map, required: true
  attr :selected_evidence, :any, default: nil

  def disposition(assigns) do
    evidence = if assigns.package, do: assigns.package["evidence"], else: []

    selected =
      Enum.find(evidence, &(&1["id"] == assigns.selected_evidence)) || List.first(evidence)

    assigns = assign(assigns, evidence: evidence, selected: selected)

    ~H"""
    <section id="decision-docket" class="decision-docket" aria-label="Review disposition">
      <.form
        :if={length(@evidence) > 1}
        for={to_form(%{"id" => @selected["id"]})}
        id="evidence-choice"
        phx-change="select_evidence"
      >
        <.input
          name="id"
          value={@selected["id"]}
          type="select"
          label="Stored finding to review"
          options={
            Enum.map(@evidence, &{&1["kind"] <> " · " <> String.slice(&1["id"], 0, 12), &1["id"]})
          }
        />
      </.form>
      <div :if={!@package || @selected} class="decision-actions">
        <button
          :for={
            {action, label} <- [
              {"design", "Note: needs a fix"},
              {"policy", "Note: requirement is unclear"},
              {"considered", "Note: reviewed"}
            ]
          }
          id={if action == "design", do: "request-repair"}
          phx-click="review_decision"
          phx-value-action={action}
          phx-value-evidence={if @selected, do: @selected["id"]}
        >{label}</button>
      </div>
      <span :if={@package && !@selected} class="scope-note">Run the comparison to attach a note to a specific result.</span>
    </section>
    """
  end

  attr :package, :map, default: nil
  attr :doc, :map, required: true

  def review_history(assigns) do
    ~H"""
    <section id="review-history">
      <h3>Review scope and history</h3><p class="scope-note">
        Your saved observations and comparison results.
      </p>
      <article
        :for={evidence <- if(@package, do: @package["evidence"], else: [])}
        class="pair-evidence"
      >
        <strong>{evidence["kind"]}</strong><p>{evidence["note"]}</p><a href={"/comparisons/#{@package["id"]}/repair/#{evidence["id"]}.json"}>Download local repair packet</a>
      </article>
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
        <strong>Try a request</strong><small>{if @request,
          do: "",
          else: "This event does not request an amount"}</small>
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
        <button phx-click="boundary" phx-value-offset="-1" disabled={!@request}>1¢ less</button><button
          phx-click="boundary"
          phx-value-offset="0"
          disabled={!@request}
        >All available</button><button phx-click="boundary" phx-value-offset="1" disabled={!@request}>1¢ more</button>
      </div>
    </div>
    """
  end

  attr :reading, :map, required: true
  attr :stage, :integer, required: true
  attr :full, :boolean, default: false

  def proof_source(assigns) do
    selected = Enum.at(assigns.reading["proof_steps"], assigns.stage)
    declaration = List.first(assigns.reading["declarations"])

    lines =
      Enum.with_index(String.split(declaration["text"] || "", "\n"), declaration["line"] || 1)

    focus = if selected, do: selected["line"], else: declaration["line"] || 1

    assigns =
      assign(assigns,
        selected: selected,
        declaration: declaration,
        lines:
          if(assigns.full,
            do: lines,
            else: Enum.filter(lines, fn {_, n} -> n >= focus - 1 and n <= focus + 4 end)
          )
      )

    ~H"""
    <section id="proof-source-workspace">
      <header class="section-heading">
        <h2>Proof</h2><button phx-click="full_proof" id="full-proof">{if @full,
          do: "Show selected step",
          else: "Read full proof"}</button>
      </header>
      <nav class="proof-source-stages">
        <button
          :for={{step, index} <- Enum.with_index(@reading["proof_steps"])}
          phx-click="proof_stage"
          phx-value-index={index}
          aria-current={if index == @stage, do: "step", else: "false"}
        >{index + 1}. {step["title"]}</button>
      </nav>
      <div class="numbered-proof" id="proof-script" phx-hook="ProofSource" data-stage={@stage}>
        <div
          :for={{line, n} <- @lines}
          class={if @selected && n == @selected["line"], do: "active-proof-line", else: ""}
        >
          <span>{n}</span><code>{line}</code>
        </div>
      </div>
      <p :if={@selected} class="proof-reading">{@selected["reason"]}</p>
      <div id="lemma-links">
        <span :for={ref <- Enum.take(@reading["references"], 3)}><button
          class="text-button"
          phx-click="lemma"
          phx-value-name={ref["name"]}
        >{ref["name"]}</button><a
          :for={d <- Enum.take(ref["declarations"], 1)}
          href={HoldLedgerReviewWeb.DissectorComponents.source_url(@reading, d["path"])}
          target="_blank"
          rel="noopener"
        >↗</a></span>
      </div>
    </section>
    """
  end

  attr :reading, :map, required: true

  def verification_files(assigns) do
    ~H"""
    <p id="goal-state-status">Saved Lean hypotheses and goals: unavailable.</p>
    <section id="lean-bridge">
      <h3>Lynx producer artifacts</h3><p>
        Focused elaboration: <span id="focused-status">{@reading["focused"]["status"]}</span>. Full gate: <span id="formal-status">{@reading["formal"]["status"]}</span>.
      </p><ul id="generated-artifacts">
        <li :for={item <- @reading["focused"]["artifacts"] || []}>
          <button class="text-button" phx-click="inspect_artifact" phx-value-sha={item["sha256"]}>{Path.basename(
            item["path"]
          )}</button><a
            href={"/claims/#{@reading["slug"]}/generated/#{item["sha256"]}"}
            target="_blank"
            rel="noopener"
          >{Path.basename(item["path"])} ↗</a>
        </li>
      </ul><div id="all-lemma-links">
        <span :for={ref <- @reading["references"]}><button
          class="text-button"
          phx-click="lemma"
          phx-value-name={ref["name"]}
        >{ref["name"]}</button><a
          :for={d <- ref["declarations"]}
          href={HoldLedgerReviewWeb.DissectorComponents.source_url(@reading, d["path"])}
          target="_blank"
          rel="noopener"
        >{ref["name"]} ↗</a></span>
      </div>
    </section>
    """
  end

  attr :proof, :map, required: true
  attr :package, :map, required: true
  attr :slug, :string, required: true

  def pair_artifacts(assigns) do
    ~H"""
    <section id="pair-proof-artifacts" class="pair-artifacts">
      <h3>Source-pair proof artifacts</h3>
      <section :for={version <- @proof["versions"]}>
        <h4>{version["side"]}: {version["formal_acceptance"]}</h4><p>{version["report_status"]}</p>
        <p :for={law <- Enum.filter(version["sources"], &(&1["slug"] == @slug))}>
          {law["slug"]} · {law["artifact_scope"]} · {if law["translated_statement"],
            do: "translation supplied",
            else: "translation missing"} · {if law["proof_dependencies"],
            do: "dependencies supplied",
            else: "dependencies missing"}
        </p>
        <a
          :for={item <- Enum.filter(version["artifacts"], &(&1["status"] == "present"))}
          href={"/comparisons/#{@package["id"]}/artifact/#{version["side"]}/#{item["sha256"]}"}
        >{item["kind"]}: {item["path"]}</a>
      </section>
    </section>
    """
  end

  attr :case, :map, default: nil
  attr :fencing, :boolean, required: true
  attr :selected_key, :any, default: nil

  def premise(assigns) do
    entries =
      if assigns.case,
        do:
          Enum.filter(
            assigns.case["actual"]["after"]["entries"],
            &(&1["status"] in ~w(authorized voiding))
          ),
        else: []

    key =
      if Enum.any?(entries, &(&1["key"] == assigns.selected_key)),
        do: assigns.selected_key,
        else: (List.first(entries) || %{})["key"]

    result =
      if assigns.case,
        do: ReviewWorkspace.premise(assigns.case["actual"]["after"], key, assigns.fencing),
        else: %{status: "not_applicable"}

    assigns = assign(assigns, result: result, entries: entries, selected_key: key)

    ~H"""
    <section class="review-surface" id="premise-comparison">
      <header class="review-section-heading">
        <h2>Can a cancelled hold reappear?</h2><span class="type-badge">Processor model</span>
      </header>
      <.form
        :if={@entries != []}
        for={to_form(%{"key" => @selected_key})}
        id="premise-selector"
        phx-change="premise_key"
      >
        <.input
          name="key"
          value={@selected_key}
          type="select"
          label="Entry to challenge"
          options={
            Enum.map(@entries, &{"Key #{&1["key"]} · #{&1["amount"]}¢ · #{&1["status"]}", &1["key"]})
          }
        />
      </.form>
      <p :if={@result.status == "not_applicable"}>
        This case has no hold waiting for cancellation.
        <button id="open-premise-case" phx-click="open_premise_case">Try a cancellation case</button>
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
        >Processor remembers cancellations: {if @fencing, do: "on", else: "off"}</button>
        <table>
          <thead>
            <tr>
              <th>Same identity</th><th>After delayed delivery</th>
            </tr>
          </thead><tbody>
            <tr>
              <th>Money reserved locally</th><td id="premise-local">
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
