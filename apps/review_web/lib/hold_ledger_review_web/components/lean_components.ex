defmodule HoldLedgerReviewWeb.LeanComponents do
  @moduledoc false
  use HoldLedgerReviewWeb, :html
  import HoldLedgerReviewWeb.DissectorComponents, only: [source_url: 2]

  attr :reading, :map, required: true
  attr :stage, :integer, default: 0
  attr :reference, :map, default: nil

  def bridge(assigns) do
    assigns = assign(assigns, :selected, Enum.at(assigns.reading["proof_steps"], assigns.stage))

    ~H"""
    <section class="instrument" id="lean-bridge">
      <header>
        <span class="section-number">03</span><h2>Lean theorem & proof</h2>
      </header>
      <p class="scope-note">Universal statement · the case above binds its variables once.</p>
      <article :for={declaration <- @reading["declarations"]}>
        <pre
          class="theorem"
          id={"theorem-" <> String.slice(HoldLedgerReview.Anchor.sha(declaration["name"]), 0, 8)}
        >{declaration["header"]}</pre>
        <p>
          <a href={source_url(@reading, declaration["path"])} target="_blank" rel="noopener">{declaration[
            "path"
          ]}:{declaration["line"]} ↗</a>
        </p>
        <p :if={declaration["text"] == ""} class="signal">Declaration missing or ambiguous.</p>
      </article>
      <section :if={@reading["inline_proof"]} class="inline-proof">
        <h3>Law’s Lean proof</h3><pre>{@reading["inline_proof"]["text"]}</pre>
      </section>
      <nav class="proof-stages" id="proof-stages" aria-label="Proof reading steps">
        <button
          :for={{step, index} <- Enum.with_index(@reading["proof_steps"])}
          phx-click="proof_stage"
          phx-value-index={index}
          aria-current={if index == @stage, do: "step", else: "false"}
        >{index + 1}. {step["title"]}</button>
      </nav>
      <section :if={@selected} id="proof-step">
        <h3>{@selected["title"]}</h3><p>{@selected["reason"]}</p><pre>{@selected["code"]}</pre><small>{@selected[
          "path"
        ]}:{@selected["line"]} · source reading, not a live tactic-state replay</small>
      </section>
      <p :if={!@reading["reading_current"]} class="scope-note">
        No reviewed prose for this source version. The actual declaration remains available.
      </p>
      <div class="lemma-links" id="lemma-links">
        <h3>Referenced proof lemmas</h3><button
          :for={reference <- Enum.filter(@reading["references"], &(&1["declarations"] != []))}
          phx-click="lemma"
          phx-value-name={reference["name"]}
          class="text-button"
        >{reference["name"]}</button>
      </div>
      <section :if={@reference} id="lemma-source">
        <h3>{@reference["name"]}</h3><article :for={d <- @reference["declarations"]}>
          <pre>{d["header"]}</pre><a
            href={source_url(@reading, d["path"])}
            target="_blank"
            rel="noopener"
          >{d["path"]}:{d["line"]} ↗</a>
        </article>
      </section>
      <details class="translation">
        <summary>Lynx bridge</summary><div class="translation-path">
          Elixir law → ProofCase requires/ensures helpers → Core Erlang → Lynx → Lean declaration
        </div><p>
          <a href={source_url(@reading, "test/support/proof_case.ex")} target="_blank" rel="noopener">Original contract generator ↗</a>
        </p><p>Focused producer: {@reading["focused"]["status"]}. Full acceptance is separate.</p><ul id="generated-artifacts">
          <li :for={item <- @reading["focused"]["artifacts"] || []}>
            <a
              href={"/claims/#{@reading["slug"]}/generated/#{item["sha256"]}"}
              target="_blank"
              rel="noopener"
            >{Path.basename(item["path"])} ↗</a>
          </li>
        </ul>
      </details>
    </section>
    """
  end

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
