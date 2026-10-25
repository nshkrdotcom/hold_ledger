defmodule HoldLedger.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    # An isolated source checkout never silently opens an existing ledger.
    # A deployment can opt in to one authoritative supervised server by
    # configuring :server_options with its explicit journal pathname/caps.
    server_options = Application.get_env(:hold_ledger, :server_options)
    children = [{Task.Supervisor, name: HoldLedger.EffectSupervisor}]

    children =
      if server_options do
        children ++ [{HoldLedger.Server, server_options}]
      else
        children
      end

    Supervisor.start_link(children, strategy: :one_for_one, name: HoldLedger.Supervisor)
  end
end
