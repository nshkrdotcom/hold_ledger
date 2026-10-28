defmodule HoldLedgerReview.VisualLabTest do
  use ExUnit.Case, async: false
  alias HoldLedgerReview.{Contrast, VisualLab}

  test "bounded discovery is reproducible and its candidate is distinct from observed output" do
    {:ok, doc} = Contrast.create("po_exposure_retain")
    step = List.last(doc["steps"])
    a = VisualLab.hunt("po_exposure_retain", step, 71, 12)
    b = VisualLab.hunt("po_exposure_retain", step, 71, 12)
    assert a.status == "found"
    assert a.output == b.output and a.seed == b.seed
    assert a.output != step["output"]
    assert a.cases <= 12
    assert VisualLab.hunt("po_a1", step, 71, 12).status == "unavailable"
    assert VisualLab.hunt("po_exposure_retain", step, 71, 0).status == "budget_exhausted"
  end
end
