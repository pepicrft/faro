ExUnit.start()

Ecto.Migrator.run(Faro.Repo, Application.app_dir(:faro, "priv/repo/migrations"), :up, all: true)
Ecto.Adapters.SQL.Sandbox.mode(Faro.Repo, :manual)
