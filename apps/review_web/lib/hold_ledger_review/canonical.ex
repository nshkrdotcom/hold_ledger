defmodule HoldLedgerReview.Canonical do
  @moduledoc """
  Stable canonical JSON for already typed JSON objects. Native terms must first
  pass the appropriate `TermCodec.encode_*` function; tuples and arbitrary
  atoms cannot be encoded through a generic fallback.
  """
  alias HoldLedgerReview.{Anchor, TermCodec}

  def json(value), do: value |> ordered() |> IO.iodata_to_binary()
  def digest(value), do: value |> json() |> Anchor.sha()

  def output_digest(output) do
    with {:ok, encoded} <- TermCodec.encode_output(output), do: {:ok, digest(encoded)}
  end

  defp ordered(m) when is_map(m) do
    if Enum.all?(Map.keys(m), &is_binary/1) do
      [
        "{",
        m
        |> Enum.sort_by(&elem(&1, 0))
        |> Enum.map(fn {k, v} -> [Jason.encode!(k), ":", ordered(v)] end)
        |> Enum.intersperse(","),
        "}"
      ]
    else
      raise ArgumentError, "canonical JSON requires string keys"
    end
  end

  defp ordered(l) when is_list(l),
    do: ["[", l |> Enum.map(&ordered/1) |> Enum.intersperse(","), "]"]

  defp ordered(v) when is_binary(v) or is_boolean(v) or is_nil(v) or is_integer(v),
    do: Jason.encode!(v)

  defp ordered(_), do: raise(ArgumentError, "unsupported canonical JSON term")
end
