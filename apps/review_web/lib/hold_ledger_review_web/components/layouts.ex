defmodule HoldLedgerReviewWeb.Layouts do
  use HoldLedgerReviewWeb, :html
  embed_templates "layouts/*"
  attr :flash, :map, required: true
  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <a href="#workspace" class="skip-link">Skip to workspace</a>
    <header class="site-header">
      <span class="brand">HOLD LEDGER <span>/ POLICY REVIEW</span></span><nav aria-label="Help">
        <a
          href="#glossary"
          title="Plain-English dictionary for the words used here"
          phx-click={Phoenix.LiveView.JS.set_attribute({"open", ""}, to: "#glossary")}
        >Glossary</a><span
          class="mode"
          title="This review runs in your local checkout; optional AI requests need your consent"
        >Local review</span>
      </nav>
    </header>
    <main id="workspace" class="workspace">{render_slot(@inner_block)}</main>
    <.glossary />
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
