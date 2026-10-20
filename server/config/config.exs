import Config

config :faro, FaroWeb.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  url: [host: "localhost"],
  render_errors: [formats: [json: FaroWeb.ErrorJSON], layout: false],
  pubsub_server: Faro.PubSub

config :faro, ecto_repos: [Faro.Repo], database_enabled: false

config :faro, Faro.Repo,
  migration_primary_key: [name: :id, type: :binary_id],
  migration_foreign_key: [type: :binary_id]

config :phoenix, :json_library, Jason
config :logger, :default_formatter, metadata: [:request_id]

import_config "#{config_env()}.exs"
