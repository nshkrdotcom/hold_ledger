defmodule HoldLedgerReviewWeb.ArchiveLive do
  @moduledoc "Read-only access to original review records. No schema migration or implicit re-execution."
  use HoldLedgerReviewWeb, :live_view
  alias HoldLedgerReview.{Part3Store, ReviewStore}

  @impl true
  def mount(params, _session, socket) do
    id = params["id"]

    record =
      case socket.assigns.live_action do
        :change ->
          case Part3Store.get(id) do
            {:ok, p, _status} -> p
            _ -> nil
          end

        :review ->
          case ReviewStore.get(id) do
            {:ok, doc} -> doc
            _ -> nil
          end
      end

    {:ok, assign(socket, record: record, page_title: "Archived review")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <h1>Archived review</h1>
      <p>
        This record keeps its original source identity. Start a new trace to explore the current checkout.
      </p>
      <.link navigate={~p"/"}>Open explorer</.link>
      <div :if={@record} id="archived-record">
        <p>Read only · <code>{@record["id"]}</code></p>
        <a :if={@live_action == :review} href={~p"/workbench/#{@record["id"]}/export.json"}>Export original review</a>
        <pre>{Jason.encode!(@record, pretty: true)}</pre>
      </div>
      <p :if={!@record} role="alert">The original record is unavailable.</p>
    </Layouts.app>
    """
  end
end
