defmodule Faro.Auth.DatabaseCache do
  @moduledoc """
  Deliberately bypass Boruta's process cache. Authorization and revocation read
  PostgreSQL on every request, including across replicas and sandbox transactions.
  No credentials or scope lists survive a database transaction in shared memory.
  """
  def get(_key), do: {:ok, nil}
  def put(_key, _value, _opts \\ []), do: :ok
  def delete(_key), do: :ok
end
