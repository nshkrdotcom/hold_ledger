defmodule HoldLedger.Processor do
  @moduledoc """
  Contract for the *assumed* external processor boundary. The in-process
  implementation is `HoldLedger.Processor.Sim`; it is not formally verified.

  An authorize response may be delivered, lost, delayed, or duplicated. A
  transport response is never proof of authorization to the pure ledger: only
  a journaled `{:processor_result, key, outcome}` makes that transition.
  """

  @type identity :: integer()
  @type outcome :: :approved | :declined
  @type reply ::
          {:ok, outcome()}
          | {:lost, :request | :reply}
          | {:delayed, non_neg_integer(), reply()}
          | {:callbacks, [outcome()]}

  @callback authorize(term(), identity(), pos_integer()) :: reply()
  @callback lookup(term(), identity()) :: {:ok, outcome()} | :not_found | {:error, term()}
  @callback void(term(), identity()) :: {:ok, term()} | {:error, term()}
end
