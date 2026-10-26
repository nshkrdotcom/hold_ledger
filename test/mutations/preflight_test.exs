defmodule HoldLedger.MutationPreflightTest do
  @moduledoc """
  Nine unmodified, concrete counterexamples. The isolated Python runner injects
  exactly one mutation into a temporary checkout and selects its matching tag.
  This file is also part of the normal (unmutated) ExUnit suite.
  """
  use ExUnit.Case, async: true
  alias HoldLedger.{Ledger, Spec, TestFixtures}

  @tag mutation: "M1"
  test "M1: terminal key must never revive or allocate twice" do
    s = {1000, 3, 0, 0, [{11, 300, :voided}]}
    assert Spec.valid?(s)
    assert Ledger.step(s, {:request, 11, 300}) == {s, :duplicate, []}
  end

  @tag mutation: "M2"
  test "M2: a timed-out sent hold of 300 must retain 300 cents and one slot" do
    s = TestFixtures.sent()
    assert Spec.valid?(s)
    assert Ledger.step(s, {:timeout, 11}) == {TestFixtures.unknown(), :marked_unknown, []}
  end

  @tag mutation: "M3"
  test "M3: a retry must reuse the same key and amount in its authorize effect" do
    s = TestFixtures.unknown()
    assert Spec.valid?(s)

    assert Ledger.step(s, {:retry, 11}) ==
             {TestFixtures.sent(), :retried, [{:authorize, 11, 300}]}
  end

  @tag mutation: "M4"
  test "M4: exact amount and slot fit must admit" do
    s = TestFixtures.exact_fit()
    assert Spec.request_eligible?(s, 11, 100)

    assert Ledger.step(s, {:request, 11, 100}) ==
             {{100, 1, 100, 1, [{11, 100, :reserved}]}, :admitted, []}
  end

  @tag mutation: "M5"
  test "M5: positive admission is mandatory with abundant capacity" do
    s = TestFixtures.empty()
    assert Spec.request_eligible?(s, 22, 100)

    assert Ledger.step(s, {:request, 22, 100}) ==
             {{1000, 3, 100, 1, [{22, 100, :reserved}]}, :admitted, []}
  end

  @tag mutation: "M6"
  test "M6: transport acknowledgment is never an approval" do
    s = TestFixtures.sent()
    assert Spec.valid?(s)
    assert Ledger.step(s, {:transport_ack, 11}) == {s, :stale, []}
  end

  @tag mutation: "M7"
  test "M7: authorized void requires a remote intent" do
    state = {1000, 3, 300, 1, [{11, 300, :authorized}]}

    assert Ledger.step(state, {:void, 11}) ==
             {{1000, 3, 300, 1, [{11, 300, :voiding}]}, :voiding, [{:void, 11}]}
  end

  @tag mutation: "M8"
  test "M8: decline releases exactly its contribution" do
    assert Ledger.step(TestFixtures.sent(), {:processor_result, 11, :declined}) ==
             {{1000, 3, 0, 0, [{11, 300, :declined}]}, :declined, []}
  end

  @tag mutation: "M9"
  test "M9: restart removes sent status without releasing capacity" do
    assert Ledger.step(TestFixtures.sent(), :restart) == {TestFixtures.unknown(), :restarted, []}
  end
end
