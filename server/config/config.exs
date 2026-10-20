import Config

config :faro, FaroWeb.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  url: [host: "localhost"],
  render_errors: [formats: [json: FaroWeb.ErrorJSON], layout: false],
  pubsub_server: Faro.PubSub

config :phoenix, :json_library, Jason
config :logger, :default_formatter, metadata: [:request_id]

import_config "#{config_env()}.exs"
