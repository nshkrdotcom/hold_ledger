defmodule HoldLedger.Composite do
  @moduledoc """
  Pure atomic ledger/obligation transition, shared by live application and replay.

  Valid inputs satisfy `Spec.composite_valid?/1`: exactly one obligation exists
  for each voiding key and no others. I/O and confirmation authority belong to
  Server. The independent composite oracle is implemented in Spec.
  """
  alias HoldLedger.{Ledger, Outbox}

  def init(amount, count), do: {Ledger.init(amount, count), []}

  def step({ledger, obligations}, event) do
    {next, result, effects} = Ledger.step(ledger, event)
    outbox = open_effects(effects, obligations)

    outbox =
      case {event, result} do
        {{:void_confirmed, key}, :voided} -> Outbox.remove(outbox, key)
        _ -> Outbox.fold(outbox, event)
      end

    {{next, outbox}, result, effects}
  end

  def run(state, []), do: state

  def run(state, [event | rest]) do
    {next, _, _} = step(state, event)
    run(next, rest)
  end

  @doc "Abstract successful durable transitions, scoped to a proper list of commit records."
  def commits_match?(_state, []), do: true

  def commits_match?(state, [{event, next} | rest]) do
    {actual, _, _} = step(state, event)
    actual === next and commits_match?(next, rest)
  end

  def commits_match?(_, _), do: false

  @doc "Replay only the events from an abstract accepted-commit trace."
  def replay_commits(state, []), do: state

  def replay_commits(state, [{event, _} | rest]) do
    {next, _, _} = step(state, event)
    replay_commits(next, rest)
  end

  @doc "Read the final durable state recorded by a live commit trace."
  def recorded_final(state, []), do: state
  def recorded_final(_state, [{_, next} | rest]), do: recorded_final(next, rest)

  defp open_effects([], outbox), do: outbox

  defp open_effects([{:void, key} | rest], outbox),
    do: open_effects(rest, Outbox.open(outbox, key))

  defp open_effects([_ | rest], outbox), do: open_effects(rest, outbox)
end
