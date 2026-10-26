defmodule HoldLedger.ExposureRetentionTest do
  use ExUnit.Case, async: true
  use ExUnitProperties
  import StreamData
  alias HoldLedger.{Ledger, Spec, TestGenerators}

  property "an issued hold retains capacity absent its own terminal evidence" do
    check all(
            status <- member_of([:sent, :unknown, :authorized, :voiding]),
            event <- TestGenerators.event(),
            max_runs: 10_000
          ) do
      state = {100, 2, 100, 1, [{1, 100, status}]}

      if not Spec.release_evidence?(event, 1) do
        {next, _, _} = Ledger.step(state, event)
        assert Spec.exposed_entry?(next, 1, 100)
      end
    end
  end
end
