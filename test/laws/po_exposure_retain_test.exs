defmodule HoldLedger.Laws.PoExposureRetainTest do
  use ExUnit.Case
  use HoldLedger.ProofCase
  alias HoldLedger.{Ledger, Spec}

  laws "po_exposure_retain", options: [maxHeartbeats: 16_000_000] do
    law(po_exposure_retain(state, event, key, amount, status),
      requires:
        Spec.valid?(state) and is_integer(key) and is_integer(amount) and
          Spec.lookup(elem(state, 4), key) === {:ok, {key, amount, status}} and
          status in [:sent, :unknown, :authorized, :voiding] and
          not Spec.release_evidence?(event, key),
      expects: Spec.exposed_entry?(elem(Ledger.step(state, event), 0), key, amount),
      proof: ~LEAN"""
      exact Elixir.HoldLedger.ProofContracts.«po_exposure_retain/5» state event key amount status requires
      """
    )
  end
end
