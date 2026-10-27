defmodule HoldLedgerReview.ProofEvidenceTest do
  use ExUnit.Case, async: true
  alias HoldLedgerReview.{Anchor, ProofEvidence}

  # These tests preserve independent proof-report validation, not the deleted
  # teaching-case packet or receipt mechanism. All checker records are
  # synthetic fixtures, never evidence that a real checker ran.
  test "report parser rejects invented success, missing manifest and proof-only checker claims" do
    root = HoldLedgerReview.Config.root()

    base = %{
      "mode" => "EXECUTED",
      "stage" => "proofs",
      "laws" => %{"po_b1_void" => %{"passed" => true}},
      "complete" => true,
      "source_sha256" => ProofEvidence.manifest(root),
      "source_changes_during_run" => [],
      "cache" => "LYNX_CACHE=0",
      "checker_claim" => true
    }

    assert :development_only = ProofEvidence.status(root, base, ["po_b1_void"])

    assert :stale =
             ProofEvidence.status(root, Map.put(base, "source_sha256", %{}), ["po_b1_void"])

    assert :incomplete = ProofEvidence.status(root, base, ["missing_law"])

    assert :stale =
             ProofEvidence.status(root, Map.put(base, "source_changes_during_run", ["x"]), [
               "po_b1_void"
             ])

    assert :incomplete =
             ProofEvidence.status(root, Map.put(base, "stage", "future-schema"), ["po_b1_void"])

    full = Map.put(base, "stage", "full")
    assert :incomplete = ProofEvidence.status(root, full, ["po_b1_void"])

    assert :failed =
             ProofEvidence.status(root, put_in(base, ["laws", "po_b1_void", "passed"], false), [
               "po_b1_void"
             ])
  end

  test "fixture reports distinguish selected/full acceptance and tampered export bytes" do
    root = HoldLedgerReview.Config.root()

    relative =
      "tmp/verification/exports/review-fixture-#{System.unique_integer([:positive])}.ndjson"

    path = Path.join(root, relative)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, "synthetic checker fixture; not real proof evidence")
    on_exit(fn -> File.rm(path) end)

    export = %{
      "passed" => true,
      "allowed_axioms" => true,
      "axiom_list" => ["propext"],
      "checker_acceptance" =>
        Map.new(
          ["Lean paranoid", "lean4lean", "nanoda", "con-leche", "con-ron", "Lean default"],
          &{&1, true}
        ),
      "path" => relative,
      "export_bytes" => File.stat!(path).size,
      "export_sha256" => Anchor.sha(File.read!(path))
    }

    source = "test/laws/po_b1_void_test.exs"

    law = %{
      "native_passed" => true,
      "passed" => true,
      "exports" => [export],
      "source" => source,
      "source_sha256" => ProofEvidence.digest_file(root, source)
    }

    r = %{
      "mode" => "EXECUTED",
      "stage" => "full",
      "laws" => %{"po_b1_void" => law},
      "complete" => true,
      "source_sha256" => ProofEvidence.manifest(root),
      "source_changes_during_run" => [],
      "cache" => "LYNX_CACHE=0",
      "checker_claim" => true,
      "release_complete" => false
    }

    assert :selected_checked = ProofEvidence.status(root, r, ["po_b1_void"])

    assert :incomplete =
             ProofEvidence.status(root, Map.put(r, "release_complete", true), ["po_b1_void"])

    catalog = Jason.decode!(File.read!(Path.join(root, "verification/laws.json")))["laws"]

    records =
      Map.new(catalog, fn item ->
        p = item["file"]

        {item["slug"],
         %{law | "source" => p, "source_sha256" => ProofEvidence.digest_file(root, p)}}
      end)

    slugs = Enum.sort(Map.keys(records))

    full =
      Map.merge(r, %{
        "laws" => records,
        "release_complete" => true,
        "obligation_coverage" => %{
          "complete" => true,
          "missing" => [],
          "required" => slugs,
          "accepted" => slugs
        }
      })

    assert :full_catalog_checked = ProofEvidence.status(root, full, ["po_b1_void"])
    File.write!(path, "tampered")
    assert :incomplete = ProofEvidence.status(root, r, ["po_b1_void"])
  end

  test "anchor reader rejects untrusted or ambiguous source selectors" do
    root = Path.join(System.tmp_dir!(), "anchor-source-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    File.write!(Path.join(root, "sample"), "marker marker")
    assert {:error, _} = Anchor.resolve(root, "sample", "marker", :file, ["sample"])
    assert {:error, _} = Anchor.resolve(root, "sample", "absent", :file, ["sample"])
    assert {:error, _} = Anchor.resolve(root, "../sample", "marker", :file, ["../sample"])
    File.ln_s!("/etc/passwd", Path.join(root, "link"))
    assert {:error, :unsafe_path} = Anchor.read_under(root, "link")
  end
end
