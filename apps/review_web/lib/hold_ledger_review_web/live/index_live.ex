defmodule HoldLedgerReviewWeb.IndexLive do
  use HoldLedgerReviewWeb, :live_view

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <h1>Hold Ledger / Review Studio</h1>
      <p>Investigate the meaning and limits of a formal claim.</p>
      <.link navigate={~p"/review/void_pending"}>Pending void</.link>
    </Layouts.app>
    """
  end
end
