defmodule FaroWeb.AuthAvailable do
  @moduledoc false
  import Plug.Conn
  def init(opts), do: opts

  def call(conn, _opts) do
    if Application.get_env(:faro, :database_enabled, false) do
      conn
    else
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(503, Jason.encode!(%{error: "temporarily_unavailable"}))
      |> halt()
    end
  end
end
