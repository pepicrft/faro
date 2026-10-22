defmodule FaroWeb.AuthRateLimit do
  @moduledoc false
  import Plug.Conn
  def init(opts), do: opts

  def call(conn, _opts) do
    key = "#{conn.method}:#{conn.request_path}"

    limit =
      case {conn.method, conn.request_path} do
        {"POST", "/oauth/register"} -> 10
        {"POST", "/auth/register"} -> 5
        {"POST", "/auth/login"} -> 10
        _ -> 120
      end

    # Do not trust caller-supplied forwarding headers. Configure a trusted-proxy
    # boundary before changing remote_ip when the service is behind an ingress.
    ip = conn.remote_ip |> :inet.ntoa() |> to_string()
    limiter = conn.private[:auth_rate_limiter] || (&Faro.Auth.RateLimit.allow?/2)
    global_ok = conn.request_path != "/oauth/register" or limiter.(key <> ":global", 20)

    if global_ok and limiter.(key <> ":" <> ip, limit) do
      conn
    else
      conn
      |> put_resp_header("retry-after", "60")
      |> put_resp_content_type("application/json")
      |> send_resp(429, Jason.encode!(%{error: "slow_down"}))
      |> halt()
    end
  end
end
