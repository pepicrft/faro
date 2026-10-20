defmodule Faro.HealthTest do
  use ExUnit.Case, async: true

  test "readiness can explicitly run without a database for local scaffolding" do
    assert :ok = Faro.Health.readiness(false, fn -> flunk("database must not be queried") end)
  end

  test "readiness verifies the database when enabled" do
    assert :ok = Faro.Health.readiness(true, fn -> {:ok, %{rows: [[1]]}} end)
  end

  test "readiness returns unavailable while the connection pool is restarting" do
    assert {:error, :database_unavailable} = Faro.Health.readiness(true, fn -> exit(:noproc) end)
  end

  test "readiness does not leak database errors" do
    assert {:error, :database_unavailable} =
             Faro.Health.readiness(true, fn -> {:error, "private connection details"} end)
  end
end
