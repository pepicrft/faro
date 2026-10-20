import Config

config :faro, FaroWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  secret_key_base: String.duplicate("faro-local-development-only-", 4),
  check_origin: false,
  debug_errors: true

config :logger, :default_formatter, format: "[$level] $message\n"
