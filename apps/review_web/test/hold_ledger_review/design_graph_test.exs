defmodule HoldLedgerReview.DesignGraphTest do
  use ExUnit.Case, async: false
  alias HoldLedgerReview.{Adversarial, Anchor, Claims, Config, DesignGraph, Dossier}

  test "all 15 exact policy event rows and the entire 35+14 registered law catalog have source anchors" do
    assert {:ok, graph} = DesignGraph.build()
    nodes = graph["nodes"]
    policy = Enum.filter(nodes, &String.starts_with?(&1["id"], "policy.events."))
    assert length(policy) == 15
    assert Enum.map(policy, & &1["id"]) ==
      Enum.map(1..15, &("policy.events." <> String.pad_leading(to_string(&1), 2, "0")))
    assert Enum.count(nodes, &(&1["kind"] == "law")) == 35
    assert Enum.count(nodes, &(&1["kind"] == "lean")) == 14
    ids = MapSet.new(nodes, & &1["id"])
    assert MapSet.size(ids) == length(nodes)
    sources = Map.new(graph["excerpts"], &{&1["id"], &1})
    assert Enum.all?(nodes, fn n -> Enum.all?(n["source_ids"], &Map.has_key?(sources, &1)) end)
    assert Enum.all?(graph["excerpts"], fn e ->
      {:ok, bytes} = Anchor.read_under(Config.root(), e["path"])
      e["sha256"] == Anchor.sha(bytes) and byte_size(e["text"]) <= 19_500
    end)
    assert Enum.all?(graph["edges"], fn e ->
      e["provenance"] in ~w(source_explicit inferred human_confirmed) and
        MapSet.member?(ids, e["from_id"]) and MapSet.member?(ids, e["to_id"])
    end)
    assert Enum.any?(graph["edges"], &(&1["provenance"] == "inferred"))
    assert Enum.any?(nodes, &(&1["id"] == "boundary.processor"))
    assert :ok = Claims.freshness()
  end

  test "five stable human-owned cards for each of eight synthetic scenarios" do
    {:ok, graph} = DesignGraph.build()
    for seed <- Adversarial.seeds() do
      cards = Dossier.for_seed(seed, graph)
      assert length(cards) == 5
      assert Enum.map(cards, & &1["kind"]) == ~w(reading escape trace silence assumption)
      assert Enum.count(cards, & &1["mandatory"]) == 3
      assert Enum.count(cards, & &1["critical"]) == 1
      assert Enum.all?(cards, &(&1["origin"] == "deterministic"))
      assert Enum.all?(cards, &Enum.member?(~w(reading escape trace silence assumption), &1["kind"]))
      for c <- cards do
        assert Enum.any?(graph["nodes"], &(&1["id"] == c["target_node_id"]))
        assert {:ok, _} = Dossier.implication(c, hd(Dossier.choices(c["kind"])))
      end
    end
    assert Dossier.for_seed("P01", graph) == Dossier.for_seed("P01", graph)
    assert {:error, :invalid_choice} = Dossier.implication(hd(Dossier.for_seed("P01", graph)), "silently_approve")
  end
end
