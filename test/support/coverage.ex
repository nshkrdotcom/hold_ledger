defmodule HoldLedger.PropertyCoverage do
  @moduledoc """
  Real candidate/eligible/discard counts for each property, not assumed run
  totals. Each check uses its own ETS table to avoid cross-test interference.
  Every target generator is eligible by construction: discards are a failure.
  """
  def start, do: :ets.new(__MODULE__, [:set, :public])

  def hit(table, eligible?, applied? \\ false) do
    eligible_delta = if eligible?, do: 1, else: 0
    applied_delta = if applied?, do: 1, else: 0

    :ets.update_counter(
      table,
      :samples,
      [{2, 1}, {3, eligible_delta}, {4, applied_delta}],
      {:samples, 0, 0, 0}
    )
  end

  def report!(table, law, expected_candidates, opts \\ []) do
    [{:samples, candidates, eligible, applied}] = :ets.lookup(table, :samples)
    discarded = candidates - eligible
    :ets.delete(table)

    unless candidates == expected_candidates and eligible > 0 and discarded == 0 and
             (not Keyword.get(opts, :require_applied, false) or applied > 0) do
      raise "#{law}: expected #{expected_candidates} candidates, " <>
              "observed #{candidates} (eligible #{eligible}, discarded #{discarded}, applied #{applied})"
    end

    IO.puts(
      "PROPERTY-COVERAGE law=#{law} candidates=#{candidates} eligible=#{eligible} discarded=#{discarded} applied=#{applied}"
    )

    {candidates, eligible, discarded, applied}
  end
end
