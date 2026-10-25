defmodule HoldLedger.Laws.PoB2Test do
  use ExUnit.Case
  use HoldLedger.ProofCase

  @moduletag timeout: 600_000

  alias HoldLedger.{Ledger, Spec}

  # PO-B2 (P0): unknown key amount persists as holding (unknown/sent) until its valid result.
  # Witness: test/hold_ledger_witness_test.exs.
  # Proof scope and commands: guides/verification.md.
  laws "po_b2", options: [maxHeartbeats: 16_000_000] do
    law(po_b2(s, event, key, amount),
      requires:
        Spec.valid?(s) and Spec.lookup(elem(s, 4), key) == {:ok, {key, amount, :unknown}} and
          event != {:processor_result, key, :approved} and
          event != {:processor_result, key, :declined},
      expects:
        (Spec.lookup(elem(elem(Ledger.step(s, event), 0), 4), key) ==
           {:ok, {key, amount, :unknown}} or
           Spec.lookup(elem(elem(Ledger.step(s, event), 0), 4), key) ==
             {:ok, {key, amount, :sent}}) and
          Spec.identity_preserved?(s, elem(Ledger.step(s, event), 0)),
      proof: ~LEAN"""
      exact Elixir.HoldLedger.ProofContracts.«po_b2/4» s event key amount requires
      """
    )
  end
end
