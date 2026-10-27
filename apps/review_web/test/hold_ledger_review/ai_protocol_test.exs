defmodule HoldLedgerReview.AIProtocolTest do
  use ExUnit.Case, async: false
  alias HoldLedgerReview.{AI, AIPacket, AIProtocol, Canonical, ReviewStore}

  setup do
    dir = Path.join(System.tmp_dir!(), "hold-ledger-c-protocol-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, store} = start_supervised({ReviewStore, name: nil, dir: dir})
    {:ok, doc, witness} = ReviewStore.create("P01", store)
    card = Enum.find(doc["core_cards"], &(&1["kind"] == "escape"))
    {:ok, packet} = AIPacket.build(doc, "deck", card["id"])
    {:ok, store: store, review: doc, witness: witness, card: card, packet: packet}
  end

  defp proposal(ctx) do
    %{
      "proposal_id" => "proposal.source-review",
      "kind" => "silence",
      "target_node_id" => ctx.target_node_id,
      "question" => "Which remote capacity observation could falsify the selected policy boundary?",
      "selection_reason" => "An external premise may differ from the pure evaluator contract.",
      "source_ids" => [hd(ctx.source_ids)],
      "probe_ids" => []
    }
  end

  defp deck(ctx) do
    %{
      "request_kind" => "deck",
      "target_node_id" => ctx.target_node_id,
      "intent_hypotheses" => [],
      "readings" => [],
      "card_suggestions" => [proposal(ctx)],
      "uncertainties" => []
    }
  end

  test "a single-event seed still produces two unlabeled distinct source-evaluated probes", %{store: store} do
    {:ok, doc, _} = ReviewStore.create("P04", store)
    card = hd(doc["core_cards"])
    assert {:ok, packet} = AIPacket.build(doc, "deck", card["id"])
    data = Jason.decode!(packet.user)
    assert length(data["known_probes"]) >= 2
    assert length(Enum.uniq_by(data["known_probes"], & &1["probe_id"])) ==
             length(data["known_probes"])
    refute packet.user =~ ~r/"actual_status"|"prediction_matches"|"seed_id"|"P04"/
  end

  test "source-only discovery hides fixture names, matrix labels and reviewer state", %{packet: packet} do
    assert packet.kind == "deck"
    assert byte_size(packet.user) < 150_000
    refute packet.user =~ ~r/"seed_id"|"human_answer"|"answers"|"mutant_targets"|"expected_pointwise"/
    refute packet.user =~ ~r/"P0[1-8]"/
    refute packet.user =~ ~r/"actual_status"|"prediction_matches"|"prediction_conflicts"/
    assert packet.input_digest == Canonical.digest(%{"system" => packet.system, "user" => packet.user})
    assert is_list(packet.context.source_ids) and packet.context.source_ids != []
  end

  test "nested strict schema rejects unauthorized status, extra keys, unknown IDs and oversized fields", %{
    packet: packet
  } do
    ctx = packet.context
    correct = deck(ctx)
    assert {:ok, out} = AIProtocol.validate("deck", correct, ctx)
    assert length(out["suggested_cards"]) == 1
    assert {:error, :invalid_model_output} = AIProtocol.validate("deck", Map.put(correct, "approved", true), ctx)
    assert {:error, :unknown_model_reference} =
             AIProtocol.validate("deck", put_in(correct, ["card_suggestions", Access.at(0), "source_ids"], ["made.up.source"]), ctx)

    assert {:error, :invalid_model_output} =
             AIProtocol.validate("deck", put_in(correct, ["card_suggestions", Access.at(0), "question"], String.duplicate("x", 601)), ctx)

    assert {:error, :invalid_model_output} =
             AIProtocol.validate("deck", put_in(correct, ["card_suggestions", Access.at(0), "kind"], "human_approval"), ctx)
  end

  test "prediction contradictions are server-computed and never treated as certified prose", %{packet: packet} do
    ctx = packet.context
    {probe_id, probe} = Enum.find(ctx.probes, fn {_id, p} -> p["evaluation"]["law_rows"] != [] end)
    row = hd(probe["evaluation"]["law_rows"])
    # Two predictions across permitted opaque probes; neither expected label is sent.
    ids = Map.keys(ctx.probes) |> Enum.take(2)
    assert length(ids) == 2

    reading = %{
      "claim_slug" => row["slug"],
      "summary" => "This source claim applies to bounded candidate output.",
      "not_claimed" => "This is not a remote processor attestation.",
      "source_ids" => [hd(ctx.source_ids)],
      "predictions" => Enum.map(ids, fn id ->
        %{"probe_id" => id, "predicted_status" => "catches", "explanation" => "A proposed prediction, subject to a server check."}
      end)
    }

    result = deck(ctx) |> Map.put("readings", [reading])
    assert {:ok, checked} = AIProtocol.validate("deck", result, ctx)
    statuses = checked["reading_checks"] |> hd() |> Map.fetch!("predictions")
    assert Enum.all?(statuses, &(&1["verification"] in ~w(prediction_matches prediction_conflicts cannot_evaluate)))
    assert Enum.all?(statuses, &is_map(&1["computed_example"]))
    assert Enum.any?(statuses, &(&1["probe_id"] == probe_id)) or is_binary(probe_id)
  end

  test "stable AI card ID and dedup cannot overwrite an accepted card", %{packet: packet} do
    ctx = packet.context
    assert {:ok, first} = AIProtocol.validate("deck", deck(ctx), ctx)
    [card] = first["suggested_cards"]
    assert String.starts_with?(card["id"], "ai.")
    assert card["origin"] == "ai_proposed" and card["mandatory"] == false

    second_ctx = %{ctx | existing_cards: ctx.existing_cards ++ [card]}
    assert {:ok, repeated} = AIProtocol.validate("deck", deck(ctx), second_ctx)
    assert repeated["suggested_cards"] == [] and repeated["deduplicated_count"] == 1
  end

  test "challenge requires canonical exact witness and never pins automatically", %{
    review: doc, store: store, card: card, witness: witness
  } do
    {:ok, pkt} = AIPacket.build(doc, "challenge", card["id"], witness)
    sample = %{
      "request_kind" => "challenge", "target_card_id" => card["id"],
      "witness" => witness, "selection_reason" => "Explore a different claimed result.",
      "source_ids" => [hd(pkt.context.source_ids)]
    }

    assert {:ok, checked} = AIProtocol.validate("challenge", sample, pkt.context)
    assert is_map(checked["evaluation"])
    assert {:error, :invalid_model_output} =
             AIProtocol.validate("challenge", put_in(sample, ["witness", "event", "type"], "exec"), pkt.context)
    assert {:error, :invalid_model_output} =
             AIProtocol.validate("challenge", put_in(sample, ["witness", "before", "entries"], List.duplicate(%{"key" => 1, "amount" => 1, "status" => "reserved"}, 9)), pkt.context)
    assert {:error, :invalid_model_output} =
             AIProtocol.validate("challenge", put_in(sample, ["witness", "output", "proof_approved"], true), pkt.context)
    assert {:ok, ^doc} = ReviewStore.get(doc["id"], store)
  end

  test "follow-up is bound to an actual answer and distinguishes the card question", %{
    review: doc, store: store, card: card
  } do
    {:ok, %{review: answered}} = ReviewStore.answer_card(doc["id"], %{
      "request_id" => Base.url_encode64(:crypto.strong_rand_bytes(18), padding: false),
      "expected_human_revision" => 0,
      "card_id" => Enum.find(doc["core_cards"], &(&1["kind"] == "reading"))["id"],
      "choice" => "inaccurate", "reason" => "Evidence contradicts my intended guarantee",
      "evidence_ids" => card["source_ids"], "revealed_before_answer" => false
    }, store)
    reading = Enum.find(answered["core_cards"], &(&1["kind"] == "reading"))
    {:ok, pkt} = AIPacket.build(answered, "followup", reading["id"])
    assert pkt.user =~ "Evidence contradicts my intended guarantee"
    reply = %{
      "request_kind" => "followup", "card_id" => reading["id"],
      "question" => "Which source-backed counterexample changes that reading?",
      "possible_intent_revision" => nil, "explanation" => "We need a stronger premise.",
      "source_ids" => [hd(pkt.context.source_ids)], "uncertainty" => "External processor state unknown"
    }
    assert {:ok, %{"followup" => ^reply}} = AIProtocol.validate("followup", reply, pkt.context)
    assert {:error, :invalid_followup} =
             AIProtocol.validate("followup", %{reply | "question" => reading["question"]}, pkt.context)
  end

  test "opt-in refused before Inference, and unknown capability refuses dispatch", %{packet: packet} do
    assert {:error, :consent_required} = AI.run(packet, false)
    assert {:error, :ai_unavailable} = AI.run(packet, true, capability_check: fn _ -> false end)
  end
end
