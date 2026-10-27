defmodule HoldLedgerReview.ControlledAdapter do
  @moduledoc "Blocks mock inference requests so tests can exercise cancellation and timeouts."
  @behaviour Inference.Adapter
  def provider_kind, do: :model_endpoint

  def complete(client, _request) do
    send(client.adapter_opts[:owner], {:adapter_waiting, self()})

    receive do
      {:reply, data} -> {:ok, Inference.Response.new(object: data)}
    end
  end
end
