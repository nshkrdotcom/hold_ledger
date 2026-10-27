defmodule HoldLedgerReview.Config do
  @moduledoc "Validated local checkout configuration."
  def root, do: Application.fetch_env!(:hold_ledger_review_web, :ledger_root)

  def validate! do
    root = Path.expand(root())

    unless Enum.all?(
             ["mix.exs", "lib/hold_ledger/ledger.ex", "guides/specification.md"],
             &File.regular?(Path.join(root, &1))
           ) do
      raise ArgumentError, "Review Studio ledger_root must point to a Hold Ledger checkout"
    end

    Application.put_env(:hold_ledger_review_web, :ledger_root, root)
    :ok
  end
end
