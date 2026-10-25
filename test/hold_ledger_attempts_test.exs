defmodule HoldLedgerAttemptsTest do
  use ExUnit.Case, async: true
  use ExUnitProperties
  alias HoldLedger.Attempts

  test "deadline retains the slot through shutdown and durable commit" do
    {running, [{:spawn, 1}]} = Attempts.step(Attempts.init(), {:start, :void, 7, 2})
    {stopping, [{:shutdown, 1, :void, 7}]} = Attempts.step(running, {:deadline, 1})
    assert {stopping, []} == Attempts.step(stopping, {:result, 1})
    assert {stopping, []} == Attempts.step(stopping, {:start, :void, 7, 2})

    {committing, [{:persist, 1, :void, 7}]} =
      Attempts.step(stopping, {:shutdown_result, 1})

    assert {committing, []} == Attempts.step(committing, {:start, :void, 7, 2})
    {retired, [{:retire, 1}]} = Attempts.step(committing, {:committed, 1})
    assert {retired, []} == Attempts.step(retired, {:result, 1})
    assert {_, [{:spawn, 2}]} = Attempts.step(retired, {:start, :void, 7, 2})
  end

  test "poison prevents spawning even when slots are available" do
    {poisoned, []} = Attempts.step(Attempts.init(), :poison)
    assert {poisoned, []} == Attempts.step(poisoned, {:start, :authorize, 1, 32})
  end

  property "arbitrary interleavings preserve unique slots, bounded work and monotone IDs" do
    event =
      one_of([
        map({member_of([:authorize, :void, :lookup]), integer(1..3)}, fn {kind, key} ->
          {:start, kind, key, 4}
        end),
        map(
          {member_of([:result, :down, :deadline, :shutdown_result, :committed]), integer(1..30)},
          fn
            {tag, id} -> {tag, id}
          end
        ),
        constant(:poison)
      ])

    check all(events <- list_of(event, max_length: 100), max_runs: 1_000) do
      Enum.reduce(events, Attempts.init(), fn event, {old_next, old_poison, _} = before ->
        {{next, poison, entries} = after_state, _intents} = Attempts.step(before, event)
        assert next >= old_next
        assert not old_poison or poison
        assert length(entries) <= 4
        slots = Enum.map(entries, fn {_, kind, key, _} -> {kind, key} end)
        assert length(Enum.uniq(slots)) == length(slots)

        assert Enum.all?(entries, fn {id, _, _, phase} ->
                 id < next and phase in [:running, :stopping, :committing]
               end)

        after_state
      end)
    end
  end
end
