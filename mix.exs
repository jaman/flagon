defmodule Flagon.MixProject do
  use Mix.Project

  def project do
    [
      app: :flagon,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Flagon.Application, []}
    ]
  end

  defp deps do
    [
      {:drafter, path: "../tui/drafter"},
      {:exe_qute, path: "../kdb/exe_qute"},
      {:ecto_sql, "~> 3.10"},
      {:postgrex, "~> 0.17"},
      {:duckdbex, "~> 0.3"},
      {:toml, "~> 0.7"},
      {:cachex, "~> 4.0"},
      {:nimble_csv, "~> 1.2"},
      {:elixlsx, "~> 0.6"},
      {:jason, "~> 1.4"},
      {:kino, "~> 0.14", optional: true}
    ]
  end
end
