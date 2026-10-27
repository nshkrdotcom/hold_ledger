defmodule HoldLedgerReview.AdversarialTest do
  use ExUnit.Case, async: false
  alias HoldLedgerReview.{Adversarial, Canonical, Claims}

  test "all eight seeded cases use the loaded source evaluator and independent Spec oracle" do
    assert :ok = Claims.freshness()

    for id <- Adversarial.seeds() do
      assert {:ok, witness} = Adversarial.seed(id)
      assert {:ok, decoded} = Adversarial.decode(witness)
      assert {:ok, ^witness} = Adversarial.encode(decoded)
      assert {:ok, evaluation, details} = Adversarial.evaluate(witness)
      assert evaluation["scope"] == "pointwise_pure_ledger"
      assert evaluation["candidate_hash"] == Canonical.digest(witness["output"])
      assert is_map(evaluation["actual"])
      assert is_map(evaluation["oracle"])
      assert evaluation["actual"] == evaluation["oracle"]
      assert details.actual_equals_oracle?
      assert evaluation["law_rows"] != []

      assert Enum.all?(evaluation["law_rows"], fn r ->
               r["label"] in ~w(catches allows_here does_not_apply cant_check) and
                 r["slug"] in Adversarial.active_slugs(decoded.event)
             end)

      if id in ~w(P06 P07) do
        assert witness["follow_on"] == nil
        assert evaluation["follow_on_actual"] == nil
        assert evaluation["follow_on_candidate"] == nil
        assert details.follow_reason == :no_follow_on_event
      end
    end
  end

  test "P01 and P05 differ only by hypothetical output; correct source catcher stays the authority" do
    {:ok, p1} = Adversarial.seed("P01")
    {:ok, p5} = Adversarial.seed("P05")
    assert p1["before"] == p5["before"]
    assert p1["event"] == p5["event"]
    assert p1["output"] != p5["output"]
    {:ok, e1, _} = Adversarial.evaluate(p1)
    {:ok, e5, _} = Adversarial.evaluate(p5)
    assert e1["actual"] == e5["actual"]
    assert Enum.any?(e1["law_rows"] ++ e5["law_rows"], &(&1["label"] == "catches"))
  end

  test "complete submitted form, including last keystroke, owns the candidate and no previous good state is used" do
    {:ok, p4} = Adversarial.seed("P04")
    form = Adversarial.form(p4)
    assert {:ok, _} = Adversarial.from_form(form)
    altered = put_in(p4, ["output", "after", "used_amount"], 99)
    changed = %{form | "output_json" => Jason.encode!(altered["output"])}
    assert {:ok, decoded} = Adversarial.from_form(changed)
    assert {:ok, submitted} = Adversarial.encode(decoded)
    assert submitted["output"]["after"]["used_amount"] == 99
    assert {:ok, evidence, _} = Adversarial.evaluate(submitted)
    assert evidence["candidate_hash"] == Canonical.digest(submitted["output"])
    assert {:error, :invalid_draft} = Adversarial.from_form(%{changed | "output_json" => "{"})

    assert {:error, :invalid_draft} =
             Adversarial.from_form(%{changed | "event_json" => ~s({"type":"bogus"})})

    assert {:error, :invalid_draft} =
             Adversarial.from_form(%{changed | "before_json" => ~s({"amount_limit":-1})})
  end

  test "shape-valid, non-Spec-valid hypothetical is examined, not silently discarded" do
    {:ok, p6} = Adversarial.seed("P06")
    assert {:ok, evidence, details} = Adversarial.evaluate(p6)
    assert details.candidate_after_valid? == false
    assert evidence["follow_on_candidate"] == nil
    assert evidence["follow_on_actual"] == nil
  end

  test "exact-fit 99/100/101 edits use source eligibility and positive admission" do
    {:ok, seed} = Adversarial.seed("P04")

    for amount <- [99, 100, 101] do
      witness = put_in(seed, ["event", "amount"], amount)
      {:ok, evaluation, details} = Adversarial.evaluate(witness)
      assert details.request_eligible? == amount <= 100
      row = Enum.find(evaluation["law_rows"], &(&1["slug"] == "po_a2"))
      assert row["label"] == if(amount <= 100, do: "catches", else: "does_not_apply")

      assert evaluation["actual"]["result"] ==
               if(amount <= 100, do: "admitted", else: "insufficient_amount")
    end
  end

  test "null follow-on never inspects or steps either after-state" do
    assert HoldLedgerReview.ClaimProbe.follow_on(:not_an_output, :not_an_output, nil) ==
             %{actual: nil, candidate: nil, reason: :no_follow_on_event}
  end
end
