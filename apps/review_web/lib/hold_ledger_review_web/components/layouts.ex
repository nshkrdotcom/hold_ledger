defmodule HoldLedgerReviewWeb.Layouts do
  use HoldLedgerReviewWeb, :html
  embed_templates "layouts/*"
  attr :flash, :map, required: true
  attr :review_stage, :string, default: nil
  attr :review_claim, :string, default: "po_a2"
  slot :tools
  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <a href="#workspace" class="skip-link">Skip to workspace</a>
    <header class="site-header" id="global-header">
      <div class="site-header-main">
        <a href="/" class="brand" aria-label="Hold Ledger, overview">
          <img src="/images/lambda.svg" width="24" height="24" alt="" />
          <span class="brand-name">HOLD LEDGER</span>
          <span class="brand-section">Payment holds, explained</span>
        </a>
        <nav class="global-nav" aria-label="Main navigation" data-global-nav>
          <a href="/" data-nav="/">Overview</a>
          <a href="/start" data-nav="/start">Learn</a>
          <a href="/atlas" data-nav="/atlas">Claims</a>
          <a href="/lab" data-nav="/lab">Case Lab</a>
          <a href="/lens/po_a2" data-nav="/lens">Practice a review</a>
          <details class="reference-nav" id="reference-nav">
            <summary>Reference</summary>
            <div>
              <a href="/system" data-nav="/system">How the system works</a>
              <a href="/guarantees" data-nav="/guarantees">Payment requirements</a>
              <a href="/proofs" data-nav="/proofs">Read a claim</a>
              <a href="/assurance" data-nav="/assurance">Evidence and assumptions</a>
              <a href="/repository" data-nav="/repository">Find the source</a>
              <a href="/glossary" data-nav="/glossary">Glossary</a>
            </div>
          </details>
        </nav>
        <div class="global-actions">
          <label for="edu-guidance" class="edu-guidance-label">Hints</label>
          <select
            id="edu-guidance"
            phx-update="ignore"
            aria-label="Explanation density"
            data-edu-guidance
          >
            <option value="guided">Guided</option>
            <option value="focused">Focused</option>
          </select>
          <button
            id="edu-help-toggle"
            phx-update="ignore"
            type="button"
            data-edu-help-open
            aria-controls="edu-help-drawer"
            aria-expanded="false"
          >? <span>Page guide</span></button>
        </div>
      </div>
      <div class="site-tools">{render_slot(@tools)}</div>
    </header>
    <main id="workspace" class="workspace">
      <nav id="review-steps" class="review-steps" aria-label="Review steps">
        <span>Review a claim</span>
        <ol>
          <li :for={{stage, label, path} <- review_steps(@review_claim)}>
            <a href={path} aria-current={if(@review_stage == stage, do: "step")}>{label}</a>
          </li>
        </ol>
      </nav>
      {render_slot(@inner_block)}
    </main>
    <aside
      id="edu-help-drawer"
      phx-update="ignore"
      class="edu-help-drawer"
      hidden
      role="dialog"
      aria-label="Explain this screen"
      aria-modal="false"
      tabindex="-1"
    >
      <div class="edu-help-head">
        <span>Page guide</span><button
          type="button"
          data-edu-help-close
          aria-label="Close page guide"
        >×</button>
      </div>
      <div class="edu-help-content">
        <p class="help-label">Your question here</p>
        <h2 id="edu-help-title">How does a payment hold work?</h2>
        <h3>What you can do</h3>
        <p id="edu-help-description">Follow a request, then read the claims that describe it.</p>
        <div class="edu-help-callout">
          <strong>What this can't tell you</strong>
          <p id="edu-help-limit">A walkthrough explains the model. Current proof results need a matching report.</p>
        </div><h3>Keep exploring</h3><div class="edu-help-links">
          <a href="/start">Follow a payment hold →</a><a href="/glossary">Look up a term →</a><a href="/assurance">Read the evidence guide →</a>
        </div>
      </div>
    </aside>
    <div id="edu-tooltip" phx-update="ignore" class="edu-tooltip" role="tooltip" hidden>
      <strong data-tooltip-title></strong><p data-tooltip-short></p>
    </div>
    <aside
      id="edu-term-dialog"
      phx-update="ignore"
      class="edu-term-dialog"
      role="dialog"
      aria-modal="false"
      aria-labelledby="edu-term-title"
      hidden
      tabindex="-1"
    >
      <div class="edu-help-head">
        <span>Term guide</span>
        <button type="button" data-edu-term-close aria-label="Close term guide">×</button>
      </div>
      <div class="edu-help-content">
        <h2 id="edu-term-title"></h2>
        <p data-term-meaning></p>
        <p data-term-detail></p>
        <h3>In this repository</h3>
        <p data-term-example></p>
        <code data-term-source></code>
        <div class="term-guide-actions">
          <a data-term-link href="/glossary">Read the glossary entry →</a>
          <button type="button" data-copy-explanation>Copy explanation</button>
        </div>
        <p data-copy-status role="status" aria-live="polite"></p>
      </div>
    </aside>
    <div id="copy-status" class="copy-status" role="status" aria-live="polite">
    </div>
    <.flash_group flash={@flash} />
    """
  end

  defp review_steps(slug) do
    [
      {"policy", "Policy", "/guarantees"},
      {"claim", "Claim", "/atlas/" <> slug},
      {"challenge", "Challenge", "/claims/" <> slug},
      {"evidence", "Evidence", "/assurance"},
      {"assumptions", "Assumptions", "/assurance#model-boundary"},
      {"decision", "Decision", decision_path(slug)}
    ]
  end

  defp decision_path(slug) when slug in ~w(po_a2 po_exposure_retain), do: "/lens/" <> slug
  defp decision_path(slug), do: "/claims/" <> slug <> "#nearby-observation"

  attr :flash, :map, required: true

  def flash_group(assigns) do
    ~H"""
    <aside id="flash-group" aria-live="polite">
      <p :if={Phoenix.Flash.get(@flash, :error)} role="alert">{Phoenix.Flash.get(@flash, :error)}</p>
      <details :if={Phoenix.Flash.get(@flash, :error_detail)}>
        <summary>Technical details</summary><code>{Phoenix.Flash.get(@flash, :error_detail)}</code>
      </details>
      <p :if={Phoenix.Flash.get(@flash, :info)} role="status">{Phoenix.Flash.get(@flash, :info)}</p>
    </aside>
    """
  end
end
