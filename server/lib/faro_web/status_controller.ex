defmodule FaroWeb.StatusController do
  use Phoenix.Controller, formats: [:json]

  def live(conn, _params), do: json(conn, %{status: "ok"})

  # The scaffold has no external dependencies. Add readiness checks here when
  # persistence or workers become necessary; never add them to liveness.
  def ready(conn, _params), do: json(conn, %{status: "ok"})

  def show(conn, _params) do
    json(conn, %{name: "Faro", service: "server", agent_runtime: "not_configured"})
  end
end
