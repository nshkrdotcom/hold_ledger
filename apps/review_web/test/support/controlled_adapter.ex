defmodule HoldLedgerReview.TestSupport.ControlledAdapter do
  @moduledoc """
  Deterministic inference test boundary. It captures the actual Inference.Request
  with declared JSON Schema and returns an object or an error on explicit signal.
  It is not installed as the production adapter and never contacts a provider.
  """

  def capable?(_client), do: true
  def unavailable?(_client), do: false

  def complete(_client, request) do
    send(self_controller(), {:controlled_request, self(), request})

    receive do
      {:controlled_reply, {:ok, payload}} -> {:ok, %{object: payload, tool_calls: []}}
      {:controlled_reply, {:error, error}} -> {:error, error}
    after
      5_000 -> {:error, :controlled_timeout}
    end
  end

  defp self_controller do
    :persistent_term.get({__MODULE__, :controller})
  end

  def set_controller(pid), do: :persistent_term.put({__MODULE__, :controller}, pid)
  def clear_controller, do: :persistent_term.erase({__MODULE__, :controller})
end
