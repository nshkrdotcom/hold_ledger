defmodule HoldLedgerReview.ExplanationTest do
  use ExUnit.Case, async: false
  alias HoldLedger.{Ledger, Spec}
  alias HoldLedgerReview.{Adversarial, Canonical, ClaimProbe, TermCodec}

  defp nodes(node), do: [node | Enum.flat_map(node["children"], &nodes/1)]

  test "source helper exposes actual exact-fit operands, guards and failure at 101" do
    state = Ledger.init(100, 2)

    for {amount, applies} <- [{99, true}, {100, true}, {101, false}] do
      event = {:request, 11, amount}
      output = Ledger.step(state, event)
      assert {:ok, view} = ClaimProbe.explain("po_a2", state, event, output)
      row = hd(view["bindings"])
      assert row["requires"]["value"] == applies
      all = nodes(row["requires"])
      capacity = Enum.find(all, &(&1["expression"] == "amount <= amount_limit - used_amount"))
      assert capacity["value"] == applies
      assert Enum.map(capacity["children"], & &1["value"]) == [amount, 100]
      assert Enum.any?(all, &(&1["expression"] == "is_integer(key)" and &1["value"] == true))
      assert row["values"]["key"] == 11
      assert row["values"]["amount"] == amount
      if not applies, do: assert(row["candidate"] == nil)
      assert is_binary(Canonical.json(view))
    end
  end

  test "short-circuiting labels untouched conditions instead of executing them" do
    {state, _, _} = Ledger.step(Ledger.init(100, 0), {:request, 11, 1})

    assert {:ok, view} =
             ClaimProbe.explain(
               "po_a2",
               state,
               {:request, 11, 100},
               Ledger.step(state, {:request, 11, 100})
             )

    all = nodes(hd(view["bindings"])["requires"])

    assert Enum.any?(
             all,
             &(&1["expression"] == "amount <= amount_limit - used_amount" and
                 &1["status"] == "not_evaluated")
           )
  end

  test "coherent early release passes validity and fails the actual retention expression" do
    {:ok, witness} = Adversarial.seed("P05")
    {:ok, decoded} = Adversarial.decode(witness)
    assert Spec.valid?(elem(decoded.output, 0))

    assert ClaimProbe.probe("po_b1_void", decoded.before, decoded.event, decoded.output).status ==
             :allows_here

    assert ClaimProbe.probe("po_exposure_retain", decoded.before, decoded.event, decoded.output).status ==
             :catches

    assert {:ok, view} =
             ClaimProbe.explain(
               "po_exposure_retain",
               decoded.before,
               decoded.event,
               decoded.output
             )

    row = hd(view["bindings"])
    assert row["requires"]["value"]
    assert row["actual"]["value"]
    refute row["candidate"]["value"]

    assert Enum.any?(
             nodes(row["candidate"]),
             &(&1["expression"] == "status in [:sent, :unknown, :authorized, :voiding]" and
                 &1["value"] == false)
           )

    assert row["values"]["status"] == "authorized"
  end

  test "all retained-entry bindings include off-event identities and incomplete domains stay unsupported" do
    {:ok, witness} = Adversarial.seed("P07")
    {:ok, w} = Adversarial.decode(witness)
    assert {:ok, view} = ClaimProbe.explain("po_exposure_retain", w.before, w.event, w.output)
    assert Enum.sort(Enum.map(view["bindings"], & &1["values"]["key"])) == [1, 2]

    assert {:error, :truncated_binding_domain} =
             ClaimProbe.explain("po_exposure_retain", w.before, w.event, w.output,
               binding_limit: 1
             )

    assert {:error, :outside_initial_probe_scope} =
             ClaimProbe.explain("po_a1", w.before, w.event, w.output)
  end

  test "typed observation values refuse arbitrary tuples and atoms" do
    assert {:error, _} = TermCodec.encode_inspection({:unregistered, 1, :hidden})
    assert {:error, _} = TermCodec.encode_inspection(self())
    assert {:error, _} = TermCodec.encode_inspection(:unregistered)
  end
end
