defmodule ReplicatedAgent.MixProject do
  use Mix.Project

  def project do
    [
      app: :replicated_agent,
      version: "0.1.0",
      elixir: "~> 1.20.0",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {ReplicatedAgent.Application, []}
    ]
  end

  defp deps do
    [
      {:libcluster, "~> 3.6.0"},
      {:delta_crdt, "~> 0.6.5"}
    ]
  end
end
