defmodule FaroWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :faro

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]
  plug FaroWeb.Router
end
