defmodule HoldLedgerReview.ClaimsTest do
  use ExUnit.Case, async: false
  alias HoldLedgerReview.{Claims, ClaimProbe, Config, TermCodec}
  alias HoldLedgerReview.Claims.{Compiler, Source}

  @fixture_dir Path.expand("../fixtures/claims", __DIR__)

  test "complete registered DSL/native inventory and evaluated generation are source-bound" do
    root = Config.root()
    assert {:ok, source} = Source.snapshot(root)
    assert length(source.catalog) == 49
    assert length(source.law_files) == 35
    assert Enum.count(source.catalog, &(&1["kind"] == "lean")) == 14
    assert :ok = Claims.freshness(root)
    generation = Claims.snapshot()
    assert generation.status == :ready
    assert generation.source.sha256 == source.sha256
    assert generation.module.claim_manifest_sha256() == source.sha256
    assert generation.module.compiler_version() == Source.version()
    expected_identity = generation.generated_identity
    assert {:ok, ^expected_identity} = Claims.generated_identity(generation.module)
    assert {:ok, _} = Claims.loaded_fingerprint()
    assert {:error, :outside_initial_probe_scope} = Claims.claim("l3_accounting")
    assert {:error, :native_lean_obligation} = Claims.claim("po_exposure_history")
    assert {:error, :unknown_law} = Claims.claim("invented_policy")
  end

  test "source extraction, exact call multiplicity and compiled actual/candidate divergence" do
    root = Config.root()

    for {slug, sites} <- [{"po_b3", 3}, {"po_b2", 3}, {"po_a2", 2},
                           {"po_exposure_retain", 1}, {"po_b1_void", 1},
                           {"po_b1_timeout", 1}, {"po_s", 1}] do
      assert {:ok, claim} = Claims.claim(slug)
      assert claim.occurrence_count == sites
      assert claim.residual_target_count == 0
      assert claim.source_sha256 == source_hash(root, claim.source_file)
      assert Macro.to_string(claim.normalized_expects) != Macro.to_string(claim.substituted_expects)
      assert claim.source_text != ""
      assert {:ok, parsed} = Source.declaration(root, law_record(slug))
      assert parsed.formals == claim.formals
      assert Macro.to_string(parsed.expects) == Macro.to_string(claim.expects)
    end

    {before, event, output, _} = fixture("P04")
    assert {:ok, claim} = Claims.claim("po_a2")
    assert claim.formals == [:s, :key, :amount]
    assert {:ok, checks} = Claims.evaluate("po_a2", [before, 11, 100], output)
    assert checks.requires == true
    assert checks.actual == true
    assert checks.candidate == false
  end

  test "expected pointwise P01-P08 cells run through compiled original expressions" do
    expectations = load("expected_pointwise.json")["scenarios"]

    for {id, claims} <- expectations do
      {before, event, output, follow_on} = fixture(id)

      for {slug, expected} <- claims do
        row = ClaimProbe.probe(slug, before, event, output)
        status = if(expected == "does_not_apply", do: :doesnt_apply, else: String.to_existing_atom(expected))
        assert row.status == status, "#{id}/#{slug}: #{inspect(row)}"
        assert row.exhaustive_for_source_domain
        assert row.evaluator_id == Claims.snapshot().evaluator_id
        assert Enum.all?(row.rows, &(&1[:requires] in [true, false]))
        refute Enum.any?(row.rows, &(&1[:source_actual_expects] == false))
      end

      actual = HoldLedger.Ledger.step(before, event)
      follow = ClaimProbe.follow_on(actual, output, follow_on)

      if is_nil(follow_on) do
        assert follow.actual == nil and follow.candidate == nil
        assert follow.reason == :no_follow_on_event
      else
        assert follow.actual != nil
      end
    end
  end

  test "cross-key retained entries are all bound from the source lookup, not event fields" do
    {before, event, output, _} = fixture("P07")
    row = ClaimProbe.probe("po_exposure_retain", before, event, output)
    assert row.status == :catches
    assert row.exhaustive_for_source_domain
    assert row.bindings_tested == 2
    assert Enum.sort(Enum.map(row.rows, & &1.actual_binding_values["key"])) == [1, 2]
    assert Enum.all?(row.rows, &(&1.actual_binding_values["event"]["type"] == "timeout"))
    assert Enum.all?(row.rows, &(&1.binding_origin["amount"].kind == :existing_entry))
    assert Enum.any?(row.rows, &(&1.actual_binding_values["key"] != elem(event, 1) and
                                 &1.substituted_expects == false))

    truncated = ClaimProbe.probe("po_exposure_retain", before, event, output, binding_limit: 1)
    assert truncated.status == :cant_check
    assert truncated.reason == :truncated_binding_domain
  end

  test "new request amount and existing original are separate, including duplicate equality" do
    vector = load("edge_case_vectors.json")["binder_cases"]
    conflict = Enum.find(vector, &(&1["law"] == "po_a4_conflict"))
    duplicate = Enum.find(vector, &(&1["law"] == "po_a4_duplicate"))

    for {v, slug, expected} <- [{conflict, "po_a4_conflict", :allows_here},
                                 {duplicate, "po_a4_duplicate", :allows_here}] do
      {:ok, before} = TermCodec.decode_state(v["before"])
      {:ok, event} = TermCodec.decode_event(v["event"])
      output = HoldLedger.Ledger.step(before, event)
      row = ClaimProbe.probe(slug, before, event, output)
      assert row.status == expected
      assert row.bindings_tested == 1
      assert hd(row.rows).requires == true
      assert hd(row.rows).actual_binding_values["amount"] == elem(event, 2)
      assert hd(row.rows).binding_origin["amount"].kind in
               [:request_field, :event_field_and_existing_entry]

      if slug == "po_a4_conflict" do
        assert hd(row.rows).actual_binding_values["original"] == 50
        assert hd(row.rows).binding_origin["original"].field == :amount
        assert hd(row.rows).actual_binding_values["amount"] == 60
      end
    end

    {:ok, before} = TermCodec.decode_state(conflict["before"])
    output = HoldLedger.Ledger.step(before, {:request, 1, 60})
    assert ClaimProbe.probe("po_a4_duplicate", before, {:request, 1, 60}, output).status == :doesnt_apply
    assert ClaimProbe.probe("po_a4_conflict", before, {:request, 1, 50},
             HoldLedger.Ledger.step(before, {:request, 1, 50})).status == :doesnt_apply
  end

  test "po_b2 scans existing unknown entries, not arbitrary sent entries or event key" do
    {sent_before, event, candidate, _} = fixture("P06")
    row = ClaimProbe.probe("po_b2", sent_before, event, candidate)
    assert row.status == :doesnt_apply
    assert row.bindings_tested == 0

    before = {250, 3, 150, 2, [{1, 50, :unknown}, {2, 100, :sent}]}
    output = HoldLedger.Ledger.step(before, {:timeout, 2})
    unknown = ClaimProbe.probe("po_b2", before, {:timeout, 2}, output)
    assert unknown.status == :allows_here
    assert unknown.bindings_tested == 1
    assert hd(unknown.rows).actual_binding_values["key"] == 1
    assert hd(unknown.rows).binding_origin["key"].field == :key
  end

  test "unsupported aliases/AST, no reducer and non-equivalent calls fail closed" do
    {:ok, law} = Claims.claim("po_b3")
    assert {:error, :unresolved_alias} = Compiler.prepare(%{law | aliases: []})
    assert {:error, :unsupported_ast} = Compiler.prepare(%{law | expects: quote(do: System.cmd("sh", []))})
    assert {:error, :no_target_reducer_call} = Compiler.prepare(%{law | expects: quote(do: Spec.valid?(s))})

    assert {:error, :non_equivalent_reducer_calls} =
             Compiler.prepare(%{law | expects: quote(do: Ledger.step(s, event) == Ledger.void(s, 1))})

    {:ok, request_law} = Claims.claim("po_a2")
    assert {:error, :unsupported_call_signature} =
             Compiler.prepare(%{request_law | expects: quote(do: Ledger.request(s, amount, key) == {s, :admitted, []})})

    assert {:error, :unsupported_ast} =
             Compiler.prepare(%{law | expects: quote(do: apply(Ledger, :step, [s, event]))})

    assert ClaimProbe.probe("po_a2", elem(fixture("P01"), 0), {:void, 1}, elem(fixture("P01"), 2)).status == :not_probed
  end

  test "law edits, inventory additions/deletions and catalog changes invalidate the independent manifest" do
    tmp = cloned_sources()
    assert :ok = Claims.freshness(tmp)
    assert Config.source_matches?(tmp)
    source = Path.join(tmp, "test/laws/po_b1_void_test.exs")
    original = File.read!(source)
    File.write!(source, original <> "\n# trusted law edit\n")
    assert Config.source_matches?(tmp)
    assert {:error, :source_or_compiled_code_drift} = Claims.freshness(tmp)
    File.write!(source, original)
    assert :ok = Claims.freshness(tmp)

    added = Path.join(tmp, "test/laws/injected_test.exs")
    File.write!(added, "# unexpected source")
    assert {:error, :source_or_compiled_code_drift} = Claims.freshness(tmp)
    File.rm!(added)
    assert :ok = Claims.freshness(tmp)

    other_added = Path.join(tmp, "test/laws/unregistered.exs")
    File.write!(other_added, "# not named as a test")
    assert {:error, :source_or_compiled_code_drift} = Claims.freshness(tmp)
    File.rm!(other_added)
    assert :ok = Claims.freshness(tmp)

    File.rm!(source)
    assert {:error, :source_or_compiled_code_drift} = Claims.freshness(tmp)
    File.write!(source, original)
    assert :ok = Claims.freshness(tmp)

    compiler = Path.join(tmp, "apps/review_web/lib/hold_ledger_review/claims/compiler.ex")
    File.write!(compiler, File.read!(compiler) <> "\n# compiled dependency edit\n")
    assert {:error, :source_or_compiled_code_drift} = Claims.freshness(tmp)
    File.cp!(Path.join(Config.root(), "apps/review_web/lib/hold_ledger_review/claims/compiler.ex"), compiler)
    assert :ok = Claims.freshness(tmp)

    catalog = Path.join(tmp, "verification/laws.json")
    File.write!(catalog, File.read!(catalog) <> "\n")
    assert {:error, :source_or_compiled_code_drift} = Claims.freshness(tmp)
  end

  test "drift during the evaluation invalidates the result, even if the source actual passed" do
    tmp = cloned_sources()
    source = Path.join(tmp, "test/laws/po_b1_void_test.exs")
    {before, event, candidate, _} = fixture("P01")

    assert :ok = Claims.freshness(tmp)
    row =
      ClaimProbe.probe("po_b1_void", before, event, candidate,
        root: tmp,
        before_finish: fn -> File.write!(source, File.read!(source) <> "\n# changed in flight") end)

    assert row.status == :cant_check
    assert row.reason == :source_or_compiled_code_drift
  end

  test "invalid or out-of-range native inputs fail before any reducer invocation" do
    {before, event, output, _} = fixture("P01")
    assert ClaimProbe.probe("po_b3", before, {:request, 1, -3}, output).status == :cant_check
    assert ClaimProbe.probe("po_b3", before, event, {elem(output, 0), :arbitrary, []}).status == :cant_check
    assert ClaimProbe.probe("po_b3", {100, 2, 0, 0, [{1, -5, :sent}]}, event, output).status == :cant_check
    assert ClaimProbe.probe("po_b3", before, event, output, binding_limit: 0).status == :cant_check
  end

  test "concurrent readers share the one immutable evaluator generation" do
    {before, event, output, _} = fixture("P05")
    tasks = for _ <- 1..12, do: Task.async(fn -> ClaimProbe.probe("po_b3", before, event, output) end)
    rows = Enum.map(tasks, &Task.await(&1, 15_000))
    assert Enum.all?(rows, &(&1.status == :catches))
    assert rows |> Enum.map(& &1.evaluator_id) |> Enum.uniq() |> length() == 1
  end

  defp source_hash(root, path) do
    root |> Path.join(path) |> File.read!() |> HoldLedgerReview.Anchor.sha()
  end

  defp law_record(slug) do
    {:ok, catalog} = Claims.catalog()
    Enum.find(catalog, &(&1["slug"] == slug))
  end

  defp fixture(id) do
    f = load(id <> ".json")
    {:ok, before} = TermCodec.decode_state(f["before"])
    {:ok, event} = TermCodec.decode_event(f["event"])
    {:ok, output} = TermCodec.decode_output(f["output"])
    follow = if f["follow_on"], do: elem(TermCodec.decode_event(f["follow_on"]), 1), else: nil
    {before, event, output, follow}
  end

  defp load(name), do: @fixture_dir |> Path.join(name) |> File.read!() |> Jason.decode!()

  defp cloned_sources do
    original = Config.root()
    path = Path.join(System.tmp_dir!(), "claims-fixture-#{System.unique_integer([:positive])}")
    File.mkdir_p!(path)
    on_exit(fn -> File.rm_rf!(path) end)
    {:ok, manifest} = Source.snapshot(original)

    for relative <- Map.keys(manifest.file_sha256) ++ ["verification/laws.json", "verification/obligations.json"] do
      target = Path.join(path, relative)
      File.mkdir_p!(Path.dirname(target))
      File.cp!(Path.join(original, relative), target)
    end

    path
  end
end
