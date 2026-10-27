import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/hold_ledger_review_web start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :hold_ledger_review_web, HoldLedgerReviewWeb.Endpoint, server: true
end

config :hold_ledger_review_web, HoldLedgerReviewWeb.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

if config_env() == :dev do
  # Reload browser tabs when matching files change.
  config :hold_ledger_review_web, HoldLedgerReviewWeb.Endpoint,
    live_reload: [
      web_console_logger: true,
      patterns: [
        # Static assets, except user uploads
        ~r"priv/static/(?!uploads/).*\.(js|css|png|jpeg|jpg|gif|svg)$"E,
        # Router, Controllers, LiveViews and LiveComponents
        ~r"lib/hold_ledger_review_web/router\.ex$"E,
        ~r"lib/hold_ledger_review_web/(controllers|live|components)/.*\.(ex|heex)$"E
      ]
    ]
end

# This prototype supports localhost development, not hosted releases.
config :hold_ledger_review_web,
       :ledger_root,
       System.get_env("HOLD_LEDGER_REVIEW_ROOT") || Path.expand("../../..", __DIR__)

if model = System.get_env("HOLD_LEDGER_REVIEW_MODEL") do
  config :hold_ledger_review_web, :inference_model, model
end

if effort = System.get_env("HOLD_LEDGER_REVIEW_REASONING_EFFORT") do
  allowed = %{
    "low" => :low,
    "medium" => :medium,
    "high" => :high,
    "xhigh" => :xhigh,
    "max" => :max,
    "ultra" => :ultra
  }

  config :hold_ledger_review_web, :inference_reasoning_effort, Map.fetch!(allowed, effort)
end
