defmodule FaroWeb.OAuthResponse do
  @moduledoc false
  import Plug.Conn
  import Phoenix.Controller

  def no_store(conn),
    do:
      conn
      |> put_resp_header("cache-control", "no-store")
      |> put_resp_header("pragma", "no-cache")

  def error(conn, %Boruta.Oauth.Error{} = error) do
    status = Plug.Conn.Status.code(error.status)
    code = if status >= 500, do: "temporarily_unavailable", else: to_string(error.error)

    conn
    |> no_store()
    |> put_status(status)
    |> json(%{
      error: code,
      error_description: "The OAuth request is invalid, expired, or unauthorized."
    })
  end

  def invalid(conn, description) do
    conn
    |> no_store()
    |> put_status(:bad_request)
    |> json(%{error: "invalid_request", error_description: description})
  end
end
