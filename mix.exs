defmodule Soren.MixProject do
  use Mix.Project

  def project do
    [
      app: :soren,
      version: "0.1.0",
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :inets],
      mod: {Soren.Application, []}
    ]
  end

  defp deps do
    [
      {:bandit, "~> 1.0"},
      {:jason, "~> 1.0"},
      {:logster, "~> 2.0.0-rc.1"},
      {:mdex, "~> 0.1"},
      {:nimble_publisher, "~> 1.0"},
      {:phoenix, "~> 1.7.0"},
      {:phoenix_html, "~> 4.0"},
      {:phoenix_pubsub, "~> 2.1"},
      {:phoenix_live_view, "~> 0.20"},

      # Development
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:tailwind, "~> 0.2", runtime: Mix.env() == :dev}
    ]
  end
end
