defmodule HoldLedgerReviewWeb.Layouts do
  use HoldLedgerReviewWeb, :html
  embed_templates "layouts/*"
  attr :flash, :map, required: true
  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <a href="#workspace" class="skip-link">Skip to workspace</a>
    <header class="site-header">
      <span class="brand">HOLD LEDGER <span>/ CLAIM WORKBENCH</span></span><span class="mode">Local development</span>
    </header>
    <main id="workspace" class="workspace">{render_slot(@inner_block)}</main>
    <.flash_group flash={@flash} />
    """
  end

  attr :flash, :map, required: true

  def flash_group(assigns) do
    ~H"""
    <aside id="flash-group" aria-live="polite">
      <p :if={Phoenix.Flash.get(@flash, :error)} role="alert">{Phoenix.Flash.get(@flash, :error)}</p>
      <p :if={Phoenix.Flash.get(@flash, :info)} role="status">{Phoenix.Flash.get(@flash, :info)}</p>
    </aside>
    """
  end
end
