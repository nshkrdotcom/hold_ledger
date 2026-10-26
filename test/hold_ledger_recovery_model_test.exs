defmodule HoldLedger.RecoveryModelTest do
  use ExUnit.Case, async: true
  alias HoldLedger.Composite

  test "accepted commit records replay to the live durable state" do
    initial = Composite.init(100, 2)

    events = [
      {:request, 1, 100},
      {:dispatch, 1},
      {:processor_result, 1, :approved},
      {:void, 1},
      {:void_attempt, 1},
      :restart,
      {:void_outcome, 1, {:error, :timeout}},
      {:void_confirmed, 1}
    ]

    {commits, final} =
      Enum.map_reduce(events, initial, fn event, state ->
        {next, _, _} = Composite.step(state, event)
        {{event, next}, next}
      end)

    assert Composite.commits_match?(initial, commits)
    assert Composite.replay_commits(initial, commits) == final
    assert Composite.recorded_final(initial, commits) == final
    assert Composite.replay_commits(initial, []) == initial
    [{event, _} | tail] = commits
    refute Composite.commits_match?(initial, [{event, initial} | tail])
  end
end
