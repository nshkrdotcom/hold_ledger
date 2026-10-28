defmodule HoldLedgerReviewWeb.LabComponents do
  @moduledoc false
  use HoldLedgerReviewWeb, :html
  alias HoldLedgerReview.{Trace, VisualLab}
  import HoldLedgerReviewWeb.DissectorComponents, only: [term: 1, frontier: 1]

  attr :doc, :map, required: true
  attr :cursor, :string, required: true
  attr :case, :map, default: nil
  attr :reading, :map, required: true
  attr :basis, :string, required: true
  attr :binding_index, :integer, default: 0
  attr :stage, :integer, required: true
  attr :fencing, :boolean, required: true
  attr :durable, :boolean, required: true
  attr :environment_position, :integer, required: true
  attr :hunt, :map, required: true

  def laboratory(assigns) do
    {:ok, state} = Trace.state_at(assigns.doc, assigns.cursor)
    ledger = if assigns.doc["mode"] == "ledger", do: state, else: state["ledger"]
    before = if assigns.case, do: assigns.case["before"], else: ledger
    output = if assigns.case, do: assigns.case[assigns.basis], else: nil
    frames = VisualLab.proof_frames(assigns.reading)
    environment = VisualLab.environment(assigns.fencing, assigns.durable)

    binding =
      if assigns.case, do: Enum.at(assigns.case["explanation"]["bindings"], assigns.binding_index)

    assigns =
      assign(assigns,
        before: before,
        output: output,
        frames: frames,
        frame: Enum.at(frames, assigns.stage),
        environment: environment,
        environment_frame: Enum.at(environment, assigns.environment_position),
        binding: binding,
        law_result: law_result(assigns.case, assigns.basis)
      )

    ~H"""
    <div
      id="visual-lab"
      phx-hook="VisualLab"
      data-stage={@stage}
      data-proof-count={length(@frames)}
      data-environment-position={@environment_position}
    >
      <div class="lab-topline">
        <span><i class="live-dot" /> Local execution</span>
        <span>Explore → inspect → challenge</span>
        <a href="#technical-inspector">Source & evidence ↓</a>
      </div>
      <div class="lab-primary">
        <section class="lab-panel scene-panel" id="account-stage">
          <header class="lab-panel-header">
            <div>
              <span class="lab-kicker">01 / Concrete case</span><h2>What changes?</h2>
            </div>
            <div class="segmented">
              <button
                phx-click="basis"
                phx-value-value="actual"
                aria-pressed={to_string(@basis == "actual")}
              >Ledger</button><button
                phx-click="basis"
                phx-value-value="candidate"
                aria-pressed={to_string(@basis == "candidate")}
              >Hypothetical</button>
            </div>
          </header>
          <div class="scene-caption">
            <strong>{if @case, do: term(@case["event"]), else: "Choose a transition"}</strong><span class="type-badge">{if @basis ==
                                                                                                                             "candidate",
                                                                                                                           do:
                                                                                                                             "Hypothetical output",
                                                                                                                           else:
                                                                                                                             "Computed output"}</span>
          </div>
          <div class="account-pair">
            <.account state={@before} title="Before" id="visual-before" />
            <div class="transition-arrow" aria-hidden="true">→</div>
            <.account
              state={if @output, do: @output["after"], else: @before}
              title={if @basis == "candidate", do: "What if…", else: "Ledger output"}
              id="visual-after"
            />
          </div>
          <div :if={@case} class="visual-verdicts" id="visual-verdicts">
            <span>Consistent accounting
            <b class={
              if @case[if(@basis == "actual", do: "actual_valid", else: "candidate_valid")],
                do: "yes",
                else: "no"
            }>{if @basis == "actual",
              do: to_string(@case["actual_valid"]),
              else: to_string(@case["candidate_valid"])}</b></span>
            <span>{@reading["slug"]}
            <b class={if @law_result == "Rejects", do: "no", else: "yes"}>{@law_result}</b></span>
          </div>
          <div
            :if={@case && @case["event"]["type"] == "request"}
            class="amount-dial"
            id="amount-dial"
            data-link-target="capacity"
          >
            <.form
              for={to_form(%{"amount" => @case["event"]["amount"]})}
              id="amount-preview"
              phx-change="preview_amount"
            >
              <label for="visual-amount">Request amount <output>{@case["event"]["amount"]}¢</output></label>
              <input
                id="visual-amount"
                type="range"
                name="amount"
                min="1"
                max={max(2, min(1_000_000, @before["amount_limit"] * 2))}
                value={@case["event"]["amount"]}
                phx-throttle="100"
              />
            </.form>
            <div class="boundary-buttons">
              <button phx-click="boundary" phx-value-offset="-1">Below</button><button
                phx-click="boundary"
                phx-value-offset="0"
              >Exact fit</button><button phx-click="boundary" phx-value-offset="1">Above</button><button
                phx-click="apply_preview"
                class="primary"
              >Add to trace</button>
            </div>
            <small>Live input preview · add it to preserve a branch.</small>
          </div>
          <div class="scene-actions">
            <button id="visual-early-release" phx-click="early_release">Release early</button><button phx-click="restore_candidate">Restore actual</button><button
              phx-click="edit_candidate"
              data-open-inspector
            >Build an output ↗</button>
          </div>
          <div class="compact-trace">
            <span class="lab-kicker">Your trace</span><nav
              id="visual-timeline"
              aria-label="Visual trace"
            >
              <button
                phx-click="select_step"
                phx-value-id="start"
                aria-current={if @cursor == "start", do: "step", else: "false"}
              >Start</button><button
                :for={{step, n} <- Enum.with_index(@doc["steps"], 1)}
                phx-click="select_step"
                phx-value-id={step["id"]}
                aria-current={if @cursor == step["id"], do: "step", else: "false"}
              >{n} · {if step["event"]["type"], do: step["event"]["type"], else: "model"}</button>
            </nav>
          </div>
          <div class="scene-actions">
            <button phx-click="previous">← Back</button><button phx-click="next">Forward →</button><button phx-click="next_request">Next 100¢ request</button><button
              :if={@doc["mode"] == "ledger"}
              phx-click="confirm_void"
            >Confirm void</button>
          </div>
        </section>
        <section class="lab-panel expression-panel" id="expression-inspector">
          <header class="lab-panel-header">
            <div>
              <span class="lab-kicker">02 / Why this result</span><h2>Follow the condition</h2>
            </div><span class="type-badge">Real evaluation</span>
          </header>
          <p class="panel-hint">Hover or focus a clause. Pin it to follow its values.</p>
          <nav
            :if={@case && length(@case["explanation"]["bindings"]) > 1}
            class="binding-picker"
            aria-label="Claim binding"
          >
            <button
              :for={{binding, index} <- Enum.with_index(@case["explanation"]["bindings"])}
              phx-click="select_binding"
              phx-value-index={index}
              aria-pressed={to_string(index == @binding_index)}
            >Entry #{binding["values"]["key"]}</button>
          </nav>
          <p :if={@case && length(@case["explanation"]["bindings"]) > 1} class="panel-hint">
            Law result: all tested entries. Tree: selected entry.
          </p>
          <div :if={@binding}>
            <.expression_tree :if={@binding["requires"]} node={@binding["requires"]} label="Requires" />
            <.expression_tree :if={@binding[@basis]} node={@binding[@basis]} label="Expects" />
            <p :if={!@binding[@basis]} class="domain-silence" id="visual-domain-silence">
              Outside this law’s domain. No output promise is evaluated.
            </p>
          </div>
          <p :if={!@binding} class="empty-instrument">
            No supported pointwise binding for this state and law. Actual source remains below.
          </p>
          <div class="discovery-bar">
            <button
              phx-click="hunt"
              id="hunt-candidate"
              disabled={@hunt.status == "running" || !@case}
            >Find a rejected output <span aria-hidden="true">↗</span></button>
            <button :if={@hunt.status == "running"} phx-click="cancel_hunt">Cancel</button>
            <output id="hunt-status" aria-live="polite">{if @hunt.status == "idle",
              do: "≤12 cases · 3s budget",
              else: @hunt.status}{if @hunt[:cases],
              do: " · #{@hunt.cases} cases · #{@hunt.elapsed_ms}ms · seed #{@hunt.seed}"}</output>
          </div>
        </section>
      </div>
      <div class="lab-secondary">
        <section class="lab-panel proof-player" id="proof-player" data-player="proof">
          <header class="lab-panel-header">
            <div>
              <span class="lab-kicker">03 / From facts to a guarantee</span><h2>
                The proof, in motion
              </h2>
            </div><span class="type-badge illustrated">Illustrated</span>
          </header>
          <nav class="proof-track" aria-label="Illustrated proof stages">
            <button
              :for={frame <- @frames}
              phx-click="proof_stage"
              phx-value-index={frame.index}
              aria-current={if frame.index == @stage, do: "step", else: "false"}
            ><span>{frame.index + 1}</span>{frame.title}</button>
          </nav>
          <div :if={@frame} class="infoview" id="illustrated-infoview">
            <div class="infoview-header">
              <span>Given</span><span>{length(@frame.facts)} facts in view</span>
            </div>
            <div class="fact-stack">
              <p :for={{fact, n} <- Enum.with_index(@frame.facts)}><span>h{n + 1}</span>{fact}</p>
            </div>
            <div class="goal-state">
              <span class="turnstile">⊢</span><div>
                <small>Establish</small><strong>{@frame.goal}</strong>
              </div>
            </div>
            <div class="tactic-line">
              <span>Source tactic</span><code>{first_line(@frame.code)}</code>
            </div>
          </div>
          <p :if={!@frame} class="empty-instrument">
            No illustrated proof sequence for this obligation. Read its actual declaration in the inspector.
          </p>
          <div class="playback">
            <button
              type="button"
              data-play="proof"
              disabled={@frames == []}
              aria-label="Play proof illustration"
            >▶ Play</button><button type="button" data-step="proof:-1" disabled={@frames == []}>←</button><button
              type="button"
              data-step="proof:1"
              disabled={@frames == []}
            >→</button><span>{@stage + 1} / {length(@frames)}</span><a
              href="#lean-bridge"
              data-open-inspector
            >Actual Lean source ↗</a>
          </div>
          <p class="provenance-note">
            Source-guided reconstruction. These are explanatory frames, not captured Lean tactic states.
          </p>
        </section>
        <section
          class="lab-panel environment-player"
          id="environment-player"
          data-player="environment"
        >
          <header class="lab-panel-header">
            <div>
              <span class="lab-kicker">04 / Where the model meets reality</span><h2>
                Break an assumption
              </h2>
            </div><span class="type-badge illustrated">Fault sandbox</span>
          </header>
          <div class="assumption-switches">
            <button
              id="fencing-toggle"
              role="switch"
              aria-checked={to_string(@fencing)}
              phx-click="toggle_assumption"
              phx-value-name="fencing"
            ><span class="switch-track"><i /></span><span>Terminal fencing<small>Voided identity stays terminal</small></span></button>
            <button
              id="durability-toggle"
              role="switch"
              aria-checked={to_string(@durable)}
              phx-click="toggle_assumption"
              phx-value-name="durable"
            ><span class="switch-track"><i /></span><span>Durable local record<small>Recovery remembers the reservation</small></span></button>
          </div>
          <div
            class={["exposure-theater", !@environment_frame.covered && "uncovered"]}
            id="exposure-theater"
          >
            <div class="theater-event">
              <span>0{@environment_position + 1}</span><strong>{@environment_frame.label}</strong>
            </div>
            <div class="swimlane">
              <span>Local reservation</span><div class="lane-track">
                <i style={"width:#{@environment_frame.local}%"} />
              </div><b id="sandbox-local">{@environment_frame.local}¢</b>
            </div>
            <div class="swimlane remote">
              <span>Remote exposure</span><div class="lane-track">
                <i style={"width:#{@environment_frame.remote}%"} />
              </div><b id="sandbox-remote">{@environment_frame.remote}¢</b>
            </div>
            <div class="coverage-status" id="sandbox-coverage">
              <span class={if @environment_frame.covered, do: "yes", else: "no"}>{if @environment_frame.covered,
                do: "Covered",
                else: "Uncovered authorization"}</span><small>Processor: {@environment_frame.remote_status}</small>
            </div>
          </div>
          <.form
            for={to_form(%{"position" => @environment_position})}
            id="environment-scrubber"
            phx-change="environment_scrub"
          >
            <label for="environment-position" class="sr-only">Assumption experiment position</label><input
              id="environment-position"
              type="range"
              name="position"
              min="0"
              max="8"
              value={@environment_position}
            />
          </.form>
          <div class="playback">
            <button type="button" data-play="environment" aria-label="Play assumption experiment">▶ Play</button><button
              type="button"
              data-step="environment:-1"
            >←</button><button type="button" data-step="environment:1">→</button><button
              phx-click="environment_end"
              id="show-delayed"
            >Jump to delayed delivery</button>
          </div>
          <p class="provenance-note" id="sandbox-provenance">
            {@environment_frame.provenance}. Faults affect this illustration only.
          </p>
        </section>
      </div>
    </div>
    """
  end

  attr :state, :map, required: true
  attr :title, :string, required: true
  attr :id, :string, required: true

  def account(assigns) do
    assigns =
      assign(assigns,
        ratio: min(1, assigns.state["used_amount"] / max(1, assigns.state["amount_limit"]))
      )

    ~H"""
    <div class="visual-account" id={@id}>
      <span class="account-label">{@title}</span>
      <svg
        viewBox="0 0 240 130"
        role="img"
        aria-label={"#{@state["used_amount"]} cents reserved out of #{@state["amount_limit"]}"}
        data-link-target="capacity"
      >
        <rect x="20" y="16" width="200" height="96" rx="12" class="account-shell" />
        <text x="34" y="42" class="svg-label">RESERVED / LIMIT</text>
        <text x="34" y="70" class="svg-amount">
          {@state["used_amount"]}
          <tspan class="svg-unit">/ {@state["amount_limit"]}¢</tspan>
        </text>
        <rect x="34" y="85" width="172" height="8" rx="4" class="capacity-empty" />
        <rect x="34" y="85" width={172 * @ratio} height="8" rx="4" class="capacity-used" />
      </svg>
      <div class="slot-dots" data-link-target="slots">
        <i
          :for={n <- 1..max(1, min(@state["hold_limit"], 8))}
          class={if n <= @state["used_holds"], do: "occupied", else: ""}
        /><span>{@state["used_holds"]} / {@state["hold_limit"]} slots</span>
      </div>
      <div class="hold-tokens" data-link-target="identity status">
        <button
          :for={entry <- @state["entries"]}
          type="button"
          class={["hold-token", entry["status"] in ~w(voided declined) && "terminal"]}
          data-link-cue="identity status"
          phx-click="binding_key"
          phx-value-key={entry["key"]}
          title={"Identity #{entry["key"]}: #{entry["amount"]} cents, #{entry["status"]}"}
        ><span>#{entry["key"]}</span><b>{entry["amount"]}¢</b><small>{entry["status"]}</small></button>
        <span :if={@state["entries"] == []} class="empty-hold">No remembered holds</span>
      </div>
    </div>
    """
  end

  attr :node, :map, required: true
  attr :label, :string, required: true

  def expression_tree(assigns) do
    assigns = assign(assigns, leaves: frontier(assigns.node))

    ~H"""
    <div class="expression-tree">
      <div class="expression-root">
        <strong>{@label}</strong><span class={result_class(@node)}>{term(@node["value"])}</span>
      </div>
      <div class="expression-branches">
        <div :for={node <- @leaves} class="expression-branch">
          <button
            type="button"
            class={["expression-leaf", result_class(node)]}
            data-link-cue={cue(node["expression"])}
            aria-pressed="false"
          >
            <span class="expression-wire" aria-hidden="true" /><code>{String.replace(
              node["expression"],
              "HoldLedger.",
              ""
            )}</code><span class="leaf-operands">{operands(node)}</span><b>{if node["status"] ==
                                                                                 "not_evaluated",
                                                                               do: "not evaluated",
                                                                               else:
                                                                                 term(node["value"])}</b>
          </button>
          <details
            :for={helper <- Enum.filter(node["children"], &(&1["helper"] != nil))}
            class="expression-expansion"
          >
            <summary>Expand {helper["helper"]}</summary>
            <.expression_tree node={helper} label={helper["helper"]} />
          </details>
        </div>
      </div>
    </div>
    """
  end

  defp law_result(nil, _), do: "Unresolved"

  defp law_result(data, "candidate") do
    case data["law_status"] do
      "catches" -> "Rejects"
      "allows_here" -> "Satisfies here"
      "doesnt_apply" -> "No promise"
      _ -> "Unresolved"
    end
  end

  defp law_result(data, "actual") do
    values = Enum.map(data["explanation"]["bindings"], &get_in(&1, ["actual", "value"]))

    cond do
      false in values -> "Rejects"
      true in values -> "Satisfies here"
      true -> "No promise"
    end
  end

  defp result_class(%{"status" => "not_evaluated"}), do: "skipped"
  defp result_class(%{"value" => true}), do: "passed"
  defp result_class(%{"value" => false}), do: "failed"
  defp result_class(_), do: "observed"

  defp operands(node),
    do:
      node["children"]
      |> Enum.reject(&(&1["helper"] != nil))
      |> Enum.map_join(" → ", &term(&1["value"]))

  defp first_line(code), do: code |> String.split("\n", trim: true) |> List.first()

  defp cue(expression) do
    cond do
      String.contains?(expression, ["amount_limit", "used_amount", "amount <="]) -> "capacity"
      String.contains?(expression, ["hold_limit", "used_holds"]) -> "slots"
      String.contains?(expression, ["status", "exposed", "release"]) -> "status"
      String.contains?(expression, ["key", "lookup", "has_key"]) -> "identity"
      true -> "capacity slots identity status"
    end
  end
end
