defmodule HoldLedgerReview.Part3Test do
  use ExUnit.Case, async: false
  alias HoldLedgerReview.{Adversarial, Canonical, Config, Part3AI, Part3ContractDelta,
    Part3BoundarySearch, Part3Diagnostics, Part3Editor, Part3Package, Part3Result, Part3Snapshots,
    Part3Store, Part3Verification}

  # A pair of content-addressed *disposable, synthetic* local snapshots; never
  # modifies the authoritative reducer, Spec, laws or policy in the checkout.
  # One fixture changes a non-evaluator file, another changes a helper source.
  setup_all do
    source = Config.root()
    {paths, 0} = System.cmd("git", ["ls-files", "-z", "--cached", "--others", "--exclude-standard"], cd: source)
    files = paths |> String.split(<<0>>, trim: true) |> Enum.sort()
    commit = System.cmd("git", ["rev-parse", "HEAD"], cd: source) |> elem(0) |> String.trim()
    base = capture(files, commit, %{})
    proposal = capture(files, commit, %{"README.md" => File.read!(Path.join(source, "README.md")) <> "\n<!-- disposable review fixture -->\n"})
    spec = File.read!(Path.join(source, "lib/hold_ledger/spec.ex"))
    helper = capture(files, commit, %{"lib/hold_ledger/spec.ex" => spec <> "\n# synthetic helper source edit, no semantic claim\n"})
    on_exit(fn ->
      Enum.each([base, proposal, helper], fn id ->
        File.rm_rf!(Path.join(Part3Snapshots.directory(), id))
      end)
    end)
    {:ok, baseline: base, proposal: proposal, helper: helper}
  end

  defp capture(files, commit, overrides) do
    source = Config.root()
    manifest = Map.new(files, fn path ->
      content = Map.get(overrides, path, File.read!(Path.join(source, path)))
      {path, :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)}
    end)
    identity = %{"schema_version" => 1, "commit" => commit, "dirty" => true, "manifest" => manifest}
    id = Canonical.digest(identity)
    dest = Path.join(Part3Snapshots.directory(), id)
    File.mkdir_p!(dest)
    Enum.each(files, fn path ->
      target = Path.join(dest, path)
      File.mkdir_p!(Path.dirname(target))
      File.write!(target, Map.get(overrides, path, File.read!(Path.join(source, path))))
    end)
    File.write!(Path.join(dest, ".part3-snapshot.json"), Canonical.json(Map.put(identity, "snapshot_id", id)) <> "\n")
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

  test "strict versioned package survives JSON round trip, rejects unknown shape and shifted context", ctx do
    p = ctx.package
    assert Part3Package.valid?(p, p["id"])
    assert p == Jason.decode!(Jason.encode!(p))
    assert not Part3Package.valid?(Map.put(p, "legacy_approval", true), p["id"])
    assert not Part3Package.valid?(Map.put(p, "context_digest", String.duplicate("0", 64)), p["id"])
    assert p["baseline"]["snapshot_id"] == ctx.baseline
    assert p["proposal"]["snapshot_id"] == ctx.proposal
    assert hd(p["policy_anchors"])["sha256"] == p["baseline"]["manifest"]["guides/specification.md"]
  end

  test "source comparison includes helper changes without inventing a semantic theorem", ctx do
    {:ok, baseline} = Part3Snapshots.load(ctx.baseline)
    {:ok, helper} = Part3Snapshots.load(ctx.helper)
    assert {:ok, changes} = Part3ContractDelta.compare(baseline, helper)
    assert Enum.any?(changes, fn c ->
      c["path"] == "lib/hold_ledger/spec.ex" and c["kind"] == "called_definition_or_behavior" and
        c["semantic_relation"] == "unresolved" and c["evidence_level"] == "structural_edit"
    end)
    assert Part3Snapshots.compatible?(baseline, helper)
    assert {:error, :identical_snapshot} = Part3Package.new(fresh_id(), ctx.baseline, ctx.baseline)
  end

  test "separate concrete lost-domain, alternative and actual behavioral distinctions", ctx do
    {:ok, witness} = Adversarial.seed("P04")
    bound = %{"key" => 3}
    binding = %{"binding_id" => Canonical.digest(bound), "values" => bound,
      "post_actual" => true, "requires" => true, "post_candidate" => false}
    a = %{"evaluation" => %{"actual" => %{"result" => "admitted"}},
      "claims" => %{"po_a2" => %{"bindings" => [binding]}}}
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

  test "change-directed boundary search stays bounded and does not claim semantic approval", ctx do
    {:ok, witness} = Adversarial.seed("P04")
    cases = Part3BoundarySearch.cases(ctx.package, witness)
    assert cases == []
    {:ok, helper_package} = Part3Package.new(fresh_id(), ctx.baseline, ctx.helper)
    values = Part3BoundarySearch.cases(helper_package, witness)
    assert length(values) <= 3
    assert Enum.all?(values, &(&1["method"] =~ "not state-space coverage"))
    assert Enum.all?(values, fn v ->
      match?({:ok, _}, Adversarial.decode(v["witness"])) and
        v["witness"]["event"]["amount"] == v["requested_amount"]
    end)
  end

  test "candidate counters remain wrong until explicit recalculation; valid starting input enforced", ctx do
    {:ok, witness} = Adversarial.seed("P04")
    assert {:ok, wrong} = Part3Editor.change(witness, %{"action" => "add_entry", "section" => "candidate"})
    assert wrong["output"]["after"]["used_amount"] == 0
    assert wrong["before"] == witness["before"]
    assert {:ok, _} = Adversarial.decode(wrong)
    assert {:ok, pinned, _} = Part3Store.pin(ctx.package["id"], wrong, ctx.store)
    assert is_map(pinned)
    assert {:ok, recalculated} = Part3Editor.change(wrong, %{"action" => "recalculate", "section" => "candidate"})
    assert recalculated["output"]["after"]["used_amount"] == 1
    assert recalculated["before"] == witness["before"]
    invalid_before = put_in(witness, ["before", "used_amount"], 999)
    assert {:error, :invalid_or_stale_pin} = Part3Store.pin(ctx.package["id"], invalid_before, ctx.store)
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
    first = %{"request_id" => fresh_id(), "expected_human_revision" => 0,
      "lens" => "reading", "status" => "unresolved", "scope" => "README change only",
      "rationale" => "Policy comparison still requires a human reading.",
      "evidence_ids" => [], "change_ids" => [], "presentation" => "expert", "revealed_before_answer" => true}
    assert {:ok, updated} = Part3Store.finding(p["id"], first, ctx.store)
    assert updated["human_revision"] == 1
    assert {:ok, ^updated} = Part3Store.finding(p["id"], first, ctx.store)
    assert {:error, :human_revision_conflict_or_closed} = Part3Store.finding(p["id"], %{first | "request_id" => fresh_id()}, ctx.store)
    assert {:error, :request_id_conflict} = Part3Store.finding(p["id"], %{first | "rationale" => "Changed rationale"}, ctx.store)
    assert {:ok, ^updated, :ok} = Part3Store.get(p["id"], ctx.store)
  end

  test "runner accepts no forged identity, terminal or partial report as proof", ctx do
    p = ctx.package
    {:ok, witness} = Adversarial.seed("P04")
    assert {:ok, _, [one, two]} = Part3Store.queue_replay(p["id"], witness, ctx.store)
    assert {:ok, _} = Part3Store.running(p["id"], one["id"], ctx.store)
    assert {:error, :invalid_or_forged_replay_result} = Part3Result.validate(%{"request_id" => one["id"]}, p, one, witness)
    assert {:error, :invalid_or_late_replay_completion} = Part3Store.complete_replay(p["id"], one["id"], %{"request_id" => one["id"]}, ctx.store)
    assert {:ok, _} = Part3Store.fail_attempt(p["id"], one["id"], :timeout, ctx.store)
    assert {:error, :invalid_or_late_replay_completion} = Part3Store.complete_replay(p["id"], one["id"], %{}, ctx.store)
    assert {:ok, _} = Part3Store.fail_attempt(p["id"], two["id"], :cancelled, ctx.store)
    assert {:error, :attempt_unavailable_or_stale} = Part3Store.fail_attempt(p["id"], two["id"], :timeout, ctx.store)
    assert {:error, :missing_stale_or_invalid_verification_report} =
      Part3Verification.inspect_report(ctx.proposal, "tmp/verification/part3-does-not-exist/checked.json")
  end

  test "model consent, source packet and typed suggestion remain separate from human answer", ctx do
    assert {:ok, packet} = Part3AI.prepare(ctx.package)
    assert packet.context_digest == ctx.package["context_digest"]
    assert :ok = Part3AI.fresh?(ctx.package, packet)
    assert {:error, :consent_required} = Part3AI.run(packet, false, complete: fn _, _ -> flunk("no send") end)
    assert {:error, :ai_unavailable} = Part3AI.run(packet, true, capability_check: fn _ -> false end)
    assert :ok = Part3AI.validate(%{"request_kind" => "part3_review", "context_digest" => packet.context_digest, "proposals" => []}, packet)
    assert {:error, :invalid_model_proposal} = Part3AI.validate(%{"request_kind" => "part3_review", "context_digest" => String.duplicate("0", 64), "proposals" => []}, packet)
    assert ctx.package["ai_history"] == []
    assert ctx.package["human_findings"] == []
  end
end
