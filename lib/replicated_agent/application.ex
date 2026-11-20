defmodule ReplicatedAgent.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    topologies = Application.fetch_env!(:replicated_agent, :topologies)

    children = [
      {Cluster.Supervisor, [topologies, [name: ReplicatedAgent.ClusterSupervisor]]},
      %{id: :pg, start: {:pg, :start_link, []}},
      {Registry, keys: :unique, name: ReplicatedAgent.LocalRegistry},
      {DynamicSupervisor, strategy: :one_for_one, name: ReplicatedAgent.DynamicSupervisor},
      # Each node starts its own replica with the same logical name.
      {ReplicatedAgent, name: :shared}
    ]

    Supervisor.start_link(children,
      strategy: :one_for_one,
      name: ReplicatedAgent.Supervisor
    )
  end
end
