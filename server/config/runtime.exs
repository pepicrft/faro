import Config

if System.get_env("PHX_SERVER") == "true" do
  config :faro, FaroWeb.Endpoint, server: true
end

if config_env() != :test do
  port = System.get_env("PORT", "4000") |> String.to_integer()
  bind_address = if config_env() == :prod, do: {0, 0, 0, 0}, else: {127, 0, 0, 1}
  config :faro, FaroWeb.Endpoint, http: [ip: bind_address, port: port]

  issuer =
    if config_env() == :prod,
      do: "https://#{System.get_env("FARO_HOST", "faro.fyi")}",
      else: "http://localhost:#{port}"

  config :boruta, Boruta.Oauth, issuer: issuer
end

if config_env() == :prod do
  secret_key_base = System.fetch_env!("FARO_SECRET_KEY_BASE")

  if byte_size(secret_key_base) < 64 do
    raise "FARO_SECRET_KEY_BASE must contain at least 64 bytes"
  end

  config :faro, FaroWeb.Endpoint,
    url: [host: System.get_env("FARO_HOST", "faro.fyi"), port: 443, scheme: "https"],
    secret_key_base: secret_key_base
end

database_default = if config_env() == :prod, do: "true", else: "false"
# Authentication integration tests must never silently skip database coverage or
# upload a database-disabled result to the shared test cache.
database_enabled =
  config_env() == :test or System.get_env("FARO_DATABASE_ENABLED", database_default) == "true"

config :faro, database_enabled: database_enabled

if database_enabled do
  database_url =
    System.fetch_env!(
      if config_env() == :test, do: "FARO_TEST_DATABASE_URL", else: "FARO_DATABASE_URL"
    )

  transport_security =
    if System.get_env("FARO_DATABASE_SSL", "true") == "true" do
      [
        verify: :verify_peer,
        cacertfile: System.fetch_env!("FARO_DATABASE_CA_FILE"),
        server_name_indication:
          database_url |> URI.parse() |> Map.fetch!(:host) |> String.to_charlist(),
        customize_hostname_check: [match_fun: :public_key.pkix_verify_hostname_match_fun(:https)]
      ]
    else
      false
    end

  config :faro, Faro.Repo,
    url: database_url,
    ssl: transport_security,
    pool_size: String.to_integer(System.get_env("FARO_POOL_SIZE", "5"))
end
