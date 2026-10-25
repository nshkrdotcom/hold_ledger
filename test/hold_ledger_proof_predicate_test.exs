defmodule HoldLedger.ProofPredicateTest do
  use ExUnit.Case, async: true
  alias HoldLedger.{Ledger, Spec}

  test "L1: lookup of holding and terminal keys agrees with independent oracle" do
    entries = [{11, 300, :voided}, {12, 700, :sent}]
    assert Spec.proper_entries?(entries)
    assert Spec.unique_keys?(entries)

    for key <- [11, 12, 13] do
      assert Ledger.find(entries, key) == Spec.lookup(entries, key)
    end
  end

  test "L2: set_status keeps every key and original amount" do
    entries = [{11, 300, :sent}, {12, 400, :unknown}, {13, 100, :voided}]
    state = {1000, 3, 700, 2, entries}
    assert Spec.valid?(state)
    next = {1000, 3, 700, 2, Ledger.set_status(entries, 12, :authorized)}
    assert Spec.identity_preserved?(state, next)
    assert Spec.lookup(elem(next, 4), 12) == {:ok, {12, 400, :authorized}}
  end

  test "L3: delta for moving statuses matches independent counted contribution" do
    entries = [{11, 300, :sent}, {12, 200, :voided}]
    release = Ledger.set_status(entries, 11, :declined)
    activate = Ledger.set_status(entries, 12, :reserved)
    assert {Spec.hold_amount(entries), Spec.hold_count(entries)} == {300, 1}
    assert {Spec.hold_amount(release), Spec.hold_count(release)} == {0, 0}
    assert {Spec.hold_amount(activate), Spec.hold_count(activate)} == {500, 2}
  end

  test "L4: replacement preserves entry shape and uniqueness" do
    entries = [{11, 300, :reserved}, {12, 200, :voided}]

    for status <- [:reserved, :sent, :unknown, :authorized, :declined, :voided] do
      changed = Ledger.set_status(entries, 11, status)
      assert Spec.proper_entries?(changed)
      assert Spec.unique_keys?(changed)
    end
  end

  test "L5: fresh positive entry adds one slot and the original amount" do
    entries = [{11, 300, :declined}, {12, 200, :sent}]
    refute Spec.has_key?(entries, 13)
    next = [{13, 10, :reserved} | entries]
    assert Spec.proper_entries?(next)
    assert Spec.unique_keys?(next)
    assert Spec.hold_amount(next) == Spec.hold_amount(entries) + 10
    assert Spec.hold_count(next) == Spec.hold_count(entries) + 1
  end

  test "L6: converting all sent entries retains both holding counters" do
    entries = [{11, 300, :sent}, {12, 200, :unknown}, {13, 100, :voided}]
    changed = Ledger.mark_unknown(entries)
    assert Spec.lookup(changed, 11) == {:ok, {11, 300, :unknown}}
    assert Spec.hold_amount(changed) == Spec.hold_amount(entries)
    assert Spec.hold_count(changed) == Spec.hold_count(entries)
  end

  test "PO-C1/C2 proper event domain contains arbitrary Erlang terms, not improper lists" do
    assert Spec.proper_events?([])
    assert Spec.proper_events?([:restart, {:request, 11, 10}, 42, :bad, [1, 2]])
    refute Spec.proper_events?([:restart | :broken_tail])
    refute Spec.proper_events?(:restart)
  end

  test "PO-B7 no_sent accepts unknown and terminal, rejects any sent entry" do
    assert Spec.no_sent?([])
    assert Spec.no_sent?([{11, 10, :unknown}, {12, 20, :declined}])
    refute Spec.no_sent?([{11, 10, :unknown}, {12, 20, :sent}])
  end

  test "PO-C3 terminal entries keep their exact status, not only their amount" do
    before = {1000, 2, 0, 0, [{11, 300, :voided}]}
    good = {1000, 2, 50, 1, [{12, 50, :reserved}, {11, 300, :voided}]}
    bad = {1000, 2, 300, 1, [{11, 300, :reserved}]}
    assert Spec.valid?(before)
    assert Spec.valid?(good)
    assert Spec.valid?(bad)
    assert Spec.terminal_preserved?(before, good)
    refute Spec.terminal_preserved?(before, bad)
  end

  test "PO-C3 independent replay honors approval evidence over arbitrary finite trace" do
    state = Ledger.init(300, 1)

    events = [
      {:request, 11, 300},
      {:dispatch, 11},
      {:transport_ack, 11},
      :restart,
      {:retry, 11},
      {:processor_result, 11, :approved},
      {:void, 11},
      {:request, 11, 300}
    ]

    assert Spec.valid?(state)
    assert Spec.proper_events?(events)
    assert Ledger.run(state, events) == Spec.expected_run(state, events)
    assert Spec.history_authorizations_explained?(state, events)
    assert Spec.identity_preserved?(state, Ledger.run(state, events))
    assert Spec.terminal_preserved?(state, Ledger.run(state, events))
    assert Spec.lookup(elem(Ledger.run(state, events), 4), 11) == {:ok, {11, 300, :voided}}
  end

  test "L3 exact stored amount excludes floating point aliases" do
    entries = [{11, 9_007_199_254_740_992, :reserved}, {12, 1, :reserved}]
    floating_amount = 9_007_199_254_740_992.0
    assert Spec.proper_entries?(entries) and Spec.unique_keys?(entries)
    assert Spec.lookup(entries, 11) == {:ok, {11, floating_amount, :reserved}}
    refute Spec.lookup(entries, 11) === {:ok, {11, floating_amount, :reserved}}
    changed = Ledger.set_status(entries, 11, :voided)
    assert Spec.hold_amount(changed) == 1
    assert Spec.hold_amount(entries) - floating_amount == 0.0
  end
end
