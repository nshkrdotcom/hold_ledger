defmodule HoldLedgerReviewWeb.ReviewLive do
  use HoldLedgerReviewWeb, :live_view
  def mount(%{"case_id" => id}, _session, socket), do: {:ok, assign(socket, :case_id, id)}

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <h1>Review: {@case_id}</h1>
      <p id="empty-state">Practice workspace. Evidence packet not loaded.</p>
    </Layouts.app>
    """
  end
end
