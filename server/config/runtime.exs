import Config

if System.get_env("PHX_SERVER") == "true" do
  config :faro, FaroWeb.Endpoint, server: true
end

if config_env() != :test do
  port = System.get_env("PORT", "4000") |> String.to_integer()
  bind_address = if config_env() == :prod, do: {0, 0, 0, 0}, else: {127, 0, 0, 1}
  config :faro, FaroWeb.Endpoint, http: [ip: bind_address, port: port]
end

if config_env() == :prod do
  secret_key_base = System.fetch_env!("FARO_SECRET_KEY_BASE")

  if byte_size(secret_key_base) < 64 do
    raise "FARO_SECRET_KEY_BASE must contain at least 64 bytes"
  end

  config :faro, FaroWeb.Endpoint,
    url: [host: System.get_env("FARO_HOST", "localhost"), port: 80, scheme: "http"],
    secret_key_base: secret_key_base
end
