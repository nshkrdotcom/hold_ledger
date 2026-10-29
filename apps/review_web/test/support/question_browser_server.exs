# Explicit controlled browser fixture. No provider is contacted.
# MIX_ENV=test uv run --locked python scripts/local_run.py --cwd apps/review_web \
#   mix run --no-start --no-halt test/support/question_browser_server.exs
alias HoldLedgerReview.{AI, Config}
root = Config.root()

Application.put_env(
  :hold_ledger_review_web,
  :question_store_dir,
  Path.join(root, "tmp/acceptance_0752/controlled-questions")
)

Application.put_env(
  :hold_ledger_review_web,
  :review_store_dir,
  Path.join(root, "tmp/acceptance_0752/controlled-traces")
)

Application.put_env(
  :hold_ledger_review_web,
  :part3_store_dir,
  Path.join(root, "tmp/acceptance_0752/controlled-packages")
)

Application.put_env(:hold_ledger_review_web, :question_runner, fn packet ->
  complete = fn client, _request ->
    cond do
      String.contains?(packet["question"], "[wait]") ->
        receive do
          :release -> {:error, :controlled_release}
        end

      String.contains?(packet["question"], "[fail]") ->
        {:error, :controlled_unavailable}

      true ->
        {:ok,
         Inference.Response.new(%{
           model: client.model,
           provider: :codex,
           object: %{
             "summary" => "Controlled fixture: the rule covers requests that fit.",
             "explanation" => "This is a controlled adapter answer, not observed model quality.",
             "source_ids" => [hd(packet["context"]["sources"])["id"]],
             "limits" => ["No live provider was called."]
           }
         })}
    end
  end

  AI.answer(packet, true, complete: complete, capability_check: fn _ -> true end)
end)

endpoint = Application.get_env(:hold_ledger_review_web, HoldLedgerReviewWeb.Endpoint)

Application.put_env(
  :hold_ledger_review_web,
  HoldLedgerReviewWeb.Endpoint,
  Keyword.merge(endpoint,
    server: true,
    url: [host: "127.0.0.1", port: 4001],
    http: [ip: {127, 0, 0, 1}, port: 4001]
  )
)

{:ok, _} = Application.ensure_all_started(:hold_ledger_review_web)
IO.puts("Controlled question browser fixture listening on 4001; no provider calls.")
