defmodule HoldLedger do
  @moduledoc """
  An authorization-hold ledger with a pure state machine and a journaled OTP runtime.

  `HoldLedger.Ledger` implements state transitions; `HoldLedger.Spec` independently
  describes their expected behavior. `HoldLedger.Server` journals inputs before
  applying transitions and executes effects through a `HoldLedger.Processor`.

  See the guides for usage, recovery behavior and the scope of the formal laws.
  """
end
