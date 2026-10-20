defmodule Faro.Health do
  @moduledoc false

  def readiness do
    readiness(
      Application.get_env(:faro, :database_enabled, false),
      fn -> Ecto.Adapters.SQL.query(Faro.Repo, "SELECT 1", [], timeout: 1_000, log: false) end
    )
  end

  def readiness(false, _query), do: :ok

  def readiness(true, query) do
    case query.() do
      {:ok, _result} -> :ok
      {:error, _reason} -> {:error, :database_unavailable}
    end
  rescue
    _error -> {:error, :database_unavailable}
  catch
    :exit, _reason -> {:error, :database_unavailable}
  end
end
