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

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", HoldLedgerReviewWeb do
    pipe_through :browser

    get "/", PageController, :home
    live "/review", IndexLive
    get "/review/receipts/:id/export", ReceiptController, :export
    live "/review/receipts/:id", ReceiptLive
    live "/review/:case_id", ReviewLive
  end

  # Other scopes may use custom stacks.
  # scope "/api", HoldLedgerReviewWeb do
  #   pipe_through :api
  # end
end
