defmodule Nerves.Hub.Mixfile do

  use Mix.Project

  def project, do: [
    app: :nerves_hub,
    version: version,
    elixir: "~> 1.0",
    source_url: "https://github.com/nerves-project/hub",
    homepage_url: "http://nerves-project.org/",
    deps: deps
  ]

  def application, do: [
    mod: { Nerves.Hub, []}
  ]

  defp deps, do: [
    {:earmark, "~> 0.1", only: :dev},
    {:ex_doc, "~> 0.8", only: :dev}
  ]

  defp version do
    case File.read("VERSION") do
      {:ok, ver} -> String.strip ver
      _ -> "0.0.0-dev"
    end
  end
 end
