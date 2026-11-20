import Config

# Start each command in its own terminal:
# iex --name a@127.0.0.1 --cookie replicated -S mix
# iex --name b@127.0.0.1 --cookie replicated -S mix
# iex --name c@127.0.0.1 --cookie replicated -S mix
config :replicated_agent, :topologies,
  local_demo: [
    strategy: Cluster.Strategy.Epmd,
    config: [
      hosts: [
        :"a@127.0.0.1",
        :"b@127.0.0.1",
        :"c@127.0.0.1"
      ]
    ]
  ]
