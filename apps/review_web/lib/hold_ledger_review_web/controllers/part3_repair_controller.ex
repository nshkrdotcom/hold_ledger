defmodule HoldLedgerReviewWeb.Part3RepairController do
  use HoldLedgerReviewWeb, :controller
  alias HoldLedgerReview.{Part3RepairPacket, Part3Store}

  # Explicit local GET/download only. No revision write, provider dispatch or
  # implicit consent is performed by exporting this fixed-scope data packet.
  def export(conn, %{"id" => id, "evidence_id" => evidence_id, "format" => format})
      when format in ~w(json md) do
    with {:ok, package, :ok} <- Part3Store.get(id),
         {:ok, packet} <- Part3RepairPacket.build(package, evidence_id) do
      {bytes, type} =
        case format do
          "json" -> {Part3RepairPacket.json(packet), "application/json"}
          "md" -> {Part3RepairPacket.markdown(packet), "text/markdown; charset=utf-8"}
        end

      send_download(conn, {:binary, bytes},
        filename: "hold-ledger-repair-#{evidence_id}.#{format}",
        content_type: type
      )
    else
      _ -> send_resp(conn, 409, "Current-source repair export refused; no permission to send")
    end
  end
end
