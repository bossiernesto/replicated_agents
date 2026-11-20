import Config

# No cluster connections by default. Dev sets up a local three-node demo;
# tests and production need no discovery settings unless you add a topology.
config :replicated_agent, :topologies, []
config :replicated_agent, :sync_interval, 200
config :replicated_agent, :refresh_interval, 1_000

import_config "#{config_env()}.exs"
