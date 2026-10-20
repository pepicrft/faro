import Config

config :faro, FaroWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: String.duplicate("faro-isolated-tests-only-", 4),
  server: false

config :logger, level: :warning
