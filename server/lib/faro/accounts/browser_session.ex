defmodule Faro.Accounts.BrowserSession do
  @moduledoc false
  use Faro.Schema

  schema "browser_sessions" do
    belongs_to(:user, Faro.Accounts.User)
    field(:token_hash, :binary, redact: true)
    field(:expires_at, :utc_datetime_usec)
  end
end
