defmodule FaroWeb.OAuthController do
  @moduledoc false
  use Phoenix.Controller, formats: [:json]
  @behaviour Boruta.Oauth.RevokeApplication
  @behaviour Boruta.Openid.JwksApplication
  @behaviour Boruta.Openid.UserinfoApplication
  alias FaroWeb.OAuthResponse

  def token(conn, _params) do
    case Faro.Auth.Protocol.exchange(conn) do
      {:ok, response} ->
        payload =
          response
          |> Map.from_struct()
          |> Map.take(~w(access_token token_type expires_in refresh_token id_token scope)a)
          |> Enum.reject(fn {_, value} -> is_nil(value) end)
          |> Map.new()

        conn |> OAuthResponse.no_store() |> json(payload)

      {:error, error} ->
        OAuthResponse.error(conn, error)
    end
  end

  def revoke(conn, _params) do
    case Faro.Auth.Protocol.revoke(conn) do
      {:ok, :revoked} -> revoke_success(conn)
      {:error, error} -> revoke_error(conn, error)
    end
  end

  def jwks(conn, _params), do: Boruta.Openid.jwks(conn, __MODULE__)
  def userinfo(conn, _params), do: Boruta.Openid.userinfo(conn, __MODULE__)

  @impl true
  def revoke_success(conn), do: conn |> OAuthResponse.no_store() |> send_resp(200, "")
  @impl true
  def revoke_error(conn, error), do: OAuthResponse.error(conn, error)
  @impl true
  def jwk_list(conn, keys), do: conn |> OAuthResponse.no_store() |> json(%{keys: keys})
  @impl true
  def userinfo_fetched(conn, response),
    do: conn |> OAuthResponse.no_store() |> json(response.userinfo)

  @impl true
  def unauthorized(conn, _error),
    do:
      conn
      |> OAuthResponse.no_store()
      |> put_resp_header("www-authenticate", ~s(Bearer error="invalid_token"))
      |> put_status(:unauthorized)
      |> json(%{error: "invalid_token"})

  def discovery(conn, _params) do
    issuer = Boruta.Config.issuer()

    json(conn, %{
      issuer: issuer,
      authorization_endpoint: issuer <> "/oauth/authorize",
      token_endpoint: issuer <> "/oauth/token",
      registration_endpoint: issuer <> "/oauth/register",
      revocation_endpoint: issuer <> "/oauth/revoke",
      userinfo_endpoint: issuer <> "/oauth/userinfo",
      jwks_uri: issuer <> "/oauth/jwks",
      response_types_supported: ["code"],
      response_modes_supported: ["query"],
      grant_types_supported: ["authorization_code", "refresh_token"],
      scopes_supported: ["openid", "profile", "email"],
      subject_types_supported: ["public"],
      id_token_signing_alg_values_supported: ["RS256"],
      code_challenge_methods_supported: ["S256"],
      token_endpoint_auth_methods_supported: ["none"],
      revocation_endpoint_auth_methods_supported: ["none"],
      claims_supported: ["sub", "iss", "aud", "exp", "iat", "nonce", "email", "email_verified"]
    })
  end
end
