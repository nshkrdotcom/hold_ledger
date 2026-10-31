defmodule HoldLedgerReviewWeb.LeanComponents do
  @moduledoc false
  use HoldLedgerReviewWeb, :html
  import HoldLedgerReviewWeb.DissectorComponents, only: [source_url: 2]
  alias HoldLedgerReviewWeb.ReviewCopy

  attr :reading, :map, required: true

  attr :show_status, :boolean, default: true

  def assumptions(assigns) do
    ~H"""
    <section class="instrument" id="assumptions">
      <header>
        <span class="section-number">Assumptions</span><h2>What this model relies on</h2>
      </header>
      <blockquote :if={@reading["policy"]["quote"]} id="policy-quote">
        {@reading["policy"]["quote"]}
      </blockquote>
      <a href={source_url(@reading, "guides/specification.md")} target="_blank" rel="noopener">Payment policy:{@reading[
        "policy"
      ]["line"]} ↗</a>
      <p :if={@reading["omits"]} class="omission" id="omission">{@reading["omits"]}</p>
      <dl :if={@show_status} class="evidence-status">
        <dt>Focused Lean elaboration</dt><dd id="focused-status">
          {ReviewCopy.evidence_status(@reading["focused"]["status"])}
        </dd><dt>
          Full verification report
        </dt><dd id="formal-status">{ReviewCopy.evidence_status(@reading["formal"]["status"])}</dd><dt>
          Axioms used by this theorem
        </dt><dd>Read the matching proof export.</dd><dt>Checker configurations</dt><dd>
          Lean default · Lean paranoid · lean4lean · nanoda · con-leche · con-ron
        </dd>
      </dl>
      <h3>Processor and storage contracts</h3><p>
        The processor must recognize repeated keys and report truthful outcomes.
        After a confirmed remote cancellation, that key must never authorize again.
        The runtime also relies on durable journal writes. Review these contracts before applying the model to a real system.
      </p>
      <div class="source-links">
        <a
          href={source_url(@reading, "lib/hold_ledger/environment.ex")}
          target="_blank"
          rel="noopener"
        >Environment ↗</a><a
          href={source_url(@reading, "lib/hold_ledger/exposure.ex")}
          target="_blank"
          rel="noopener"
        >Exposure ↗</a><a
          href={source_url(@reading, "guides/processors.md")}
          target="_blank"
          rel="noopener"
        >Processor requirements ↗</a><a
          href={source_url(@reading, "guides/runtime.md")}
          target="_blank"
          rel="noopener"
        >Runtime / storage ↗</a>
      </div>
      <p class="scope-note">
        The model tracks authorization capacity. Real processor behavior and journal durability need separate evidence.
      </p>
      <button phx-click="refresh_evidence" class="text-button">Refresh evidence</button>
    </section>
    """
  end
end
