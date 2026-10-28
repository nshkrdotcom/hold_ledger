ExUnit.start()

review_store_dir = Application.fetch_env!(:hold_ledger_review_web, :review_store_dir)
ExUnit.after_suite(fn _results -> File.rm_rf!(review_store_dir) end)
