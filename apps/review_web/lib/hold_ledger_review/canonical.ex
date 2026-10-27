defmodule HoldLedgerReview.Canonical do
  def json(value),
    do: value |> HoldLedgerReview.TermCodec.encode() |> ordered() |> IO.iodata_to_binary()

  def digest(value), do: value |> json() |> HoldLedgerReview.Anchor.sha()

  defp ordered(m) when is_map(m),
    do: [
      "{",
      m
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map(fn {k, v} -> [Jason.encode!(k), ":", ordered(v)] end)
      |> Enum.intersperse(","),
      "}"
    ]

  defp ordered(l) when is_list(l),
    do: ["[", l |> Enum.map(&ordered/1) |> Enum.intersperse(","), "]"]

  defp ordered(v), do: Jason.encode!(v)
end
