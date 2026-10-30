defmodule HoldLedgerReview.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    HoldLedgerReview.Config.validate!()
    # Source generation first; the durable writer refuses a stale generation.

    children = [
      HoldLedgerReview.Claims,
      {Task.Supervisor, name: HoldLedgerReview.AITaskSupervisor},
      HoldLedgerReview.Questions,
      HoldLedgerReview.ReviewStore,
      {HoldLedgerReview.Part3Store,
       dir:
         Application.get_env(
           :hold_ledger_review_web,
           :part3_store_dir,
           Path.join(HoldLedgerReview.Config.root(), "tmp/review_studio/packages")
         )},
      HoldLedgerReview.Part3Runner,
      {Phoenix.PubSub, name: HoldLedgerReview.PubSub},
      # Start to serve requests, typically the last entry
      HoldLedgerReviewWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: HoldLedgerReview.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    HoldLedgerReviewWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
