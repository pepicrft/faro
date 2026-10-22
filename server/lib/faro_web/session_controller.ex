defmodule FaroWeb.SessionController do
  @moduledoc false
  use Phoenix.Controller, formats: [:html]
  alias FaroWeb.{AuthHTML, BrowserSession, OAuthResponse}

  def new(conn, _params) do
    if user = conn.assigns.current_user do
      conn
      |> OAuthResponse.no_store()
      |> html(AuthHTML.signed_in(Plug.CSRFProtection.get_csrf_token(), user))
    else
      render_form(conn)
    end
  end

  def create(conn, params) do
    case Faro.Accounts.authenticate(params["email"], params["password"]) do
      {:ok, user} ->
        conn |> BrowserSession.sign_in(user) |> after_sign_in()

      {:error, _} ->
        conn |> put_status(:unprocessable_entity) |> render_form("Invalid email or password.")
    end
  end

  def register(conn, params) do
    case Faro.Accounts.register(Map.take(params, ["email", "password"])) do
      {:ok, user} ->
        conn |> BrowserSession.sign_in(user) |> after_sign_in()

      {:error, _} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render_form(
          "Unable to create this account. Use a valid email and a password of 15 to 128 characters, or sign in if you already have an account."
        )
    end
  end

  def delete(conn, _params), do: conn |> BrowserSession.sign_out() |> redirect(to: "/auth/login")

  defp after_sign_in(conn) do
    if get_session(conn, :oauth_request),
      do: redirect(conn, to: "/oauth/authorize"),
      else: redirect(conn, to: "/auth/login")
  end

  defp render_form(conn, error \\ nil),
    do:
      conn
      |> OAuthResponse.no_store()
      |> html(AuthHTML.sign_in(Plug.CSRFProtection.get_csrf_token(), error))
end
