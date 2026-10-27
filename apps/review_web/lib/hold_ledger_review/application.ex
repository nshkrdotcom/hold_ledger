defmodule HoldLedgerReview.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    HoldLedgerReview.Config.validate!()
    # No model jobs are dispatched by the Milestone A source evaluator.

    children = [
      {Task.Supervisor, name: HoldLedgerReview.Tasks},
      HoldLedgerReview.Claims,
      HoldLedgerReviewWeb.Telemetry,
      {DNSCluster,
       query: Application.get_env(:hold_ledger_review_web, :dns_cluster_query) || :ignore},
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
