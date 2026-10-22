defmodule FaroWeb.OAuthRegistrationController do
  @moduledoc false
  use Phoenix.Controller, formats: [:json]
  @behaviour Boruta.Openid.DynamicRegistrationApplication
  alias FaroWeb.OAuthResponse

  def create(conn, params) do
    case Faro.Auth.Registration.normalize(params) do
      {:ok, metadata} -> Boruta.Openid.register_client(conn, metadata, __MODULE__)
      {:error, reason} -> registration_error(conn, reason)
    end
  end

  @impl true
  def client_registered(conn, client) do
    conn
    |> OAuthResponse.no_store()
    |> put_status(:created)
    |> json(%{
      client_id: client.id,
      client_id_issued_at: System.system_time(:second),
      client_name: client.name,
      application_type: "native",
      redirect_uris: client.redirect_uris,
      grant_types: client.metadata["grant_types"],
      scope: client.metadata["scope"],
      response_types: ["code"],
      token_endpoint_auth_method: "none",
      id_token_signed_response_alg: client.id_token_signature_alg
    })
  end

  @impl true
  def registration_failure(conn, _changeset),
    do: registration_error(conn, "The client metadata is invalid.")

  defp registration_error(conn, reason),
    do:
      conn
      |> OAuthResponse.no_store()
      |> put_status(:bad_request)
      |> json(%{error: "invalid_client_metadata", error_description: reason})
end
