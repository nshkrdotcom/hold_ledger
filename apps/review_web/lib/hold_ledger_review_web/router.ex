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
    live "/", WorkbenchLive, :index
    live "/workbench", WorkbenchLive, :index
    live "/workbench/:id", WorkbenchLive, :show
    get "/workbench/:id/export.:format", ExportController, :export
    get "/workbench/:id/source/:source_id", SourceController, :show
  end
end
