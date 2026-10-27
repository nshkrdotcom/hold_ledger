defmodule HoldLedgerReview.Config do
  @moduledoc "Validated local checkout configuration."
  @ledger_source HoldLedger.Ledger.module_info(:compile)[:source] |> to_string()
  @spec_source HoldLedger.Spec.module_info(:compile)[:source] |> to_string()
  @external_resource @ledger_source
  @external_resource @spec_source
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

  @doc "Builds the application-configured inference client without choosing an adapter."
  def configure_inference! do
    case Application.get_env(:hold_ledger_review_web, :inference_client) do
      %Inference.Client{} -> :ok
      nil -> install_inference_client!()
    end
  end

  defp install_inference_client! do
    options = Application.fetch_env!(:hold_ledger_review_web, :inference_client_options)
    model = Application.get_env(:hold_ledger_review_web, :inference_model, options[:model])
    defaults = Keyword.get(options, :defaults, [])

    effort =
      Application.get_env(
        :hold_ledger_review_web,
        :inference_reasoning_effort,
        defaults[:reasoning_effort]
      )

    options =
      options
      |> Keyword.put(:model, model)
      |> Keyword.put(:defaults, Keyword.put(defaults, :reasoning_effort, effort))

    client = Inference.Client.new!(options)
    Application.put_env(:hold_ledger_review_web, :inference_client, client)
    Application.put_env(:hold_ledger_review_web, :inference_model, client.model)
    :ok
  end

  def root, do: Application.fetch_env!(:hold_ledger_review_web, :ledger_root)

  def validate! do
    root = Path.expand(root())

    unless Enum.all?(
             ["mix.exs", "lib/hold_ledger/ledger.ex", "guides/specification.md"],
             &File.regular?(Path.join(root, &1))
           ) do
      raise ArgumentError, "Review Studio ledger_root must point to a Hold Ledger checkout"
    end

    unless source_matches?(root),
      do:
        raise(
          ArgumentError,
          "Review Studio source differs from compiled Ledger/Spec; recompile the companion against the intended checkout"
        )

    Application.put_env(:hold_ledger_review_web, :ledger_root, root)
    :ok
  end
end
