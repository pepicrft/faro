defmodule FaroWeb.StatusController do
  use Phoenix.Controller, formats: [:json]

  def live(conn, _params), do: json(conn, %{status: "ok"})

  def ready(conn, _params) do
    case Faro.Health.readiness() do
      :ok ->
        json(conn, %{status: "ok"})

      {:error, :database_unavailable} ->
        conn |> put_status(:service_unavailable) |> json(%{status: "unavailable"})
    end
  end

  def show(conn, _params) do
    json(conn, %{name: "Faro", service: "server", agent_runtime: "not_configured"})
  end
end
