defmodule FaroWeb.Router do
  use Phoenix.Router

  pipeline :api do
    plug :accepts, ["json"]
    plug :put_secure_browser_headers
  end

  scope "/", FaroWeb do
    pipe_through :api

    get "/", StatusController, :show
    get "/health/live", StatusController, :live
    get "/health/ready", StatusController, :ready
    get "/api/v1/status", StatusController, :show
  end
end
