defmodule Faro.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    database = if Application.get_env(:faro, :database_enabled, false), do: [Faro.Repo], else: []

    children = database ++ [{Phoenix.PubSub, name: Faro.PubSub}, FaroWeb.Endpoint]

    Supervisor.start_link(children, strategy: :one_for_one, name: Faro.Supervisor)
  end

  @impl true
  def config_change(changed, _new, removed) do
    FaroWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
