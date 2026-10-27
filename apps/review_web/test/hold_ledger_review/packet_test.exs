defmodule HoldLedgerReview.PacketTest do
  use ExUnit.Case, async: true
  alias HoldLedgerReview.{Anchor, Cases, Facts, Packet, ProofEvidence, TermCodec}

  test "three golden policy transitions, candidates and law mappings" do
    for c <- Cases.all() do
      assert {:ok, p} = Packet.build(c.id, report: nil)
      assert p.facts.actual == c.expected
      assert p.facts.oracle == c.expected
      refute p.facts.disputed?
      assert p.proof.status == :not_supplied
      assert Enum.all?(p.facts.domains, fn {_, value} -> value end)
      assert Packet.current?(p)
      assert {:ok, again} = Packet.build(c.id, report: nil)
      assert p.packet_sha256 == again.packet_sha256

      assert Enum.all?(c.laws, fn {slug, _, _} ->
               Map.has_key?(p.anchors, c.id <> ".law." <> slug)
             end)
    end

    {:ok, p} = Packet.build("void_pending", report: nil)

    assert p.facts.matrix == %{
             "correct" => %{"valid" => true, "effects" => true, "retention" => true},
             "early_release" => %{"valid" => true, "effects" => false, "retention" => false},
             "lost_effect" => %{"valid" => true, "effects" => false, "retention" => true},
             "early_release_no_effect" => %{
               "valid" => true,
               "effects" => true,
               "retention" => false
             }
           }

    assert {:ok, {_, :insufficient_amount, []}} = Facts.follow(p.facts.actual, p.case.follow)

    assert {:ok, {_, :admitted, []}} =
             Facts.follow(p.facts.candidates["early_release"], p.case.follow)

    {:ok, t} = Packet.build("timeout_unknown", report: nil)
    assert {:ok, {_, :insufficient_amount, []}} = Facts.follow(t.facts.actual, t.case.follow)
    assert t.facts.matrix["invent_decline"] == %{"valid" => true, "retention" => false}
    {:ok, e} = Packet.build("exact_fit", report: nil)
    assert e.facts.matrix["reject_equality"] == %{"valid" => true, "admission" => false}
    assert e.facts.matrix["always_reject"] == %{"valid" => true, "admission" => false}
    refute Facts.domain?("po_a2", {100, 1, 100, 1, [{1, 100, :authorized}]}, {:request, 2, 100})

    assert {:error, :invalid_state} =
             Facts.follow({{100, 1, 200, 0, []}, :bad, []}, {:request, 1, 1})

    assert Facts.build(%{e.case | expected: {e.case.before, :bad, []}}).disputed?
  end

  test "anchors fail for missing, ambiguous and unsafe sources; source edits stale the packet" do
    root = Path.join(System.tmp_dir!(), "ledger-source-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    File.write!(Path.join(root, "sample"), "marker marker")
    assert {:error, _} = Anchor.resolve(root, "sample", "marker", :file, ["sample"])
    assert {:error, _} = Anchor.resolve(root, "sample", "absent", :file, ["sample"])
    assert {:error, _} = Anchor.resolve(root, "../sample", "marker", :file, ["../sample"])
    File.ln_s!("/etc/passwd", Path.join(root, "link"))
    assert {:error, _} = Anchor.read_under(root, "link")
    {:ok, p} = Packet.build("void_pending", report: nil)

    refute Packet.current?(%{
             p
             | source_sha256: Map.put(p.source_sha256, "lib/hold_ledger/ledger.ex", "changed")
           })

    assert {:error, :unknown_case} = Packet.build("../../etc/passwd")
  end

  test "bounded codec rejects unknown atoms, malformed nested values and excessive input" do
    assert {:ok, {:request, 1, 100}} =
             TermCodec.decode_event(%{"type" => "request", "key" => 1, "amount" => 100})

    for v <- [
          %{"type" => "evil", "key" => 1},
          %{"type" => "request", "key" => 1, "amount" => -1},
          %{"type" => "request", "key" => 1.0, "amount" => 1}
        ] do
      assert {:error, :malformed} = TermCodec.decode_event(v)
    end

    s = %{
      "amount_limit" => 100,
      "hold_limit" => 1,
      "used_amount" => 0,
      "used_holds" => 0,
      "entries" => []
    }

    assert {:ok, {100, 1, 0, 0, []}} = TermCodec.decode_state(s)

    assert {:error, :malformed} =
             TermCodec.decode_state(%{
               s
               | "entries" => [%{"key" => 1, "amount" => 1, "status" => "invented"}]
             })

    assert {:error, :malformed} = TermCodec.decode_state(Map.put(s, "extra", true))
  end

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

  test "source override cannot attach different source to compiled facts" do
    root = Path.join(System.tmp_dir!(), "review-compiled-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(root, "lib/hold_ledger"))
    on_exit(fn -> File.rm_rf!(root) end)
    File.write!(Path.join(root, "lib/hold_ledger/ledger.ex"), "different source")
    refute HoldLedgerReview.Config.source_matches?(root)
    assert {:error, :compiled_source_drift} = Packet.build("void_pending", root: root)
  end
end
