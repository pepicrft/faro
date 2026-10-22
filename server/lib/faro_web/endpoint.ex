defmodule FaroWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :faro

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :json],
    pass: ["*/*"],
    length: 16_384,
    json_decoder: Jason

  plug Plug.Session,
    store: :cookie,
    key: "_faro_session",
    signing_salt: "faro-session-v1",
    encryption_salt: "faro-encryption-v1",
    http_only: true,
    same_site: "Lax",
    secure: Application.compile_env(:faro, :secure_cookies, false),
    max_age: 2_592_000

  plug FaroWeb.Router
end
