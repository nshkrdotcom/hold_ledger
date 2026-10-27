defmodule HoldLedgerReview.Packet do
  @moduledoc "Builds a fixed record of the sources, computations and evidence for one review."
  alias HoldLedgerReview.{Anchor, Canonical, Cases, Config, Facts, ProofEvidence}

  def build(id, opts \\ []) do
    root = Keyword.get(opts, :root, Config.root())

    with {:ok, c} <- Cases.fetch(id),
         :ok <- if(Config.source_matches?(root), do: :ok, else: {:error, :compiled_source_drift}),
         {:ok, anchors} <- Anchor.build(root, c) do
      source_sha256 =
        ProofEvidence.manifest(root)
        |> Map.merge(
          Map.new(app_sources(root), fn path -> {path, ProofEvidence.digest_file(root, path)} end)
        )
        |> Map.merge(Map.new(anchors, fn {_, a} -> {a.path, a.sha256} end))

      proof =
        ProofEvidence.load(
          root,
          Keyword.get(opts, :report, Application.get_env(:hold_ledger_review_web, :proof_report)),
          Enum.map(c.laws, &elem(&1, 0))
        )

      {head, _} = System.cmd("git", ["rev-parse", "HEAD"], cd: root, stderr_to_stdout: true)
      {dirty, _} = System.cmd("git", ["status", "--porcelain"], cd: root, stderr_to_stdout: true)

      packet = %{
        schema_version: 1,
        case: c,
        facts: Facts.build(c),
        anchors: anchors,
        source_sha256: source_sha256,
        git_head: String.trim(head),
        dirty?: dirty != "",
        proof: proof
      }

      {:ok, Map.put(packet, :packet_sha256, Canonical.digest(packet))}
    end
  end

  def current?(p, root \\ Config.root()) do
    Enum.all?(p.source_sha256, fn {path, sha} -> ProofEvidence.digest_file(root, path) == sha end) and
      Enum.all?(
        ProofEvidence.sources(root) ++ app_sources(root),
        &Map.has_key?(p.source_sha256, &1)
      ) and proof_current?(p, root)
  end

  defp app_sources(root),
    do:
      Enum.flat_map(
        ["apps/review_web/lib/**/*.ex", "apps/review_web/priv/prompts/*.md"],
        &Path.wildcard(Path.join(root, &1))
      )
      |> Enum.map(&Path.relative_to(&1, root))

  defp proof_current?(%{proof: %{report: nil}}, _root), do: true

  defp proof_current?(p, root) do
    fresh = ProofEvidence.load(root, p.proof.detail, Enum.map(p.case.laws, &elem(&1, 0)))
    fresh.status == p.proof.status and fresh[:report_sha256] == p.proof[:report_sha256]
  end

  def evidence_ids(p),
    do:
      Map.keys(p.anchors) ++
        Enum.map(Map.keys(p.facts.candidates), &(p.case.id <> ".candidate." <> &1))
end
