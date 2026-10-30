defmodule HoldLedgerReview.JSONSchema do
  @moduledoc "Validates the closed JSON Schema subset used by comparison model responses."
  @doc "Check JSON Schema's closed subset used by the shipped contracts, including nested oneOf."
  def structure?(value, schema) when is_map(schema) do
    alternatives?(value, Map.get(schema, "oneOf"), :one) and
      alternatives?(value, Map.get(schema, "anyOf"), :any) and
      scalar_rules?(value, schema) and string_rules?(value, schema) and
      number_rules?(value, schema) and object_rules?(value, schema) and
      array_rules?(value, schema)
  end

  def structure?(_, _), do: false

  defp alternatives?(_value, nil, _mode), do: true

  defp alternatives?(value, schemas, :one),
    do: Enum.count(schemas, &structure?(value, &1)) == 1

  defp alternatives?(value, schemas, :any),
    do: Enum.any?(schemas, &structure?(value, &1))

  defp scalar_rules?(value, schema) do
    type?(value, Map.get(schema, "type")) and
      (not Map.has_key?(schema, "const") or value == schema["const"]) and
      (not Map.has_key?(schema, "enum") or value in schema["enum"])
  end

  defp type?(_value, nil), do: true
  defp type?(v, types) when is_list(types), do: Enum.any?(types, &type?(v, &1))
  defp type?(v, "object"), do: is_map(v) and not is_struct(v)
  defp type?(v, "array"), do: is_list(v)
  defp type?(v, "string"), do: is_binary(v)
  defp type?(v, "integer"), do: is_integer(v)
  defp type?(v, "number"), do: is_number(v)
  defp type?(v, "boolean"), do: is_boolean(v)
  defp type?(v, "null"), do: is_nil(v)
  defp type?(_, _), do: false

  defp string_rules?(v, s) when is_binary(v) do
    String.valid?(v) and
      (not Map.has_key?(s, "minLength") or String.length(v) >= s["minLength"]) and
      (not Map.has_key?(s, "maxLength") or String.length(v) <= s["maxLength"]) and
      byte_size(v) <= 2_400
  end

  defp string_rules?(_, _), do: true

  defp number_rules?(v, s) when is_number(v) do
    (not Map.has_key?(s, "minimum") or v >= s["minimum"]) and
      (not Map.has_key?(s, "maximum") or v <= s["maximum"])
  end

  defp number_rules?(_, _), do: true

  defp object_rules?(v, s) when is_map(v) do
    fields = Map.get(s, "properties", %{})
    required = Map.get(s, "required", [])

    Enum.all?(Map.keys(v), &is_binary/1) and
      Enum.all?(required, &Map.has_key?(v, &1)) and
      (Map.get(s, "additionalProperties") != false or
         Enum.all?(Map.keys(v), &Map.has_key?(fields, &1))) and
      Enum.all?(v, fn {k, x} ->
        not Map.has_key?(fields, k) or structure?(x, fields[k])
      end)
  end

  defp object_rules?(_, _), do: true

  defp array_rules?(v, s) when is_list(v) do
    (not Map.has_key?(s, "minItems") or length(v) >= s["minItems"]) and
      (not Map.has_key?(s, "maxItems") or length(v) <= s["maxItems"]) and
      (Map.get(s, "uniqueItems") != true or length(Enum.uniq(v)) == length(v)) and
      (not Map.has_key?(s, "items") or Enum.all?(v, &structure?(&1, s["items"])))
  end

  defp array_rules?(_, _), do: true
end
