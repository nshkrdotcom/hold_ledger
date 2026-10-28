defmodule HoldLedgerReviewWeb.Router do
  use HoldLedgerReviewWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {HoldLedgerReviewWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  scope "/", HoldLedgerReviewWeb do
    pipe_through :browser
    live "/", CockpitLive, :index
    live "/claims/:slug", CockpitLive, :claim
    live "/claims/:slug/:id", CockpitLive, :show
    get "/claims/:slug/source/:source_id/:sha", CockpitController, :source
    get "/claims/:slug/generated/:sha", CockpitController, :generated
    get "/sessions/:id/export", CockpitController, :export
    get "/comparisons/:id/repair/:file", CockpitController, :repair
    get "/comparisons/:id/source/:side/:change_id", CockpitController, :change
    get "/comparisons/:id/law/:side/:slug/source", CockpitController, :law
    get "/comparisons/:id/artifact/:side/:sha256", CockpitController, :artifact
  end
end
