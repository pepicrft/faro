defmodule FaroWeb.OAuthAuthorizeController do
  @moduledoc false
  use Phoenix.Controller, formats: [:html, :json]
  @behaviour Boruta.Oauth.AuthorizeApplication
  alias Boruta.Oauth.{AuthorizeResponse, ResourceOwner}
  alias FaroWeb.{AuthHTML, OAuthResponse}

  def show(conn, params) do
    params = if params == %{}, do: get_session(conn, :oauth_request) || %{}, else: params

    with {:ok, params} <- Faro.Auth.Registration.authorization(params) do
      conn =
        conn
        |> put_session(:oauth_request, params)
        |> put_session(:oauth_request_at, System.system_time(:second))
        |> put_session(:oauth_request_id, Ecto.UUID.generate())

      conn = %{conn | params: params, query_params: params}

      if user = conn.assigns.current_user do
        Boruta.Oauth.preauthorize(assign(conn, :decision, :show), owner(user), __MODULE__)
      else
        redirect(conn, to: "/auth/login")
      end
    else
      {:error, reason} -> OAuthResponse.invalid(conn, reason)
    end
  end

  def create(conn, %{"decision" => decision, "request_id" => request_id})
      when decision in ["approve", "deny"] do
    params = get_session(conn, :oauth_request)
    at = get_session(conn, :oauth_request_at) || 0

    if conn.assigns.current_user && is_map(params) && is_binary(request_id) &&
         request_id == get_session(conn, :oauth_request_id) &&
         (System.system_time(:second) - at) in 0..600 do
      # Never accept OAuth fields from the consent POST. Consent is bound to the
      # server-validated request in the authenticated, encrypted browser session.
      conn = %{conn | params: params, query_params: params, body_params: %{}}

      Boruta.Oauth.preauthorize(
        assign(conn, :decision, decision),
        owner(conn.assigns.current_user),
        __MODULE__
      )
    else
      OAuthResponse.invalid(conn, "Sign in and restart the authorization request.")
    end
  end

  def create(conn, _params), do: OAuthResponse.invalid(conn, "Choose Allow or Deny.")

  @impl true
  def preauthorize_success(conn, authorization) do
    case conn.assigns.decision do
      :show ->
        conn
        |> OAuthResponse.no_store()
        |> permit_callback(authorization.redirect_uri)
        |> html(
          AuthHTML.consent(
            Plug.CSRFProtection.get_csrf_token(),
            conn.assigns.current_user,
            authorization.client,
            authorization.scope,
            get_session(conn, :oauth_request_id)
          )
        )

      "approve" ->
        conn = clear_request(conn)
        Boruta.Oauth.authorize(conn, owner(conn.assigns.current_user), __MODULE__)

      "deny" ->
        uri = URI.parse(authorization.redirect_uri)

        query =
          URI.decode_query(uri.query || "")
          |> Map.merge(%{"error" => "access_denied", "state" => authorization.state})

        conn
        |> clear_request()
        |> OAuthResponse.no_store()
        |> redirect(external: URI.to_string(%{uri | query: URI.encode_query(query)}))
    end
  end

  @impl true
  def preauthorize_error(conn, error), do: conn |> clear_request() |> OAuthResponse.error(error)
  @impl true
  def authorize_success(conn, response),
    do:
      conn
      |> OAuthResponse.no_store()
      |> redirect(external: AuthorizeResponse.redirect_to_url(response))

  @impl true
  def authorize_error(conn, error), do: OAuthResponse.error(conn, error)

  defp permit_callback(conn, redirect_uri) do
    # Browsers may enforce form-action across the consent POST's redirect. Permit
    # only the validated callback origin (or private-use scheme), not arbitrary
    # form destinations, so native/loopback callbacks aren't blocked by CSP.
    uri = URI.parse(redirect_uri)

    source =
      if uri.host,
        do: URI.to_string(%URI{scheme: uri.scheme, host: uri.host, port: uri.port}),
        else: uri.scheme <> ":"

    [policy] = Plug.Conn.get_resp_header(conn, "content-security-policy")

    Plug.Conn.put_resp_header(
      conn,
      "content-security-policy",
      String.replace(policy, "form-action 'self'", "form-action 'self' " <> source)
    )
  end

  defp owner(user), do: %ResourceOwner{sub: user.id, username: user.email}

  defp clear_request(conn),
    do:
      conn
      |> delete_session(:oauth_request)
      |> delete_session(:oauth_request_at)
      |> delete_session(:oauth_request_id)
end
