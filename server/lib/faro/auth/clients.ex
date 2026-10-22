defmodule Faro.Auth.Clients do
  @moduledoc false
  @behaviour Boruta.Oauth.Clients
  @behaviour Boruta.Openid.Clients

  @impl Boruta.Oauth.Clients
  defdelegate get_client(id), to: Boruta.Ecto.Clients
  @impl Boruta.Oauth.Clients
  defdelegate authorized_scopes(client), to: Boruta.Ecto.Clients
  @impl Boruta.Oauth.Clients
  defdelegate list_clients_jwk(), to: Boruta.Ecto.Clients
  @impl Boruta.Openid.Clients
  defdelegate refresh_jwk_from_jwks_uri(id), to: Boruta.Ecto.Clients

  # Boruta's registration_changeset ignores PKCE/public-client/grant settings.
  # Only our allowlisted, server-normalized policy may reach this adapter.
  @impl Boruta.Openid.Clients
  def create_client(params) do
    redirects = params[:redirect_uris]

    if is_list(redirects) and redirects != [] and
         Enum.all?(redirects, &Faro.Auth.Registration.valid_redirect?/1) do
      # Boruta's generic URI validator requires an authority/host, which rejects
      # RFC 8252 private-use callbacks such as io.github.pepicrft.faro:/callback.
      # Validate with our stricter native policy first, then supply the validated
      # URIs as schema data; retain Boruta's other changeset checks/key generation.
      with {:ok, client} <-
             %Boruta.Ecto.Client{redirect_uris: redirects}
             |> Boruta.Ecto.Client.create_changeset(Map.delete(params, :redirect_uris))
             |> Faro.Repo.insert(log: false) do
        {:ok, Boruta.Ecto.OauthMapper.to_oauth_schema(client)}
      end
    else
      {:error,
       %Boruta.Ecto.Client{}
       |> Ecto.Changeset.change()
       |> Ecto.Changeset.add_error(:redirect_uris, "invalid native callback")}
    end
  end
end
