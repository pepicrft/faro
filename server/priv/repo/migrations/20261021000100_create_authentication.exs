defmodule Faro.Repo.Migrations.CreateAuthentication do
  use Ecto.Migration

  def change do
    create table(:users, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:email, :string, null: false)
      add(:password_hash, :text, null: false)
      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:users, [:email]))

    create table(:browser_sessions, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false)
      add(:token_hash, :binary, null: false)
      add(:expires_at, :utc_datetime_usec, null: false)
    end

    create(unique_index(:browser_sessions, [:token_hash]))
    create(index(:browser_sessions, [:user_id]))

    # Boruta's Ecto schemas use these table and column names. Keep UUIDs even
    # for the join table, rather than adopting its historical integer key.
    create table(:oauth_clients, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:name, :string, default: "", null: false)
      add(:secret, :text, null: false)
      add(:redirect_uris, {:array, :text}, default: [], null: false)
      add(:scope, :text)
      add(:authorize_scope, :boolean, default: false, null: false)
      add(:supported_grant_types, {:array, :text}, default: [], null: false)
      add(:authorization_code_ttl, :integer, null: false)
      add(:access_token_ttl, :integer, null: false)
      add(:refresh_token_ttl, :integer, null: false)
      add(:id_token_ttl, :integer, null: false)
      add(:pkce, :boolean, default: false, null: false)
      add(:confidential, :boolean, default: false, null: false)
      add(:public_refresh_token, :boolean, default: false, null: false)
      add(:public_revoke, :boolean, default: false, null: false)
      add(:public_key, :text)
      add(:private_key, :text, null: false)
      add(:id_token_signature_alg, :string, default: "RS256")
      add(:id_token_kid, :string)
      add(:token_endpoint_auth_methods, {:array, :text}, default: [])
      add(:token_endpoint_jwt_auth_alg, :string, default: "HS256")
      add(:jwt_public_key, :text)
      add(:jwks_uri, :text)
      add(:userinfo_signed_response_alg, :string)
      add(:logo_uri, :text)
      add(:metadata, :map, default: %{})
      add(:trusted_authorities, :text, default: "", null: false)
      add(:trusted_hosts, {:array, :text}, default: [], null: false)
      timestamps()
    end

    create table(:oauth_scopes, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:name, :string, default: "", null: false)
      add(:label, :string)
      add(:public, :boolean, default: false, null: false)
      timestamps()
    end

    create(unique_index(:oauth_scopes, [:name]))

    create table(:oauth_clients_scopes, primary_key: false) do
      add(:id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()"))
      add(:client_id, references(:oauth_clients, type: :binary_id, on_delete: :delete_all))
      add(:scope_id, references(:oauth_scopes, type: :binary_id, on_delete: :delete_all))
    end

    create(unique_index(:oauth_clients_scopes, [:client_id, :scope_id]))

    create table(:oauth_tokens, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:type, :string)
      add(:value, :text)
      add(:refresh_token, :text)
      add(:previous_token, :text)
      add(:previous_code, :text)
      add(:expires_at, :bigint)
      add(:redirect_uri, :text)
      add(:state, :text)
      add(:scope, :text, default: "")
      add(:nonce, :text)
      add(:revoked_at, :utc_datetime_usec)
      add(:refresh_token_revoked_at, :utc_datetime_usec)
      add(:code_challenge_hash, :text)
      add(:code_challenge_method, :string)
      add(:client_id, references(:oauth_clients, type: :binary_id, on_delete: :delete_all))
      add(:sub, :string)
      timestamps(type: :utc_datetime_usec)
    end

    create(unique_index(:oauth_tokens, [:value]))
    create(unique_index(:oauth_tokens, [:refresh_token]))
    create(index(:oauth_tokens, [:client_id]))
    create(index(:oauth_tokens, [:sub]))

    create table(:auth_rate_limits, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:key, :string, null: false)
      add(:window, :bigint, null: false)
      add(:attempts, :integer, null: false, default: 1)
    end

    create(unique_index(:auth_rate_limits, [:key, :window]))

    for name <- ["openid", "profile", "email"] do
      execute(
        "INSERT INTO oauth_scopes (id, name, label, public, inserted_at, updated_at) " <>
          "VALUES (gen_random_uuid(), '#{name}', '#{name}', true, now(), now())",
        "DELETE FROM oauth_scopes WHERE name = '#{name}'"
      )
    end
  end
end
