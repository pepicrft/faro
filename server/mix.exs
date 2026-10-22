defmodule Faro.MixProject do
  use Mix.Project

  def project do
    [
      app: :faro,
      version: "0.1.0",
      elixir: "~> 1.20",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: [faro: [include_executables_for: [:unix]]]
    ]
  end

  def application do
    [mod: {Faro.Application, []}, extra_applications: [:logger, :runtime_tools]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:phoenix, "~> 1.8.0"},
      {:bandit, "~> 1.0"},
      {:jason, "~> 1.4"},
      {:ecto_sql, "~> 3.13"},
      {:postgrex, "~> 0.22"},
      {:boruta, "~> 2.3"},
      {:pbkdf2_elixir, "~> 2.3"}
    ]
  end
end
