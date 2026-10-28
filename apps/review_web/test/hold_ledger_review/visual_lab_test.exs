defmodule HoldLedgerReview.VisualLabTest do
  use ExUnit.Case, async: false
  alias HoldLedgerReview.{Contrast, VisualLab}

  test "fencing illustration separates real local capacity from resurrected remote exposure" do
    safe = VisualLab.environment(true, true) |> List.last()
    fault = VisualLab.environment(false, true) |> List.last()
    assert safe.local == 0 and safe.remote == 0 and safe.covered
    assert fault.local == 0 and fault.remote == 100 and not fault.covered
    assert fault.provenance == "counterfactual illustration"
    assert safe.provenance == "original Exposure model"
  end

  test "lost durable state is an explicit illustration, not an original model transition" do
    frame = VisualLab.environment(true, false) |> Enum.at(4)
    assert frame.local == 0 and frame.remote == 100 and not frame.covered
    assert frame.provenance == "counterfactual illustration"
    assert VisualLab.environment(true, false) |> List.last() |> Map.fetch!(:remote) == 100
  end

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
