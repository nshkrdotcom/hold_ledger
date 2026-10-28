defmodule HoldLedgerReviewWeb.LeanComponents do
  @moduledoc false
  use HoldLedgerReviewWeb, :html
  import HoldLedgerReviewWeb.DissectorComponents, only: [source_url: 2]

  attr :reading, :map, required: true

  def assumptions(assigns) do
    ~H"""
    <section class="instrument" id="assumptions">
      <header>
        <span class="section-number">04</span><h2>Scope & assumptions</h2>
      </header>
      <blockquote :if={@reading["policy"]["quote"]} id="policy-quote">
        {@reading["policy"]["quote"]}
      </blockquote>
      <a href={source_url(@reading, "guides/specification.md")} target="_blank" rel="noopener">Governing specification:{@reading[
        "policy"
      ]["line"]} ↗</a>
      <p :if={@reading["omits"]} class="omission" id="omission">{@reading["omits"]}</p>
      <dl class="evidence-status">
        <dt>Focused Lean elaboration</dt><dd id="focused-status">{@reading["focused"]["status"]}</dd><dt>
          Required full gate
        </dt><dd id="formal-status">{@reading["formal"]["status"]}</dd><dt>
          Theorem axiom footprint
        </dt><dd>Read matching export; not inferred from source</dd><dt>Checker configurations</dt><dd>
          Lean default · Lean paranoid · lean4lean · nanoda · con-leche · con-ron
        </dd>
      </dl>
      <h3>Coupled model’s deployment premises</h3><p>
        Processor outcomes, persistent identity and terminal fencing are premises of the coupled exposure model.
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
        Pure hold model; not settlement or physical durability. Source references are not kernel dependency footprints.
      </p>
      <button phx-click="refresh_evidence" class="text-button">Refresh evidence</button>
    </section>
    """
  end
end
