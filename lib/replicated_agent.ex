defmodule ReplicatedAgent do
  @moduledoc """
  A replicated key/value Agent that accepts local writes and syncs them eventually.

  Each BEAM node runs its own process and `DeltaCrdt.AWLWWMap`. `libcluster`
  connects the nodes, `:pg` helps each logical Agent find its replicas, and
  `DeltaCrdt` keeps those replicas in sync.

  A write waits only for the *local* replica. That means it can still succeed
  while the network is partitioned, but it isn't a cluster-wide transaction.

  If nodes write different values to the same key, AWLWWMap resolves the
  conflict using its own rules. In particular, `local_update/3` is **not** an
  atomic update across nodes.

  Example:

      ReplicatedAgent.put(:shared, :greeting, "hello")
      ReplicatedAgent.get(:shared, :greeting)
      ReplicatedAgent.all(:shared)
  """

  @type agent_name :: term()

  @doc "Starts a named replica registered on this node."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) when is_list(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(ReplicatedAgent.Server, opts, name: via(name))
  end

  @doc "Gives each named Agent its own supervisor child ID."
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    name = Keyword.fetch!(opts, :name)

    %{
      id: {__MODULE__, name},
      start: {__MODULE__, :start_link, [opts]},
      restart: :permanent,
      type: :worker
    }
  end

  @doc "Starts another Agent on this node. Call it on every node that needs a replica."
  @spec start_agent(agent_name(), keyword()) :: DynamicSupervisor.on_start_child()
  def start_agent(name, opts \\ []) do
    opts = Keyword.put(opts, :name, name)

    DynamicSupervisor.start_child(
      ReplicatedAgent.DynamicSupervisor,
      {__MODULE__, opts}
    )
  end

  @doc "Gets a key from this node's replica, or returns the default."
  @spec get(agent_name(), term(), term()) :: term()
  def get(name, key, default \\ nil) do
    GenServer.call(via(name), {:get, key, default})
  end

  @doc "Writes a key on this node; the change is replicated eventually."
  @spec put(agent_name(), term(), term()) :: :ok
  def put(name, key, value) do
    GenServer.call(via(name), {:put, key, value})
  end

  @doc "Deletes a key on this node and replicates the removal."
  @spec delete(agent_name(), term()) :: :ok
  def delete(name, key) do
    GenServer.call(via(name), {:delete, key})
  end

  @doc "Returns this node's current key/value map."
  @spec all(agent_name()) :: map()
  def all(name) do
    GenServer.call(via(name), :all)
  end

  @doc """
  Reads and updates a value on this node, then replicates the result.

  Updates to the same key on other nodes can race and overwrite each other.
  Use this only if that trade-off is okay; it isn't a CRDT counter.
  """
  @spec local_update(agent_name(), term(), (term() -> term())) :: :ok
  def local_update(name, key, fun) when is_function(fun, 1) do
    GenServer.call(via(name), {:local_update, key, fun})
  end

  @doc "Shows local connection and replication details, but doesn't guarantee sync is complete."
  @spec status(agent_name()) :: map()
  def status(name) do
    GenServer.call(via(name), :status)
  end

  defp via(name), do: {:via, Registry, {ReplicatedAgent.LocalRegistry, name}}
end
