defmodule Flagon.MixProject do
  use Mix.Project

  def project do
    [
      app: :flagon,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      releases: releases(),
      deps: deps()
    ]
  end

  defp releases do
    [
      flagon: [
        steps: [:assemble, &Burrito.wrap/1],
        burrito: [
          targets: [
            macos_arm: [os: :darwin, cpu: :aarch64],
            macos_x86: [os: :darwin, cpu: :x86_64],
            linux_x86: [os: :linux, cpu: :x86_64]
          ]
        ]
      ]
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
      {:drafter, github: "jaman/drafter"},
      {:exe_qute, "~> 0.1.2"},
      {:ecto_sql, "~> 3.10"},
      {:postgrex, "~> 0.17"},
      {:duckdbex, "~> 0.3"},
      {:toml, "~> 0.7"},
      {:cachex, "~> 4.0"},
      {:burrito, "~> 1.0"},
      {:nimble_csv, "~> 1.2"},
      {:elixlsx, "~> 0.6"},
      {:jason, "~> 1.4"},
      {:kino, "~> 0.14", optional: true}
    ]
  end
end
