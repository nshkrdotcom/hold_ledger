defmodule HoldLedgerReviewWeb.Layouts do
  use HoldLedgerReviewWeb, :html
  embed_templates "layouts/*"
  attr :flash, :map, required: true
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
          <span class="brand-section">/ EXPLORE</span>
        </a>
        <nav class="global-nav" aria-label="Main navigation" data-global-nav>
          <a href="/" data-nav="/">Overview</a>
          <a href="/start" data-nav="/start">Learn the story</a>
          <a href="/system" data-nav="/system">System</a>
          <a href="/atlas" data-nav="/atlas">49 claims</a>
          <a href="/proofs" data-nav="/proofs">Proofs</a>
          <a href="/assurance" data-nav="/assurance">Evidence</a>
          <a href="/lab" data-nav="/lab">Case Lab</a>
          <a href="/lens/po_a2" data-nav="/lens">Claim Lens</a>
        </nav>
        <div class="global-actions">
          <label for="edu-guidance" class="edu-guidance-label">EXPLAIN</label>
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
            data-edu-hint="Open the page guide, keyboard and touch accessible."
          >? <span>Help</span></button>
        </div>
      </div>
      <div class="site-tools">{render_slot(@tools)}</div>
    </header>
    <main id="workspace" class="workspace">{render_slot(@inner_block)}</main>
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
        <span>HOLD LEDGER / PAGE GUIDE</span><button
          type="button"
          data-edu-help-close
          aria-label="Close page guide"
        >×</button>
      </div>
      <div class="edu-help-content">
        <h2 id="edu-help-title">What am I looking at?</h2><p id="edu-help-description">
          This companion helps connect policy, source code, claims, and evidence.
        </p><div class="edu-help-callout">
          <strong>Evidence boundary</strong><p>
            One pointwise case and a source-reading link are not a universal formal receipt.
          </p>
        </div><h3>Keep exploring</h3><div class="edu-help-links">
          <a href="/start">The payment story →</a><a href="/glossary">Plain-language glossary →</a><a href="/assurance">Evidence and limitations →</a>
        </div>
      </div>
    </aside>
    <div id="edu-tooltip" phx-update="ignore" class="edu-tooltip" role="tooltip" hidden>
      <strong data-tooltip-title></strong><p data-tooltip-short></p><p data-tooltip-detail></p><a
        data-tooltip-link
        href="/glossary"
      >More context →</a>
    </div>
    <.flash_group flash={@flash} />
    """
  end

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
