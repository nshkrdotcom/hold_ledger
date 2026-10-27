defmodule HoldLedgerReview.Explainer.Validator do
  @moduledoc "Shape and citation validation does not establish semantic truth."
  def schema(ids) do
    item = %{
      type: "object",
      additionalProperties: false,
      required: ["text", "source_ids"],
      properties: %{
        text: %{type: "string", minLength: 1, maxLength: 500},
        source_ids: %{
          type: "array",
          minItems: 1,
          maxItems: 5,
          items: %{type: "string", enum: ids}
        }
      }
    }

    %{
      type: "object",
      additionalProperties: false,
      required: ["items"],
      properties: %{items: %{type: "array", minItems: 1, maxItems: 8, items: item}}
    }
  end

  def validate(data, packet) when is_binary(data) and byte_size(data) <= 16_000 do
    with {:ok, decoded} <- Jason.decode(data), do: validate(decoded, packet)
  end

  def validate(%{"items" => items} = data, packet)
      when map_size(data) == 1 and is_list(items) and length(items) in 1..8 do
    ids = Map.keys(packet.anchors)

    valid =
      Enum.all?(items, fn
        %{"text" => text, "source_ids" => sources} = item
        when map_size(item) == 2 and is_binary(text) and is_list(sources) ->
          String.valid?(text) and byte_size(text) in 1..500 and length(sources) in 1..5 and
            Enum.all?(sources, &(&1 in ids))

        _ ->
          false
      end)

    if valid, do: {:ok, items}, else: {:error, :invalid_explanation}
  end

  def validate(_, _), do: {:error, :invalid_explanation}
end
