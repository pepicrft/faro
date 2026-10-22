defmodule Faro.Auth.ResourceOwners do
  @moduledoc false
  @behaviour Boruta.Oauth.ResourceOwners
  alias Boruta.Oauth.{ResourceOwner, Scope}

  @impl true
  def get_by(sub: id) do
    case Faro.Accounts.get_user(id) do
      nil -> {:error, "Account not found."}
      user -> {:ok, %ResourceOwner{sub: user.id, username: user.email}}
    end
  end

  def get_by(_), do: {:error, "Account not found."}

  @impl true
  def check_password(_, _), do: {:error, "Use browser authorization with PKCE."}

  @impl true
  def authorized_scopes(_),
    do: Enum.map(~w(openid profile email), &%Scope{name: &1, public: true})

  @impl true
  def claims(%ResourceOwner{sub: id, username: email}, scope) do
    if "email" in String.split(scope),
      do: %{sub: id, email: email, email_verified: false},
      else: %{sub: id}
  end
end
