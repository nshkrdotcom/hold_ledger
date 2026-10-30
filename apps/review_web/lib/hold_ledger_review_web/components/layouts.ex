defmodule HoldLedgerReviewWeb.Layouts do
  use HoldLedgerReviewWeb, :html
  embed_templates "layouts/*"
  attr :flash, :map, required: true
  attr :review_stage, :string, default: nil
  attr :review_claim, :string, default: nil
  attr :review_case, :string, default: nil
  slot :tools
  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <a href="#workspace" class="skip-link">Skip to workspace</a>
    <header class="site-header" id="global-header" data-learning-shell>
      <div class="site-header-main">
        <a href="/" class="brand" aria-label="Hold Ledger, explore">
          <img src="/images/lambda.svg" width="24" height="24" alt="" />
          <span class="brand-name">HOLD LEDGER</span>
          <span class="brand-section">Payment holds, explained</span>
        </a>
        <nav class="global-nav" aria-label="Main navigation" data-global-nav>
          <a href="/" data-nav="/">Explore</a>
          <a href="/lab" data-nav="/lab">Case Lab</a>
          <a href="/atlas" data-nav="/atlas">Claims</a>
        </nav>
        <div class="global-actions">
          <details class="reference-nav" id="reference-nav">
            <summary>Guides</summary>
            <div>
              <a href="/start" data-nav="/start">Follow a payment hold</a>
              <a href="/how-it-fits" data-nav="/how-it-fits">How it fits together</a>
              <a href="/translation" data-nav="/translation">Elixir to Lean with Lynx</a>
              <a href="/examples" data-nav="/examples">Find a deliberate bug</a>
              <a href="/lens/po_a2?mode=explore" data-nav="/lens">Practice a review</a>
              <a href="/system" data-nav="/system">How the system works</a>
              <a href="/guarantees" data-nav="/guarantees">Payment requirements</a>
              <a href="/proofs" data-nav="/proofs">Read a claim</a>
              <a href="/assurance" data-nav="/assurance">Evidence and assumptions</a>
              <a href="/repository" data-nav="/repository">Find the source</a>
              <a href="/glossary" data-nav="/glossary">Glossary</a>
            </div>
          </details>
          <button
            id="edu-help-toggle"
            phx-update="ignore"
            type="button"
            data-edu-help-open
            aria-controls="edu-help-drawer"
            aria-expanded="false"
          >? <span>Help</span></button>
        </div>
      </div>
      <div class="site-tools">{render_slot(@tools)}</div>
    </header>
    <main id="workspace" class="workspace">
      <nav
        :if={@review_claim}
        id="claim-navigation"
        class="claim-navigation"
        aria-label="For this claim"
      >
        <span>For this claim</span>
        <ul>
          <li :for={{stage, label, path} <- claim_links(@review_claim, @review_case)}>
            <a href={path} aria-current={if(@review_stage == stage, do: "page")}>{label}</a>
          </li>
        </ul>
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
        <span>Help with this page</span><button
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
          <p id="edu-help-limit">
            A walkthrough explains the model. Current proof results need a matching report.
          </p>
        </div>
        <section class="edu-control-guide" data-control-guide>
          <h3>Help with controls</h3>
          <p>Choose a control to read what it does. This won't run it.</p>
          <div id="edu-control-help" class="edu-control-help"></div>
        </section>
        <div class="edu-guidance-setting">
          <label for="edu-guidance">Extra explanations</label>
          <select
            id="edu-guidance"
            aria-label="Extra explanations"
            data-edu-guidance
          >
            <option value="guided">Show</option>
            <option value="focused">Hide</option>
          </select>
          <p>Show or hide the short reading notes beside the tools.</p>
        </div>
        <h3>Keep exploring</h3><div class="edu-help-links">
          <a href="/start">Follow a payment hold →</a><a href="/glossary">Look up a term →</a><a href="/assurance">Read the evidence guide →</a>
        </div>
        <p class="edu-shortcut">Press <kbd>?</kbd> to open help when you're not typing in a field.</p>
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
        <span>Explanation</span>
        <button type="button" data-edu-term-close aria-label="Close term guide">×</button>
      </div>
      <div class="edu-help-content">
        <h2 id="edu-term-title"></h2>
        <p data-term-meaning></p>
        <p data-term-detail></p>
        <section data-term-why-section hidden>
          <h3>Why it matters here</h3><p data-term-why></p>
        </section>
        <section data-term-example-section>
          <h3>In this repository</h3><p data-term-example></p>
        </section>
        <section data-term-limit-section hidden>
          <h3>Keep in mind</h3><p data-term-limit></p>
        </section>
        <code data-term-source></code>
        <div data-term-lookups class="edu-term-lookups"></div>
        <div class="term-guide-actions">
          <a data-term-link href="/glossary">Read the glossary entry →</a>
          <button type="button" data-copy-explanation>Copy explanation</button>
        </div>
        <p data-copy-status role="status" aria-live="polite"></p>
      </div>
    </aside>
    <div id="copy-status" class="copy-status" role="status" aria-live="polite"></div>
    <.flash_group flash={@flash} />
    """
  end

  defp claim_links(slug, case_id) do
    case_path = "/claims/" <> slug <> if(case_id, do: "/" <> case_id, else: "")

    links = [
      {"claim", "Read claim", "/atlas/" <> slug},
      {"challenge", "Case Lab", case_path}
    ]

    if slug in ~w(po_a2 po_exposure_retain),
      do: links ++ [{"practice", "Guided practice", "/lens/" <> slug}],
      else: links
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
