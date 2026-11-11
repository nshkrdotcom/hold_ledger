defmodule HoldLedger.Phase4ArchitectureBoundariesTest do
  @moduledoc """
  Research-only negative controls for a NOT AUTHORIZED sets/hash/sharding change.

  These are BEAM observations, not a Lynx proof, ownership protocol, or a
  promise of phash2 stability across toolchain changes. Production routing and
  storage remain single-owner and unchanged.
  """
  use ExUnit.Case, async: true

  @moduletag :phase4_research

  test "version 2 sets de-duplicate keys but cannot replace the ordered ledger" do
    version_2 = :sets.from_list([1, 2, 1, 3], version: 2)
    assert :sets.size(version_2) == 3
    assert :sets.is_element(1, version_2)
    refute :sets.is_element(4, version_2)
    assert Enum.sort(:sets.to_list(version_2)) == [1, 2, 3]

    # Lynx models version 2 only. Do not infer version 1 equivalence from OTP
    # accepting a version 1 option; a set loses the original order and amounts.
    ordered_entries = [{3, 7, :voided}, {1, 2, :reserved}, {2, 5, :declined}]
    assert length(ordered_entries) == :sets.size(version_2)
    assert ordered_entries != :sets.to_list(version_2)
    assert Enum.map(ordered_entries, &elem(&1, 0)) == [3, 1, 2]

    # OTP can handle version 1, but the pinned Lynx model cannot prove that
    # representation. Explicitly reject an invalid version rather than
    # mistaking a version option for a verified behavioral contract.
    version_1 = :sets.from_list([1, 1, 2], version: 1)
    assert :sets.size(version_1) == 2
    assert_raise CaseClauseError, fn -> :sets.new(version: 3) end
  end

  test "phash2 ranges are bounded; deterministic collisions are not identity" do
    assert :erlang.phash2({:hold, 1}, 1) == 0
    assert :erlang.phash2({:hold, 2}, 1) == 0
    assert :erlang.phash2({:hold, 1}, 1) == :erlang.phash2({:hold, 1}, 1)

    for term <- [0, -1, 1, 1.0, :atom, [], {1, 2}, %{a: 2}, <<1, 2>>] do
      assert :erlang.phash2(term) in 0..134_217_727

      for range <- [1, 2, 17, 256, 4_294_967_296] do
        assert :erlang.phash2(term, range) in 0..(range - 1)
      end
    end

    # OTP hashes these, but Lynx's runtime identifiers are opaque; these
    # outputs have deliberately no byte-for-byte portability assertion.
    for opaque <- [self(), make_ref(), fn -> :value end] do
      assert :erlang.phash2(opaque, 17) in 0..16
    end

    for range <- [0, -1, 4_294_967_297] do
      assert_raise ArgumentError, fn -> :erlang.phash2(:test_key, range) end
    end
  end

  test "changing topology can move keys; a bucket cannot serve as durable owner" do
    key = Enum.find(0..256, fn value -> :erlang.phash2(value, 2) == 1 end)
    refute is_nil(key)
    assert :erlang.phash2(key, 2) == 1
    assert :erlang.phash2(key, 1) == 0

    # After restart, the saved owner/placement epoch would need to determine
    # routing; recomputing against a new shard count is insufficient.
    saved = %{key: key, epoch: 1, partitions: 2, owner: 1}

    recalculated_after_restart =
      Task.async(fn -> :erlang.phash2(key, 1) end) |> Task.await()

    assert saved.partitions == 2
    assert recalculated_after_restart == 0
    refute recalculated_after_restart == saved.owner
  end
end
