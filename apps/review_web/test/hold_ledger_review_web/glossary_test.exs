defmodule HoldLedgerReviewWeb.GlossaryTest do
  use ExUnit.Case, async: true
  alias HoldLedgerReview.{Claims, Dossier}
  alias HoldLedgerReviewWeb.Glossary

  test "every registered source law has a human description" do
    {:ok, catalog} = Claims.catalog()
    assert length(catalog) == 49

    for law <- catalog do
      assert Glossary.law_description(law["slug"]) != "No description yet", law["slug"]
    end
  end

  test "all answer vocabularies and visible evidence statuses are defined" do
    kinds = ~w(reading escape silence assumption trace)

    statuses =
      ~w(reserved sent unknown authorized voiding declined voided not_supplied development_only selected_checked full_catalog_checked incomplete stale failed in_progress review_concluded stale_read_only pending complete interrupted discarded_late)

    outcomes = ~w(needs_policy_or_evidence needs_design_change meets_intent_in_reviewed_scope)
    choices = Enum.flat_map(kinds, &Dossier.choices/1)

    for key <- kinds ++ statuses ++ outcomes ++ choices ++ ["pin_only"] do
      assert {label, short, long} = Glossary.entry(key), key
      assert byte_size(label) > 0 && byte_size(short) > 0 && byte_size(long) > 0
    end
  end

  test "every scenario has a source-policy briefing without revealing its rule results" do
    for seed <- HoldLedgerReview.Adversarial.seeds() do
      briefing = Glossary.briefing(seed)

      for field <- ~w(why term1 idea1 term2 idea2 arrow policy weigh1 weigh2 teaches time) do
        assert is_binary(briefing[field]) && byte_size(briefing[field]) > 0, seed <> ": " <> field
      end

      assert Glossary.entry(briefing["term1"])
      assert Glossary.entry(briefing["term2"])
      refute Regex.match?(~r/po_|allows_here|catches/i, Enum.join(Map.values(briefing), " "))
    end
  end
end
