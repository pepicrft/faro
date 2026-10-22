defmodule Faro.Accounts do
  @moduledoc "Local account credentials and revocable, hashed browser sessions."
  import Ecto.Query
  alias Faro.Accounts.{BrowserSession, User}
  alias Faro.Repo

  @session_seconds 60 * 60 * 24 * 30

  def register(attrs), do: attrs |> User.registration_changeset() |> Repo.insert(log: false)

  def authenticate(email, password) when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, [email: email |> String.trim() |> String.downcase()], log: false)

    if user && Pbkdf2.verify_pass(password, user.password_hash) do
      {:ok, user}
    else
      # A nonexistent account still pays the password derivation cost.
      if is_nil(user),
        do: Pbkdf2.hash_pwd_salt("invalid account", rounds: 210_000, digest: :sha512)

      {:error, :invalid_credentials}
    end
  end

  def authenticate(_, _), do: {:error, :invalid_credentials}

  def create_session(%User{id: id}) do
    token = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
    expires_at = DateTime.add(DateTime.utc_now(), @session_seconds)

    Repo.insert!(%BrowserSession{user_id: id, token_hash: hash(token), expires_at: expires_at},
      log: false
    )

    token
  end

  def session_user(token) when is_binary(token) and byte_size(token) == 43 do
    now = DateTime.utc_now()
    token_hash = hash(token)

    Repo.one(
      from(s in BrowserSession,
        join: u in assoc(s, :user),
        where: s.token_hash == ^token_hash and s.expires_at > ^now,
        select: u
      ),
      log: false
    )
  end

  def session_user(_), do: nil

  def delete_session(token) when is_binary(token) do
    token_hash = hash(token)
    Repo.delete_all(from(s in BrowserSession, where: s.token_hash == ^token_hash), log: false)
    :ok
  end

  def delete_session(_), do: :ok

  def get_user(id) when is_binary(id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> Repo.get(User, id, log: false)
      :error -> nil
    end
  end

  def get_user(_), do: nil
  defp hash(value), do: :crypto.hash(:sha256, value)
end
