defmodule HoldLedgerReview.JSONSchemaTest do
  use ExUnit.Case, async: true
  alias HoldLedgerReview.JSONSchema

  test "closed nested responses reject extra fields, wrong types and ambiguous alternatives" do
    schema = %{
      "type" => "object",
      "additionalProperties" => false,
      "required" => ["answer"],
      "properties" => %{
        "answer" => %{"oneOf" => [%{"type" => "integer", "minimum" => 1}, %{"type" => "null"}]}
      }
    }

    assert JSONSchema.structure?(%{"answer" => 1}, schema)
    assert JSONSchema.structure?(%{"answer" => nil}, schema)
    refute JSONSchema.structure?(%{"answer" => 0}, schema)
    refute JSONSchema.structure?(%{"answer" => "1"}, schema)
    refute JSONSchema.structure?(%{"answer" => 1, "approved" => true}, schema)
    refute JSONSchema.structure?(%{}, schema)
    refute JSONSchema.structure?(1, %{"oneOf" => [%{"type" => "number"}, %{"type" => "integer"}]})
  end

  test "array uniqueness and string bounds remain local validation constraints" do
    schema = %{
      "type" => "array",
      "uniqueItems" => true,
      "maxItems" => 2,
      "items" => %{"type" => "string", "minLength" => 1, "maxLength" => 3}
    }

    assert JSONSchema.structure?(["one", "two"], schema)
    refute JSONSchema.structure?(["one", "one"], schema)
    refute JSONSchema.structure?(["long"], schema)
    refute JSONSchema.structure?([""], schema)
  end
end
