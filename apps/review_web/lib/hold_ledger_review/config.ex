defmodule HoldLedgerReview.Config do
  @moduledoc "Validated local checkout configuration."
  @build_root Path.expand("../../../..", __DIR__)
  @build_sources HoldLedgerReview.Claims.Source.support_sources()
  for relative <- @build_sources do
    @external_resource Path.join(@build_root, relative)
  end

  @build_hashes Map.new(@build_sources, fn relative ->
                  {relative, :crypto.hash(:sha256, File.read!(Path.join(@build_root, relative)))}
                end)
  @ledger_source HoldLedger.Ledger.module_info(:compile)[:source] |> to_string()
  @spec_source HoldLedger.Spec.module_info(:compile)[:source] |> to_string()
  @external_resource @ledger_source
  @external_resource @spec_source
  @compiled_modules Map.new([HoldLedger.Ledger, HoldLedger.Spec], fn module ->
                      {module, module.module_info(:md5)}
                    end)
  @compiled_hashes Map.new(
                     [
                       {"lib/hold_ledger/ledger.ex", @ledger_source},
                       {"lib/hold_ledger/spec.ex", @spec_source}
                     ],
                     fn {relative, path} ->
                       {relative, :crypto.hash(:sha256, File.read!(path))}
                     end
                   )
  def source_matches?(root) do
    Enum.all?(@compiled_hashes, fn {relative, hash} ->
      case File.read(Path.join(root, relative)) do
        {:ok, bytes} -> :crypto.hash(:sha256, bytes) == hash
        _ -> false
      end
    end)
  end

  def loaded_core_matches? do
    Enum.all?(@compiled_modules, fn {module, expected} ->
      module.module_info(:md5) == expected
    end)
  rescue
    _ -> false
  end

  # Unlike source_matches?/1, this also binds the evaluator implementation to
  # its build. Restarting with --no-compile cannot bless changed compiler bytes.
  def build_matches?(root) do
    Enum.all?(@build_hashes, fn {relative, expected} ->
      case HoldLedgerReview.Anchor.read_under(root, relative) do
        {:ok, bytes} -> :crypto.hash(:sha256, bytes) == expected
        _ -> false
      end
    end)
  end

  def root, do: Application.fetch_env!(:hold_ledger_review_web, :ledger_root)

  def validate! do
    root = Path.expand(root())

    unless Enum.all?(
             ["mix.exs", "lib/hold_ledger/ledger.ex", "guides/specification.md"],
             &File.regular?(Path.join(root, &1))
           ) do
      raise ArgumentError, "Claim Workbench ledger_root must point to a Hold Ledger checkout"
    end

    unless source_matches?(root),
      do:
        raise(
          ArgumentError,
          "Claim Workbench source differs from compiled Ledger/Spec; recompile the companion against the intended checkout"
        )

    Application.put_env(:hold_ledger_review_web, :ledger_root, root)
    :ok
  end
end
