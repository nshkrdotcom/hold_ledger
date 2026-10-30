defmodule HoldLedgerReview.ClaimLensTest do
  use ExUnit.Case, async: false
  alias HoldLedgerReview.ClaimLens

  test "exact-fit exclusion loses a forbidden-output witness from the domain" do
    assert {:ok, result} = ClaimLens.observe("po_a2", "exact", "strict")
    assert result.witness.policy == :forbidden
    assert result.before["amount_limit"] == 100
    assert result.event["amount"] == 100
    assert result.actual["result"] == "admitted"
    assert result.candidate["result"] == "insufficient_amount"
    assert result.baseline.status == :catches
    assert result.alternative.status == :doesnt_apply
    assert result.alternative.applies? == false
    assert result.changed?
  end

  test "narrower requirement still covers one cent below, never admits above capacity" do
    assert {:ok, below} = ClaimLens.observe("po_a2", "below", "strict")
    assert below.alternative.status == :catches
    assert below.alternative.applies?
    assert {:ok, above} = ClaimLens.observe("po_a2", "above", "strict")
    assert above.witness.policy == :allowed
    assert above.baseline.status == :doesnt_apply
    assert above.alternative.status == :doesnt_apply
  end

  test "real authorized-void candidate is caught before terminal evidence" do
    assert {:ok, result} = ClaimLens.observe("po_exposure_retain", "void", "drop_release")
    assert result.witness.policy == :forbidden
    assert result.actual["result"] == "voiding"
    assert result.actual["after"]["used_amount"] == 100
    assert result.candidate["after"]["used_amount"] == 0
    assert result.baseline.status == :catches
    assert result.alternative.status == :catches
  end

  test "removing release-evidence guard creates a false demand after confirmation" do
    assert {:ok, result} = ClaimLens.observe("po_exposure_retain", "confirmed", "drop_release")
    assert result.witness.policy == :allowed
    assert result.candidate == result.actual
    assert result.baseline.status == :doesnt_apply
    assert result.alternative.status == :catches
    assert result.alternative.applies?
  end

  test "timeout is not terminal release evidence" do
    assert {:ok, result} = ClaimLens.observe("po_exposure_retain", "timeout", "drop_release")
    assert result.witness.policy == :forbidden
    assert result.actual["after"]["used_amount"] == 100
    assert result.baseline.status == :catches
    assert result.alternative.status == :catches
  end

  test "proof-body-only illustration never claims a changed contract" do
    assert {:ok, result} = ClaimLens.observe("po_a2", "exact", "proof_only")
    refute result.changed?
    assert result.alternative.status == result.baseline.status
  end

  test "hand-authored policy excerpts remain tied to current specification bytes" do
    for study <- ClaimLens.studies() do
      assert {:ok, reading} = HoldLedgerReview.ProofReading.document(study.slug)
      assert {:ok, line} = ClaimLens.policy_line(study, reading)
      assert line > 0
    end
  end

  test "a stale registered policy digest cannot endorse a curated policy verdict" do
    assert {:ok, reading} = HoldLedgerReview.ProofReading.document("po_a2")
    assert {:ok, study} = ClaimLens.study("po_a2")

    sources =
      Enum.map(reading["sources"], fn source ->
        if source["path"] == "guides/specification.md",
          do: %{source | "sha256" => String.duplicate("0", 64)},
          else: source
      end)

    assert {:error, :policy_quote_unavailable} =
             ClaimLens.policy_line(study, %{reading | "sources" => sources})
  end

  test "only reviewed hand-authored studies, witnesses and variations are selectable" do
    assert Enum.map(ClaimLens.studies(), & &1.slug) == ~w(po_a2 po_exposure_retain)
    assert {:error, :unknown_study} = ClaimLens.study("l2_identity")
    assert {:error, :observation_unavailable} = ClaimLens.observe("po_a2", "other", "strict")
    assert {:error, :observation_unavailable} = ClaimLens.observe("po_a2", "exact", "fake")
  end
end
