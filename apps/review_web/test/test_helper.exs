ExUnit.start()

review_store_dir = Application.fetch_env!(:hold_ledger_review_web, :review_store_dir)
ExUnit.after_suite(fn _results -> File.rm_rf!(review_store_dir) end)

ExUnit.after_suite(fn _ ->
  File.rm_rf!(Application.fetch_env!(:hold_ledger_review_web, :question_store_dir))
end)

if formatter = System.get_env("HOLD_LEDGER_EXUNIT_FORMATTER") do
  Code.require_file(formatter)
  ExUnit.configure(formatters: [ExUnit.CLIFormatter, HoldLedger.ExUnitTiming])
end
