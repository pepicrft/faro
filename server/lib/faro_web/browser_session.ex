defmodule FaroWeb.BrowserSession do
  @moduledoc false
  import Plug.Conn
  def init(opts), do: opts

  def call(conn, _opts),
    do: assign(conn, :current_user, Faro.Accounts.session_user(get_session(conn, :user_token)))

  def sign_in(conn, user) do
    Faro.Accounts.delete_session(get_session(conn, :user_token))
    Plug.CSRFProtection.delete_csrf_token()

    conn
    |> configure_session(renew: true)
    |> delete_session(:_csrf_token)
    |> put_session(:user_token, Faro.Accounts.create_session(user))
  end

  def sign_out(conn) do
    Faro.Accounts.delete_session(get_session(conn, :user_token))
    Plug.CSRFProtection.delete_csrf_token()
    configure_session(conn, drop: true)
  end
end
