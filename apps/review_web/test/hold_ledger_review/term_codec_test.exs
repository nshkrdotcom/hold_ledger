defmodule HoldLedgerReview.TermCodecTest do
  use ExUnit.Case, async: true
  alias HoldLedger.{Ledger, Spec}
  alias HoldLedgerReview.{Canonical, TermCodec}

  @fixture_dir Path.expand("../fixtures/claims", __DIR__)

  test "the exact native event and effect allowlist round trips" do
    for event <- [{:request, 11, 100}, {:dispatch, 11}, {:timeout, 1}, {:void, 1}] do
      assert {:ok, json} = TermCodec.encode_event(event)
      assert Map.keys(json) |> Enum.sort() == ~w(amount key type)
      assert {:ok, ^event} = TermCodec.decode_event(json)
      assert json["amount"] == if(tuple_size(event) == 2, do: nil, else: elem(event, 2))
    end

    for effect <- [{:authorize, 11, 100}, {:void, 1}] do
      assert {:ok, json} = TermCodec.encode_effect(effect)
      assert Map.keys(json) |> Enum.sort() == ~w(amount key type)
      assert {:ok, ^effect} = TermCodec.decode_effect(json)
    end

    assert {:error, :unsupported_event} =
             TermCodec.encode_event({:processor_result, 1, :approved})

    assert {:error, :unsupported_effect} = TermCodec.encode_effect({:dispatch, 1})
  end

  test "the supplied rejection vectors and extra/wrong-field cases fail closed" do
    vectors = load("codec_roundtrip_vectors.json")

    for %{"json" => json} <- vectors["rejected_event_cases"] do
      assert {:error, :invalid_event} = TermCodec.decode_event(json)
    end

    for %{"json" => json} <- vectors["rejected_effect_cases"] do
      assert {:error, :invalid_effect} = TermCodec.decode_effect(json)
    end

    for json <- [
          %{"type" => "request", "key" => -1, "amount" => 1},
          %{"type" => "request", "key" => 1_000_001, "amount" => 1},
          %{"type" => "request", "key" => 1, "amount" => 1_000_001},
          %{"type" => "request", "key" => 1, "amount" => 1.0},
          %{"type" => "void", "key" => 1},
          %{"type" => "void", "key" => 1, "amount" => nil, "other" => true}
        ] do
      assert {:error, :invalid_event} = TermCodec.decode_event(json)
    end

    assert {:error, :invalid_effect} = TermCodec.decode_effect(%{"type" => "void", "key" => 1})

    assert {:error, :invalid_effect} =
             TermCodec.decode_effect(%{"type" => "void", "key" => 1, "amount" => 2})
  end

  test "complete outputs and independent oracle serialize identically in shape" do
    for id <- 1..8 do
      fixture = load("P#{String.pad_leading(to_string(id), 2, "0")}.json")
      {:ok, before} = TermCodec.decode_state(fixture["before"])
      {:ok, event} = TermCodec.decode_event(fixture["event"])
      {:ok, hypothetical} = TermCodec.decode_output(fixture["output"])
      expected_json = fixture["output"]
      assert {:ok, ^expected_json} = TermCodec.encode_output(hypothetical)

      for output <- [Ledger.step(before, event), Spec.expected_step(before, event)] do
        assert {:ok, json} = TermCodec.encode_output(output)
        assert Map.keys(json) |> Enum.sort() == ~w(after effects result)
        assert {:ok, ^output} = TermCodec.decode_output(json)
        assert {:ok, _digest} = Canonical.output_digest(output)
      end
    end
  end

  test "shape-valid semantic counterfactuals remain decodable" do
    {:ok, output} = TermCodec.decode_output(load("P06.json")["output"])
    refute Spec.valid?(elem(output, 0))
    assert {:ok, _} = TermCodec.encode_output(output)
  end

  test "state/result/effects are bounded and exact" do
    {:ok, state} = TermCodec.decode_state(load("P01.json")["before"])
    {:ok, json} = TermCodec.encode_state(state)
    assert {:error, :invalid_state} = TermCodec.decode_state(Map.put(json, "untrusted", "yes"))

    assert {:error, :invalid_state} =
             TermCodec.decode_state(put_in(json, ["entries", Access.at(0), "status"], "eval"))

    assert {:error, :invalid_state} =
             TermCodec.decode_state(put_in(json, ["entries", Access.at(0), "amount"], -1))

    assert {:error, :invalid_state} =
             TermCodec.decode_state(%{json | "entries" => List.duplicate(hd(json["entries"]), 9)})

    assert {:error, :invalid_output} =
             TermCodec.decode_output(%{
               "after" => json,
               "result" => "voiding",
               "effects" => [],
               "extra" => 1
             })

    assert {:error, :invalid_result} =
             TermCodec.decode_output(%{
               "after" => json,
               "result" => "user_passed",
               "effects" => []
             })

    assert {:error, :invalid_output} =
             TermCodec.decode_output(%{
               "after" => json,
               "result" => "voiding",
               "effects" => List.duplicate(%{"type" => "void", "key" => 1, "amount" => nil}, 9)
             })

    assert {:error, :unsupported_result} = TermCodec.encode_output({state, :user_passed, []})
    assert {:error, :unsupported_state} = TermCodec.encode_state({0, 0, -1, 0, []})
  end

  test "canonicalization rejects generic tuples and atoms rather than reviving old format" do
    assert Canonical.json(%{"b" => 2, "a" => [true, nil]}) == "{\"a\":[true,null],\"b\":2}"
    assert_raise ArgumentError, fn -> Canonical.json({:void, 1}) end
    assert_raise ArgumentError, fn -> Canonical.json(%{atom_key: 1}) end
    assert_raise ArgumentError, fn -> Canonical.json(%{"status" => :reserved}) end
  end

  defp load(name), do: @fixture_dir |> Path.join(name) |> File.read!() |> Jason.decode!()
end
