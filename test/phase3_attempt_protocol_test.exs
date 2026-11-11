Code.require_file("../verification/research/attempt_protocol.ex", __DIR__)

defmodule HoldLedger.Phase3AttemptProtocolTest do
  use ExUnit.Case, async: true

  alias HoldLedger.Verification.AttemptProtocol, as: Model

  test "admitted interleavings refine the pure Attempts transition relation" do
    {:bounded, evidence} = Model.bounded(7)
    assert evidence.depth == 7
    assert evidence.states > 10
    assert evidence.truncated_at_depth
  end

  test "stopping and committing keep a slot until successful sync; stale result ignored" do
    initial = Model.init()
    running = Model.step(initial, {:start, :authorize, 7, 1})
    assert {2, false, [{1, :authorize, 7, :running}]} = Model.project(running)
    stopping = Model.step(running, {:deadline, 1})
    assert Model.step(stopping, {:result, 1}) == stopping
    assert Model.step(stopping, {:start, :authorize, 7, 1}) == stopping
    committing = Model.step(stopping, {:shutdown_result, 1})
    assert Model.step(committing, {:start, :authorize, 7, 1}) == committing
    assert Model.step(committing, {:persist_ok, 2}) == committing
    assert Model.safe?(committing)
    retired = Model.step(committing, {:persist_ok, 1})
    assert Model.safe?(retired)
    assert MapSet.member?(retired.synced, 1)
    assert Model.step(retired, {:late_result, 1}) == retired
    next = Model.step(retired, {:start, :authorize, 7, 1})
    assert {3, false, [{2, :authorize, 7, :running}]} = Model.project(next)
  end

  test "sync failure poisons without freeing occupied slot" do
    running = Model.step(Model.init(), {:start, :void, 7, 1})
    committing = Model.step(running, {:result, 1})
    failed = Model.step(committing, {:persist_error, 1})
    assert failed.poisoned?
    assert failed.active == [{1, :void, 7, :committing}]
    assert MapSet.member?(failed.pending, 1)
    assert Model.step(failed, {:start, :void, 8, 2}) == failed
    assert Model.step(failed, {:persist_ok, 1}) == failed
    assert Model.source_step_agrees?(failed, {:persist_ok, 1})
    assert Model.safe?(failed)
    assert Model.source_step_agrees?(committing, {:persist_error, 1})
  end

  test "incorrect early retirement has a complete two-step counterexample" do
    {:counterexample, trace, evidence} = Model.bounded(4, :retire_before_sync)
    assert [{:start, :authorize, 7, 1}, {:result, 1}] == trace
    refute Model.safe?(evidence.state)
    refute MapSet.member?(evidence.state.synced, 1)
  end

  test "incorrect acceptance of a retired attempt is detected with a complete trace" do
    {:counterexample, trace, evidence} = Model.bounded(6, :accept_retired_result)
    assert List.last(trace) == {:late_result, 1}
    assert {:persist_ok, 1} in trace
    refute Model.safe?(evidence.state)
  end

  test "finite-depth and resource ceilings are explicit, not successful release proofs" do
    assert {:bounded, %{depth: 1, truncated_at_depth: true}} = Model.bounded(1)
    assert {:resource_limit, %{depth: 7}} = Model.bounded(7, :correct, 2)
  end
end
