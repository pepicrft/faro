import Config

config :faro, FaroWeb.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  url: [host: "localhost"],
  render_errors: [formats: [json: FaroWeb.ErrorJSON], layout: false],
  pubsub_server: Faro.PubSub

config :faro,
  ecto_repos: [Faro.Repo],
  database_enabled: false,
  secure_cookies: config_env() == :prod

config :faro, Faro.Repo,
  migration_primary_key: [name: :id, type: :binary_id],
  migration_foreign_key: [type: :binary_id],
  # OAuth query parameters include credentials. Never emit them through SQL logs.
  log: false

config :boruta, Boruta.Oauth,
  repo: Faro.Repo,
  issuer: "http://localhost:4000",
  cache_backend: Faro.Auth.DatabaseCache,
  contexts: [clients: Faro.Auth.Clients, resource_owners: Faro.Auth.ResourceOwners],
  max_ttl: [authorization_code: 60, access_token: 900, id_token: 900, refresh_token: 2_592_000]

config :phoenix,
       :filter_parameters,
       ~w(password password_hash client_secret code code_verifier code_challenge access_token refresh_token id_token token state nonce _csrf_token)

config :phoenix, :json_library, Jason
config :logger, :default_formatter, metadata: [:request_id]

import_config "#{config_env()}.exs"
