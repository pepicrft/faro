defmodule FaroWeb.Router do
  use Phoenix.Router

  pipeline :api do
    plug :accepts, ["json"]
    plug :put_secure_browser_headers
  end

  pipeline :oauth do
    plug FaroWeb.AuthAvailable
    plug FaroWeb.AuthRateLimit
  end

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :protect_from_forgery

    plug :put_secure_browser_headers, %{
      "content-security-policy" =>
        "default-src 'none'; style-src 'unsafe-inline'; form-action 'self'; frame-ancestors 'none'; base-uri 'none'",
      "referrer-policy" => "no-referrer"
    }

    plug FaroWeb.AuthAvailable
    plug FaroWeb.AuthRateLimit
    plug FaroWeb.BrowserSession
  end

  scope "/", FaroWeb do
    pipe_through :api

    get "/", StatusController, :show
    get "/health/live", StatusController, :live
    get "/health/ready", StatusController, :ready
    get "/api/v1/status", StatusController, :show
    get "/.well-known/openid-configuration", OAuthController, :discovery
    get "/.well-known/oauth-authorization-server", OAuthController, :discovery
  end

  scope "/", FaroWeb do
    pipe_through [:api, :oauth]
    post "/oauth/register", OAuthRegistrationController, :create
    post "/oauth/token", OAuthController, :token
    post "/oauth/revoke", OAuthController, :revoke
    get "/oauth/jwks", OAuthController, :jwks
    get "/oauth/userinfo", OAuthController, :userinfo
    post "/oauth/userinfo", OAuthController, :userinfo
    get "/api/v1/me", OAuthController, :userinfo
  end

  scope "/", FaroWeb do
    pipe_through :browser
    get "/auth/login", SessionController, :new
    post "/auth/login", SessionController, :create
    post "/auth/register", SessionController, :register
    post "/auth/logout", SessionController, :delete
    get "/oauth/authorize", OAuthAuthorizeController, :show
    post "/oauth/authorize", OAuthAuthorizeController, :create
  end
end
