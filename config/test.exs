import Config

# Keep node discovery off in tests.
config :replicated_agent, :topologies, []
config :replicated_agent, :refresh_interval, 50
config :replicated_agent, :sync_interval, 25
