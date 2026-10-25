defmodule HoldLedger.Laws.L3AccountingTest do
  use ExUnit.Case
  use HoldLedger.ProofCase

  alias HoldLedger.{Ledger, Spec}

  # L3 (L): changing one holding status produces exact delta.
  # Witness: test/hold_ledger_transition_test.exs.
  # Proof scope and commands: guides/verification.md.
  laws "l3_accounting", options: [maxHeartbeats: 2_000_000] do
    law(l3_accounting(entries, key, amount, from, to),
      requires:
        Spec.proper_entries?(entries) and Spec.unique_keys?(entries) and
          Spec.lookup(entries, key) === {:ok, {key, amount, from}} and Spec.known_status?(to),
      expects:
        Spec.hold_amount(Ledger.set_status(entries, key, to)) ==
          Spec.hold_amount(entries) - if(Spec.holding?(from), do: amount, else: 0) +
            if(Spec.holding?(to), do: amount, else: 0) and
          Spec.hold_count(Ledger.set_status(entries, key, to)) ==
            Spec.hold_count(entries) - if(Spec.holding?(from), do: 1, else: 0) +
              if(Spec.holding?(to), do: 1, else: 0),
      proof: ~LEAN"""
      exact Elixir.HoldLedger.ProofContracts.«l3_accounting/5» entries key amount «from» to requires
      """
    )
  end
end
