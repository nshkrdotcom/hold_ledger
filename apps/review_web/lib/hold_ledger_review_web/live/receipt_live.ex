defmodule HoldLedgerReviewWeb.ReceiptLive do
  use HoldLedgerReviewWeb, :live_view
  alias HoldLedgerReview.{Receipts, ProofEvidence, Config}

  def mount(%{"id" => id}, _, socket) do
    case Receipts.read(id) do
      {:ok, r} ->
        stale =
          Enum.any?(r["source_sha256"], fn {p, h} ->
            ProofEvidence.digest_file(Config.root(), p) != h
          end)

        {:ok, assign(socket, receipt: r, stale?: stale, error: nil)}

      _ ->
        {:ok, assign(socket, receipt: nil, stale?: false, error: "Receipt not found")}
    end
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <h1>Human review receipt</h1><p :if={@error} role="alert">{@error}</p>
      <%= if @receipt do %>
        <p>This immutable record is a human judgment, not a proof certificate.</p>
        <p :if={@stale?} id="receipt-stale" role="status">
          Sources have changed since this review. The original receipt remains unchanged.
        </p>
        <dl>
          <dt>Case</dt><dd>{@receipt["case_id"]}</dd><dt>Decision</dt><dd id="receipt-decision">
            {@receipt["decision"]}
          </dd><dt>Formal evidence</dt><dd>{@receipt["actual_proof_status"]}</dd><dt>Rationale</dt><dd>
            {@receipt["rationale"]}
          </dd><dt>Packet</dt><dd class="digest">{@receipt["packet_sha256"]}</dd>
        </dl>
        <.link id="export-receipt" href={~p"/review/receipts/#{@receipt["id"]}/export"}>Export Markdown</.link>
      <% end %>
    </Layouts.app>
    """
  end
end
