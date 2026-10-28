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
end
