# Explicit controlled browser fixture. No provider is contacted.
# MIX_ENV=test uv run --locked python scripts/local_run.py --cwd apps/review_web \
#   mix run --no-start --no-halt test/support/question_browser_server.exs
alias HoldLedgerReview.AI
root = System.fetch_env!("HOLD_LEDGER_BROWSER_DIR")
profile = System.get_env("HOLD_LEDGER_BROWSER_PROFILE", "main")

for {key, directory} <- [
      question_store_dir: "questions",
      review_store_dir: "reviews",
      part3_store_dir: "packages"
    ] do
  Application.put_env(:hold_ledger_review_web, key, Path.join(root, directory))
end

runner = fn packet ->
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
end

Application.put_env(
  :hold_ledger_review_web,
  :question_runner,
  if(profile == "questions", do: runner, else: fn _ -> {:error, :browser_provider_disabled} end)
)

endpoint = Application.get_env(:hold_ledger_review_web, HoldLedgerReviewWeb.Endpoint)

Application.put_env(
  :hold_ledger_review_web,
  HoldLedgerReviewWeb.Endpoint,
  Keyword.merge(endpoint,
    server: true,
    url: [host: "127.0.0.1", port: 0],
    http: [ip: {127, 0, 0, 1}, port: 0]
  )
)

{:ok, _} = Application.ensure_all_started(:hold_ledger_review_web)
{:ok, {_address, port}} = HoldLedgerReviewWeb.Endpoint.server_info(:http)
ready = %{port: port, profile: profile, token: System.fetch_env!("HOLD_LEDGER_BROWSER_TOKEN")}
File.write!(System.fetch_env!("HOLD_LEDGER_BROWSER_READY") <> ".tmp", JSON.encode!(ready))

File.rename!(
  System.fetch_env!("HOLD_LEDGER_BROWSER_READY") <> ".tmp",
  System.fetch_env!("HOLD_LEDGER_BROWSER_READY")
)

IO.puts("Browser fixture ready on #{port}; no provider calls.")
