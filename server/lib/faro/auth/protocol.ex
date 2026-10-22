defmodule Faro.Auth.Protocol do
  @moduledoc "Boruta token exchange with database serialization and refresh replay protection."
  @behaviour Boruta.Oauth.TokenApplication
  @behaviour Boruta.Oauth.RevokeApplication
  import Ecto.Query
  alias Boruta.Ecto.Token
  alias Boruta.Oauth.Error
  alias Faro.Repo

  def revoke(conn) do
    with {:ok, conn, _id} <- public_client(conn),
         {:ok, request} <- Boruta.Oauth.Request.revoke_request(conn),
         {:ok, client} <-
           Boruta.Oauth.Authorization.Client.authorize(
             id: request.client_id,
             source: request.client_authentication,
             grant_type: "revoke"
           ) do
      {:ok, result} =
        Repo.transaction(fn ->
          lock_client(client.id)
          # Boruta 2.3.8 finds the token globally after authorizing the caller. Bind
          # the lookup to that caller before delegating; a different public client
          # must not be able to revoke this client's credentials.
          token =
            Repo.one(
              from(t in Token,
                where:
                  t.type == "access_token" and t.client_id == ^client.id and
                    (t.value == ^request.token or t.refresh_token == ^request.token),
                lock: "FOR UPDATE"
              ),
              log: false
            )

          cond do
            is_nil(token) ->
              {:ok, :revoked}

            token.refresh_token == request.token ->
              revoke_descendants(token)
              {:ok, :revoked}

            true ->
              Boruta.Oauth.revoke(conn, __MODULE__)
          end
        end)

      result
    end
  end

  def exchange(conn) do
    params = conn.body_params

    with {:ok, conn, client_id} <- public_client(conn),
         grant when grant in ["authorization_code", "refresh_token"] <- params["grant_type"],
         verifier when is_binary(verifier) <- Map.get(params, "code_verifier", ""),
         true <-
           grant != "authorization_code" or Regex.match?(~r/^[A-Za-z0-9._~-]{43,128}$/, verifier) do
      params = conn.body_params

      transaction =
        Repo.transaction(fn ->
          # Serialize a client's grant mutations before locking a credential. This
          # prevents concurrent rotation from escaping family revocation and avoids
          # deadlocks when different credentials revoke overlapping descendants.
          lock_client(client_id)
          # Boruta itself reads then revokes. Lock before invoking it so concurrent
          # requests cannot both consume a code or rotate the same refresh token.
          token = lock_credential(params)

          if token && token.client_id == params["client_id"] &&
               (replay?(grant, token, verifier) or is_nil(Faro.Accounts.get_user(token.sub))) do
            revoke_descendants(token)

            {:error,
             %Error{
               status: :bad_request,
               error: :invalid_grant,
               error_description: "Credential reuse detected. Sign in again."
             }}
          else
            case Boruta.Oauth.token(conn, __MODULE__) do
              {:ok, response} -> {:ok, response}
              {:error, error} -> Repo.rollback({:protocol_error, error})
            end
          end
        end)

      case transaction do
        {:ok, result} -> result
        {:error, {:protocol_error, error}} -> {:error, error}
      end
    else
      {:error, %Error{} = error} ->
        {:error, error}

      _ ->
        {:error,
         %Error{
           status: :bad_request,
           error: :invalid_request,
           error_description:
             "Use authorization_code with a valid PKCE verifier, or refresh_token."
         }}
    end
  end

  defp public_client(conn) do
    with [] <- Plug.Conn.get_req_header(conn, "authorization"),
         id when is_binary(id) <- conn.body_params["client_id"],
         {:ok, id} <- Ecto.UUID.cast(id),
         true <- Enum.all?(~w(client_secret client_assertion), &is_nil(conn.body_params[&1])) do
      id = String.downcase(id)
      {:ok, %{conn | body_params: Map.put(conn.body_params, "client_id", id)}, id}
    else
      _ ->
        {:error,
         %Error{
           status: :unauthorized,
           error: :invalid_client,
           error_description:
             "Public native clients must send client_id and use no client authentication."
         }}
    end
  end

  defp lock_client(id) do
    Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", ["faro-oauth:" <> id],
      log: false
    )
  end

  defp lock_credential(%{"grant_type" => "authorization_code", "code" => value})
       when is_binary(value),
       do:
         Repo.one(
           from(t in Token, where: t.type == "code" and t.value == ^value, lock: "FOR UPDATE"),
           log: false
         )

  defp lock_credential(%{"grant_type" => "refresh_token", "refresh_token" => value})
       when is_binary(value),
       do:
         Repo.one(
           from(t in Token,
             where: t.type == "access_token" and t.refresh_token == ^value,
             lock: "FOR UPDATE"
           ),
           log: false
         )

  defp lock_credential(_), do: nil

  defp replay?("refresh_token", token, _verifier), do: not is_nil(token.refresh_token_revoked_at)
  defp replay?("authorization_code", %{revoked_at: nil}, _verifier), do: false

  defp replay?("authorization_code", token, verifier) do
    expected =
      :crypto.hash(:sha256, verifier)
      |> Base.url_encode64(padding: false)
      |> Boruta.Oauth.Token.hash()

    token.code_challenge_method == "S256" and is_binary(token.code_challenge_hash) and
      Plug.Crypto.secure_compare(expected, token.code_challenge_hash)
  end

  defp revoke_descendants(token) do
    # Reuse indicates compromise. Revoke this client's grants for this account,
    # including descendants that already rotated beyond the presented token.
    now = DateTime.utc_now()

    Repo.update_all(
      from(t in Token, where: t.client_id == ^token.client_id and t.sub == ^token.sub),
      [set: [revoked_at: now, refresh_token_revoked_at: now]],
      log: false
    )
  end

  @impl true
  def token_success(_conn, response), do: {:ok, response}
  @impl true
  def token_error(_conn, error), do: {:error, error}
  @impl true
  def revoke_success(_conn), do: {:ok, :revoked}
  @impl true
  def revoke_error(_conn, error), do: {:error, error}
end
