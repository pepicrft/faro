defmodule Faro.Release do
  @moduledoc "Database tasks run by the release, without starting the web application."

  def migrate do
    Application.load(:faro)

    for repo <- Application.fetch_env!(:faro, :ecto_repos) do
      {:ok, _result, _apps} =
        Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end

    :ok
  end
end
