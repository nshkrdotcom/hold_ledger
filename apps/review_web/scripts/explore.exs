# Run with mix run --no-start scripts/explore.exs -- request.json.
# This process owns a separate scratch store and never opens a listener or provider.
alias HoldLedgerReview.{Canonical, Config, ProofReading, Trace}

args = Enum.reject(System.argv(), &(&1 == "--"))
with [path] <- args,
     {:ok, %{size: size}} <- File.stat(path), true <- size <= 64_000,
     {:ok, bytes} <- File.read(path), {:ok, request} <- Jason.decode(bytes) do
  scratch = Path.join(Config.root(), "tmp/review_studio/commands/" <> Trace.token())
  Application.put_env(:hold_ledger_review_web, :review_store_dir, Path.join(scratch, "reviews"))
  Application.put_env(:hold_ledger_review_web, :part3_store_dir, Path.join(scratch, "packages"))
  endpoint = Application.get_env(:hold_ledger_review_web, HoldLedgerReviewWeb.Endpoint, [])
  Application.put_env(:hold_ledger_review_web, HoldLedgerReviewWeb.Endpoint, Keyword.put(endpoint, :server, false))
  {:ok, _} = Application.ensure_all_started(:hold_ledger_review_web)

  result = case request do
    %{"operation" => "step", "mode" => mode, "before" => before, "event" => event} when map_size(request) == 4 ->
      Trace.execute(mode, before, event)
    %{"operation" => "read_claim", "slug" => slug} when map_size(request) == 2 ->
      ProofReading.document(slug)
    %{"operation" => "explain_claim", "slug" => slug, "witness" => witness} when map_size(request) == 3 ->
      ProofReading.explain(slug, witness)
    %{"operation" => "source", "path" => path} when map_size(request) == 2 ->
      case Trace.source(path) do
        {:ok, bytes, digest} -> {:ok, %{"path" => path, "bytes" => bytes, "sha256" => digest}}
        error -> error
      end
    _ -> {:error, :unsupported_command}
  end

  case result do
    {:ok, receipt} ->
      {:ok, identity} = Trace.identity()
      IO.puts(Canonical.json(%{"identity" => identity, "receipt" => receipt}))
    {:error, reason} ->
      IO.puts(:stderr, inspect(reason))
      System.halt(2)
  end
else
  _ ->
    IO.puts(:stderr, "Expected one bounded JSON request file")
    System.halt(2)
end
