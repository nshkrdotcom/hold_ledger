defmodule HoldLedgerReview.Part3Test do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest, only: [get: 2]
  import Phoenix.LiveViewTest
  @endpoint HoldLedgerReviewWeb.Endpoint

  alias HoldLedgerReview.{
    Adversarial,
    Canonical,
    Config,
    Part3BoundarySearch,
    Part3ContractDelta,
    Part3Diagnostics,
    Part3Docket,
    Part3Package,
    Part3ProofInspector,
    Part3RepairPacket,
    Part3Result,
    Part3Snapshots,
    Part3Store,
    Part3Verification
  }

  # A pair of content-addressed *disposable, synthetic* local snapshots; never
  # modifies the authoritative reducer, Spec, laws or policy in the checkout.
  # One fixture changes a non-evaluator file, another changes a helper source.
  setup_all do
    source = Config.root()

    {paths, 0} =
      System.cmd("git", ["ls-files", "-z", "--cached", "--others", "--exclude-standard"],
        cd: source
      )

    files =
      paths
      |> String.split(<<0>>, trim: true)
      |> Enum.filter(&File.regular?(Path.join(source, &1)))
      |> Enum.sort()

    commit = System.cmd("git", ["rev-parse", "HEAD"], cd: source) |> elem(0) |> String.trim()
    base = capture(files, commit, %{})

    proposal =
      capture(files, commit, %{
        "README.md" =>
          File.read!(Path.join(source, "README.md")) <> "\n<!-- disposable review fixture -->\n"
      })

    spec = File.read!(Path.join(source, "lib/hold_ledger/spec.ex"))

    helper =
      capture(files, commit, %{
        "lib/hold_ledger/spec.ex" =>
          spec <> "\n# synthetic helper source edit, no semantic claim\n"
      })

    on_exit(fn ->
      Enum.each([base, proposal, helper], fn id ->
        File.rm_rf!(Path.join(Part3Snapshots.directory(), id))
      end)
    end)

    {:ok, baseline: base, proposal: proposal, helper: helper}
  end

  defp capture(files, commit, overrides) do
    source = Config.root()

    files = Enum.filter(files, &File.regular?(Path.join(Config.root(), &1)))

    readme = Map.get(overrides, "README.md", File.read!(Path.join(source, "README.md")))

    overrides =
      Map.put(overrides, "README.md", readme <> "\n<!-- isolated test VM #{System.pid()} -->\n")

    manifest =
      Map.new(files, fn path ->
        content = Map.get(overrides, path, File.read!(Path.join(source, path)))
        {path, :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)}
      end)

    identity = %{
      "schema_version" => 1,
      "commit" => commit,
      "dirty" => true,
      "manifest" => manifest
    }

    id = Canonical.digest(identity)
    dest = Path.join(Part3Snapshots.directory(), id)
    File.mkdir_p!(dest)

    Enum.each(files, fn path ->
      target = Path.join(dest, path)
      File.mkdir_p!(Path.dirname(target))
      File.write!(target, Map.get(overrides, path, File.read!(Path.join(source, path))))
    end)

    File.write!(
      Path.join(dest, ".part3-snapshot.json"),
      Canonical.json(Map.put(identity, "snapshot_id", id)) <> "\n"
    )

    id
  end

  defp fresh_id, do: Base.url_encode64(:crypto.strong_rand_bytes(18), padding: false)

  setup %{baseline: a, proposal: b} do
    dir = Path.join(System.tmp_dir!(), "part3-store-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, store} = start_supervised({Part3Store, name: nil, dir: dir})
    {:ok, p} = Part3Store.create(a, b, store)
    {:ok, package: p, store: store}
  end

  # Synthetic *projection* fixtures: no worker or checker run is claimed here.
  defp evidence_package(p, witness, kind) do
    binding = %{
      "binding_id" => Canonical.digest(%{"key" => 3}),
      "values" => %{"key" => 3},
      "requires" => true,
      "post_candidate" => false,
      "post_actual" => true
    }

    a = %{
      "evaluation" => %{"actual" => %{"result" => "admitted"}},
      "claims" => %{"po_a2" => %{"bindings" => [binding]}}
    }

    b =
      case kind do
        "lost_domain_input" ->
          put_in(a, ["claims", "po_a2", "bindings"], [%{binding | "requires" => false}])

        "observed_behavioral_difference" ->
          put_in(a, ["evaluation", "actual", "result"], "insufficient_amount")

        "permitted_alternative_output" ->
          put_in(a, ["claims", "po_a2", "bindings"], [
            %{binding | "post_candidate" => true}
          ])
      end

    [e] = Part3Diagnostics.compare(p, witness, a, b)
    Map.put(p, "evidence", [e])
  end

  defp synthetic_receipt(p, witness, side) do
    sid = p[side]["snapshot_id"]
    now = Part3Package.now()

    %{
      "id" => fresh_id(),
      "kind" => "replay",
      "snapshot_id" => sid,
      "context_digest" => p["context_digest"],
      "scope" => "controlled_projection_only",
      "status" => "succeeded",
      "producer" => "controlled_fixture_not_actual_worker_evidence",
      "queued_at" => now,
      "started_at" => now,
      "finished_at" => now,
      "input_digest" => Canonical.digest(witness),
      "completion_digest" => String.duplicate("b", 64),
      "artifacts" => [],
      "diagnostics" => "",
      "dependencies" => [],
      "witness" => witness,
      "result" => %{
        "completion_digest" => String.duplicate("b", 64),
        "evaluation" => %{"actual" => %{"result" => "admitted"}}
      }
    }
  end

  test "strict versioned package survives JSON round trip, rejects unknown shape and shifted context",
       ctx do
    p = ctx.package
    assert Part3Package.valid?(p, p["id"])
    assert p == Jason.decode!(Jason.encode!(p))
    assert not Part3Package.valid?(Map.put(p, "legacy_approval", true), p["id"])

    assert not Part3Package.valid?(
             Map.put(p, "context_digest", String.duplicate("0", 64)),
             p["id"]
           )

    assert p["baseline"]["snapshot_id"] == ctx.baseline
    assert p["proposal"]["snapshot_id"] == ctx.proposal

    assert hd(p["policy_anchors"])["sha256"] ==
             p["baseline"]["manifest"]["guides/specification.md"]
  end

  test "source comparison includes helper changes without inventing a semantic theorem", ctx do
    {:ok, baseline} = Part3Snapshots.load(ctx.baseline)
    {:ok, helper} = Part3Snapshots.load(ctx.helper)
    assert {:ok, changes} = Part3ContractDelta.compare(baseline, helper)

    assert Enum.any?(changes, fn c ->
             c["path"] == "lib/hold_ledger/spec.ex" and
               c["kind"] == "called_definition_or_behavior" and
               c["semantic_relation"] == "unresolved" and c["evidence_level"] == "structural_edit"
           end)

    assert Part3Snapshots.compatible?(baseline, helper)

    assert {:error, :identical_snapshot} =
             Part3Package.new(fresh_id(), ctx.baseline, ctx.baseline)
  end

  test "separate concrete lost-domain, alternative and actual behavioral distinctions", ctx do
    {:ok, witness} = Adversarial.seed("P04")
    bound = %{"key" => 3}

    binding = %{
      "binding_id" => Canonical.digest(bound),
      "values" => bound,
      "post_actual" => true,
      "requires" => true,
      "post_candidate" => false
    }

    a = %{
      "evaluation" => %{"actual" => %{"result" => "admitted"}},
      "claims" => %{"po_a2" => %{"bindings" => [binding]}}
    }

    b = put_in(a, ["claims", "po_a2", "bindings"], [%{binding | "requires" => false}])
    assert [lost] = Part3Diagnostics.compare(ctx.package, witness, a, b)
    assert lost["kind"] == "lost_domain_input"
    assert lost["note"] =~ "Pre_A"
    b = put_in(a, ["claims", "po_a2", "bindings"], [%{binding | "post_candidate" => true}])
    assert [permitted] = Part3Diagnostics.compare(ctx.package, witness, a, b)
    assert permitted["kind"] == "permitted_alternative_output"
    assert permitted["output"] == witness["output"]
    changed = put_in(a, ["evaluation", "actual"], %{"result" => "declined"})
    assert [difference] = Part3Diagnostics.compare(ctx.package, witness, a, changed)
    assert difference["kind"] == "observed_behavioral_difference"
    assert [] == Part3Diagnostics.compare(ctx.package, witness, a, a)
  end

  test "change-directed boundary search stays bounded and does not claim semantic approval",
       ctx do
    {:ok, witness} = Adversarial.seed("P04")
    cases = Part3BoundarySearch.cases(ctx.package, witness)
    assert cases == []
    {:ok, helper_package} = Part3Package.new(fresh_id(), ctx.baseline, ctx.helper)
    values = Part3BoundarySearch.cases(helper_package, witness)
    assert length(values) in 30..48
    assert Enum.all?(values, &(&1["method"] =~ "not state-space coverage"))

    assert Enum.all?(values, fn v ->
             match?({:ok, _}, Adversarial.decode(v["witness"])) and
               v["witness"]["event"]["amount"] == v["requested_amount"]
           end)
  end

  test "pinning refuses an invalid starting state", ctx do
    {:ok, witness} = Adversarial.seed("P04")
    invalid_before = put_in(witness, ["before", "used_amount"], 999)

    assert {:error, :invalid_or_stale_pin} =
             Part3Store.pin(ctx.package["id"], invalid_before, ctx.store)
  end

  test "pinning is deliberate and idempotent, independent of run and answer", ctx do
    {:ok, witness} = Adversarial.seed("P04")
    assert {:ok, saved, pin} = Part3Store.pin(ctx.package["id"], witness, ctx.store)
    assert saved["pinned_examples"] == [pin]
    assert saved["replay_attempts"] == []
    assert saved["human_findings"] == []
    assert {:ok, again, ^pin} = Part3Store.pin(ctx.package["id"], witness, ctx.store)
    assert saved == again
  end

  test "human CAS, retained findings, and completion-digest idempotency", ctx do
    p = ctx.package

    first = %{
      "request_id" => fresh_id(),
      "expected_human_revision" => 0,
      "lens" => "reading",
      "status" => "unresolved",
      "scope" => "README change only",
      "rationale" => "Policy comparison still requires a human reading.",
      "evidence_ids" => [],
      "change_ids" => [],
      "presentation" => "expert",
      "revealed_before_answer" => true
    }

    assert {:ok, updated} = Part3Store.finding(p["id"], first, ctx.store)
    assert updated["human_revision"] == 1
    assert {:ok, ^updated} = Part3Store.finding(p["id"], first, ctx.store)

    assert {:error, :human_revision_conflict_or_closed} =
             Part3Store.finding(p["id"], %{first | "request_id" => fresh_id()}, ctx.store)

    assert {:error, :request_id_conflict} =
             Part3Store.finding(p["id"], %{first | "rationale" => "Changed rationale"}, ctx.store)

    assert {:ok, ^updated, :ok} = Part3Store.get(p["id"], ctx.store)
  end

  test "runner accepts no forged identity, terminal or partial report as proof", ctx do
    p = ctx.package
    {:ok, witness} = Adversarial.seed("P04")
    assert {:ok, _, [one, two]} = Part3Store.queue_replay(p["id"], witness, ctx.store)
    assert {:ok, _} = Part3Store.running(p["id"], one["id"], ctx.store)

    assert {:error, :invalid_or_forged_replay_result} =
             Part3Result.validate(%{"request_id" => one["id"]}, p, one, witness)

    assert {:error, :invalid_or_late_replay_completion} =
             Part3Store.complete_replay(
               p["id"],
               one["id"],
               %{"request_id" => one["id"]},
               ctx.store
             )

    assert {:ok, _} = Part3Store.fail_attempt(p["id"], one["id"], :timeout, ctx.store)

    assert {:error, :late_or_terminal_completion} =
             Part3Store.complete_replay(p["id"], one["id"], %{}, ctx.store)

    assert {:ok, _} = Part3Store.fail_attempt(p["id"], two["id"], :cancelled, ctx.store)

    assert {:error, :attempt_unavailable_or_stale} =
             Part3Store.fail_attempt(p["id"], two["id"], :timeout, ctx.store)

    assert {:error, :missing_stale_or_invalid_verification_report} =
             Part3Verification.inspect_report(
               ctx.proposal,
               "tmp/verification/part3-does-not-exist/checked.json"
             )
  end

  test "search covers statuses, identities, wrong outputs and two-event histories", ctx do
    {:ok, p} = Part3Package.new(fresh_id(), ctx.baseline, ctx.helper)
    {:ok, witness} = Adversarial.seed("P04")
    cases = Part3BoundarySearch.cases(p, witness)

    assert Enum.all?(cases, fn item ->
             {:ok, decoded} = Adversarial.decode(item["witness"])
             HoldLedger.Spec.valid?(decoded.before)
           end)

    assert MapSet.new(
             Enum.flat_map(
               cases,
               &Enum.map(&1["witness"]["before"]["entries"], fn e -> e["status"] end)
             )
           ) == MapSet.new(HoldLedgerReview.TermCodec.statuses())

    assert Enum.any?(cases, &(&1["witness"]["follow_on"] != nil))
    assert Enum.any?(cases, &String.contains?(&1["label"], "frame"))
    assert Enum.any?(cases, &String.contains?(&1["label"], "effects"))
    assert Enum.any?(cases, &String.contains?(&1["label"], "identity"))
    assert Part3BoundarySearch.limits()["general_relation"] == "unresolved"
    changed = put_in(p, ["proposal", "codec_id"], String.duplicate("0", 64))

    assert {:error, :unsupported_representation_or_evaluator_mapping} =
             Part3ContractDelta.compare(changed["baseline"], changed["proposal"])
  end

  test "partial, failed and offline artifacts retain provenance without asserting acceptance",
       ctx do
    sid = ctx.proposal
    root = Part3Snapshots.root(sid)
    prefix = "tmp/verification/part3-intake-fixture"
    File.mkdir_p!(Path.join(root, prefix))
    artifact_path = prefix <> "/translation.lean"
    bytes = "-- controlled translation fixture, no proof executed\n"
    File.write!(Path.join(root, artifact_path), bytes)

    artifact = %{
      "path" => artifact_path,
      "sha256" => HoldLedgerReview.Anchor.sha(bytes),
      "bytes" => byte_size(bytes),
      "kind" => "translated_statement",
      "slug" => "po_a2"
    }

    index = %{
      "schema_version" => 1,
      "snapshot_id" => sid,
      "source_manifest_digest" => Canonical.digest(ctx.package["proposal"]["manifest"]),
      "requested_scope" => "full_required_catalog",
      "producer" => "controlled offline fixture (not a checker)",
      "report" => nil,
      "artifacts" => [artifact]
    }

    relative = prefix <> "/artifact-index.json"
    File.write!(Path.join(root, relative), Canonical.json(index))
    assert {:ok, first} = Part3Store.ingest_artifacts(ctx.package["id"], relative, ctx.store)
    assert {:ok, ^first} = Part3Store.ingest_artifacts(ctx.package["id"], relative, ctx.store)
    assert {:ok, inspected} = HoldLedgerReview.Part3ProofInspector.inspect(first)
    assert inspected["formal_acceptance"] == "not_run"
    assert length(inspected["artifacts"]) == 2
    assert Enum.all?(inspected["artifacts"], &(&1["status"] == "present"))
    translation = Enum.find(inspected["artifacts"], &(&1["path"] == artifact_path))
    assert translation["kind"] == "translated_statement"
    assert translation["slug"] == "po_a2"

    assert Enum.find(inspected["sources"], &(&1["slug"] == "po_a2"))["lean_declarations"] == [
             translation
           ]

    assert Enum.find(inspected["sources"], &(&1["slug"] == "po_a2"))["translated_statement"] ==
             nil

    report = %{
      "mode" => "EXECUTED",
      "stage" => "full",
      "laws" => %{"po_a2" => %{"passed" => false}},
      "source_sha256" => HoldLedgerReview.ProofEvidence.manifest(root),
      "source_changes_during_run" => [],
      "complete" => false
    }

    report_path = prefix <> "/checked.json"
    raw = Canonical.json(report)
    File.write!(Path.join(root, report_path), raw)

    index =
      Map.put(index, "report", %{
        "path" => report_path,
        "sha256" => HoldLedgerReview.Anchor.sha(raw),
        "bytes" => byte_size(raw)
      })

    File.write!(Path.join(root, relative), Canonical.json(index))
    assert {:ok, second} = Part3Store.ingest_artifacts(ctx.package["id"], relative, ctx.store)
    assert length(second["verification_attempts"]) == 2
    assert {:ok, inspected} = HoldLedgerReview.Part3ProofInspector.inspect(second)
    assert inspected["formal_acceptance"] == "incomplete"
    # A newer recorded report whose bytes drift must not expose an older
    # report as if it were the latest accepted formal evidence.
    File.write!(Path.join(root, report_path), raw <> "\n")
    assert {:ok, drifted} = Part3ProofInspector.inspect(second)
    assert drifted["formal_acceptance"] == "stale_or_missing_report"
    assert drifted["sources"] |> Enum.all?(&(&1["exports"] == []))
    File.write!(Path.join(root, report_path), raw)
    File.rm!(Path.join(root, artifact_path))
    assert {:ok, missing} = HoldLedgerReview.Part3ProofInspector.inspect(second)
    assert Enum.find(missing["artifacts"], &(&1["path"] == artifact_path))["status"] == "missing"
    assert Enum.find(missing["artifacts"], &(&1["path"] == report_path))["status"] == "present"
    index_versions = Enum.filter(missing["artifacts"], &(&1["path"] == relative))
    assert Enum.sort(Enum.map(index_versions, & &1["status"])) == ["present", "stale"]

    assert {:error, :artifact_intake_refused} =
             Part3Store.ingest_artifacts(ctx.package["id"], relative, ctx.store)

    assert ctx.package["conclusion"] == nil
  end

  test "snapshot rejects added source, dependency and loaded-analysis drift", ctx do
    path = Path.join(Part3Snapshots.root(ctx.helper), "unmanifested.ex")
    File.write!(path, "# controlled extra source")
    assert {:error, :invalid_or_stale_snapshot} = Part3Snapshots.load(ctx.helper)
    File.rm!(path)
    assert {:ok, snapshot} = Part3Snapshots.load(ctx.helper)
    assert Part3Snapshots.trusted_analysis?(snapshot)

    changed =
      put_in(
        snapshot,
        ["manifest", "apps/review_web/lib/hold_ledger_review/part3_result.ex"],
        String.duplicate("0", 64)
      )

    refute Part3Snapshots.trusted_analysis?(changed)
    lock = Path.join(Part3Snapshots.root(ctx.helper), "mix.lock")
    original = File.read!(lock)
    File.write!(lock, original <> "\n")
    assert {:error, :invalid_or_stale_snapshot} = Part3Snapshots.load(ctx.helper)
    File.write!(lock, original)
  end

  test "removed archive routes cannot dispatch model requests", ctx do
    {:ok, p} = Part3Store.create(ctx.baseline, ctx.proposal)
    assert get(Phoenix.ConnTest.build_conn(), "/changes/" <> p["id"]).status == 404
    assert {:ok, unchanged, :ok} = Part3Store.get(p["id"])
    assert unchanged["human_findings"] == []
    assert unchanged["ai_history"] == []
  end

  test "source-verified normalized differences retain exact declaration span and changed helpers",
       ctx do
    source = Config.root()

    {paths, 0} =
      System.cmd("git", ["ls-files", "-z", "--cached", "--others", "--exclude-standard"],
        cd: source
      )

    files = String.split(paths, <<0>>, trim: true)
    commit = System.cmd("git", ["rev-parse", "HEAD"], cd: source) |> elem(0) |> String.trim()
    law_path = "test/laws/po_a2_test.exs"
    original = File.read!(Path.join(source, law_path))
    needle = "requires: Spec.request_eligible?(s, key, amount),"

    baseline_bytes =
      String.replace(
        original,
        needle,
        "requires: Spec.request_eligible?(s, key, amount) and amount <= elem(s, 0) - elem(s, 2),"
      )

    proposal_bytes = String.replace(baseline_bytes, "amount <= elem(s, 0)", "amount < elem(s, 0)")
    assert baseline_bytes != proposal_bytes
    a = capture(files, commit, %{law_path => baseline_bytes})
    b = capture(files, commit, %{law_path => proposal_bytes})

    on_exit(fn ->
      File.rm_rf!(Part3Snapshots.root(a))
      File.rm_rf!(Part3Snapshots.root(b))
    end)

    assert {:ok, p} = Part3Package.new(fresh_id(), a, b)
    [change] = Enum.filter(p["source_changes"], &(&1["path"] == law_path))
    assert change["claim"]["analysis"] == "supported_structural_ast"
    assert change["claim"]["changed"]["conditions"]
    assert {:ok, projection} = Part3ContractDelta.presentation(p)
    detail = projection[change["id"]]
    assert detail["status"] == "source_hash_matched_structural_only"
    assert Enum.map(detail["declarations"], & &1["side"]) == ~w(baseline proposal)
    assert Enum.all?(detail["declarations"], &is_integer(&1["start_line"]))
    [requires, _expects] = detail["expressions"]
    assert requires["status"] == "normalized_changed"
    assert Enum.any?(requires["baseline"], &(&1["kind"] == "del"))
    # <= -> < removes '='; it need not insert any character on the proposal.
    assert Enum.find(requires["baseline"], &(&1["kind"] == "del"))["text"] == "="

    assert Enum.map_join(requires["baseline"], & &1["text"]) ==
             change["claim"]["baseline"]["requires"]

    assert Enum.map_join(requires["proposal"], & &1["text"]) ==
             change["claim"]["proposal"]["requires"]

    assert requires["baseline"] != requires["proposal"]
    assert detail["baseline"]["start_line"] >= 1
    assert detail["proposal"]["start_line"] >= 1

    {:ok, helper} = Part3Snapshots.load(ctx.helper)
    {:ok, base} = Part3Snapshots.load(ctx.baseline)
    assert {:ok, helper_edits} = Part3ContractDelta.compare(base, helper)
    assert Enum.any?(helper_edits, &(&1["kind"] == "called_definition_or_behavior"))
  end

  test "evidence docket links only registered declarations and prepares strict human commands",
       ctx do
    {:ok, witness} = Adversarial.seed("P04")
    p = evidence_package(ctx.package, witness, "lost_domain_input")
    assert Part3Package.valid?(p, p["id"])
    [card] = Part3Docket.cards(p)
    assert card["kind"] == "lost_domain_input"
    assert card["correspondence"] == "no_directly_matched_changed_declaration"
    assert card["changes"] == []
    assert card["receipts"]["baseline"]["actual"] == nil
    assert card["latest"] == nil

    assert {:ok, cmd} =
             Part3Docket.decision(p, card["id"], "design", fresh_id(), 0, "expert", true)

    assert cmd["lens"] == "excluded_inputs"
    assert cmd["status"] == "unresolved"
    assert cmd["evidence_ids"] == [card["id"]]
    assert cmd["change_ids"] == []
    assert cmd["expected_human_revision"] == 0
    assert cmd["rationale"] =~ "Reviewer selected"

    assert {:ok, policy} =
             Part3Docket.decision(p, card["id"], "policy", fresh_id(), 0, "expert", true)

    assert policy["status"] == "unresolved"
    assert policy["rationale"] =~ "no policy change is authorized"

    assert {:ok, considered} =
             Part3Docket.decision(p, card["id"], "considered", fresh_id(), 0, "expert", true)

    assert considered["status"] == "addressed"
    assert considered["rationale"] =~ "not defect resolution"

    assert {:error, :unknown_or_unmatched_evidence} =
             Part3Docket.decision(p, fresh_id(), "design", fresh_id(), 0, "expert", true)

    assert {:error, :unsupported_human_action} =
             Part3Docket.decision(p, card["id"], "approve", fresh_id(), 0, "expert", true)

    # Store still refuses a constructed command whose evidence was not admitted
    # through its original worker-result path.
    assert {:error, :invalid_finding} = Part3Store.finding(p["id"], cmd, ctx.store)
    assert ctx.package["human_revision"] == 0
  end

  test "repair packets distinguish contract-only exclusion, candidate and actual output", ctx do
    {:ok, witness} = Adversarial.seed("P04")

    for kind <- ~w(lost_domain_input permitted_alternative_output observed_behavioral_difference) do
      p = evidence_package(ctx.package, witness, kind)

      p =
        Map.put(p, "replay_attempts", [
          synthetic_receipt(p, witness, "baseline"),
          synthetic_receipt(p, witness, "proposal")
        ])

      assert Part3Package.valid?(p, p["id"])
      [e] = p["evidence"]
      assert {:ok, packet} = Part3RepairPacket.build(p, e["id"], "2026-10-27T00:00:00Z")
      assert packet["content_sha256"] == Canonical.digest(packet["content"])
      distinction = packet["content"]["distinction"]
      assert distinction["kind"] == kind

      if kind == "observed_behavioral_difference" do
        assert distinction["baseline_claim_observations"] == nil
        assert distinction["proposal_claim_observations"] == nil
      end

      assert distinction["baseline_actual_output"]["result"] == "admitted"
      assert distinction["proposal_actual_output"]["result"] == "admitted"
      assert distinction["baseline_replay"]["status"] == "admitted_succeeded_replay"

      assert distinction["candidate_output_not_observed"] ==
               if(kind == "permitted_alternative_output", do: witness["output"], else: nil)

      assert packet["content"]["human"]["policy_change_authorized"] == false
      assert packet["content"]["package"]["human_revision"] == 0
      assert packet["content"]["formal"] |> length() == 2
      assert String.contains?(Part3RepairPacket.markdown(packet), "not instructions")
      assert Jason.decode!(Part3RepairPacket.json(packet)) == packet
      assert {:ok, next} = Part3RepairPacket.build(p, e["id"], "2026-10-28T00:00:00Z")
      assert next["content_sha256"] == packet["content_sha256"]
      refute next["generated_at_utc"] == packet["generated_at_utc"]

      assert {:error, :stale_invalid_or_unknown_repair_source} =
               Part3RepairPacket.build(p, fresh_id())

      assert {:error, :stale_invalid_or_unknown_repair_source} =
               Part3RepairPacket.build(
                 %{p | "context_digest" => String.duplicate("a", 64)},
                 e["id"]
               )
    end
  end

  test "original proof data stays independently scoped per snapshot, with missing still missing",
       ctx do
    assert {:ok, inspection} = Part3ProofInspector.inspect(ctx.package)
    assert Enum.map(inspection["versions"], & &1["side"]) == ~w(baseline proposal)
    assert Enum.all?(inspection["versions"], &(&1["formal_acceptance"] == "not_run"))
    assert Enum.all?(inspection["versions"], &(&1["report_reference"] == nil))
    assert Enum.all?(inspection["versions"], &(&1["catalog_count"] == 49))
    proposal = Enum.find(inspection["versions"], &(&1["side"] == "proposal"))
    po = Enum.find(proposal["sources"], &(&1["slug"] == "po_a2"))
    assert po["source"]["status"] == "source_hash_matched"
    assert po["translated_statement"] == nil
    assert po["proof_dependencies"] == nil
    assert po["exports"] == []
    assert po["lean_declarations"] == []
  end

  test "identified source and export routes refuse unknown paths and formats", ctx do
    {:ok, p} = Part3Store.create(ctx.baseline, ctx.proposal)
    [change] = p["source_changes"]
    prefix = "/comparisons/" <> p["id"]
    conn = get(Phoenix.ConnTest.build_conn(), prefix <> "/source/proposal/" <> change["id"])
    assert conn.status == 200

    assert conn.resp_body ==
             File.read!(Path.join(Part3Snapshots.root(ctx.proposal), change["path"]))

    assert Plug.Conn.get_resp_header(conn, "content-type") == ["text/plain; charset=utf-8"]

    for path <- [
          "/source/other/" <> change["id"],
          "/source/baseline/unknown",
          "/law/other/po_a2/source",
          "/law/baseline/unknown/source",
          "/artifact/other/" <> String.duplicate("0", 64),
          "/repair/unknown.json",
          "/repair/e-" <> String.duplicate("0", 32) <> ".html"
        ] do
      assert get(Phoenix.ConnTest.build_conn(), prefix <> path).status == 404
    end

    assert get(
             Phoenix.ConnTest.build_conn(),
             prefix <> "/repair/e-" <> String.duplicate("0", 32) <> ".json"
           ).status == 409

    assert {:ok, ^p, :ok} = Part3Store.get(p["id"])
  end

  test "replay updates keep a single subscription and artifact inspection stays responsive",
       ctx do
    {:ok, package} = Part3Store.create(ctx.baseline, ctx.proposal)
    {:ok, doc} = HoldLedgerReview.Contrast.create("po_a2")

    {:ok, doc} =
      HoldLedgerReview.Trace.command(
        doc["id"],
        doc["revision"],
        HoldLedgerReview.Trace.token(),
        %{"kind" => "comparison", "id" => package["id"]}
      )

    {:ok, view, _} = live(Phoenix.ConnTest.build_conn(), "/claims/po_a2/#{doc["id"]}")
    topic = "part3:" <> package["id"]
    assert [{pid, _}] = Registry.lookup(HoldLedgerReview.PubSub, topic)
    assert pid == view.pid
    send(view.pid, {:part3_updated, package["id"]})
    render(view)
    send(view.pid, {:part3_updated, package["id"]})
    render(view)
    assert [{^pid, _}] = Registry.lookup(HoldLedgerReview.PubSub, topic)
    render_click(view, "pair_proof", %{})
    assert has_element?(view, "#pair-proof-artifacts", "not_run_or_missing")
    assert has_element?(view, "#verdict")
    render_click(view, "show_sources", %{})

    form(view, "#compare-form", compare: %{baseline: ctx.baseline, proposal: ctx.proposal})
    |> render_submit()

    {:ok, changed} = HoldLedgerReview.Trace.get(doc["id"])
    assert changed["comparison"] != package["id"]
    assert Registry.lookup(HoldLedgerReview.PubSub, topic) == []

    assert [{^pid, _}] =
             Registry.lookup(HoldLedgerReview.PubSub, "part3:" <> changed["comparison"])
  end
end
