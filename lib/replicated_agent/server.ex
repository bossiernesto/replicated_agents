defmodule ReplicatedAgent.Server do
  @moduledoc false
  use GenServer

  @impl true
  def init(opts) do
    name = Keyword.fetch!(opts, :name)

    sync_interval =
      Keyword.get(opts, :sync_interval, Application.fetch_env!(:replicated_agent, :sync_interval))

    refresh_interval =
      Keyword.get(
        opts,
        :refresh_interval,
        Application.fetch_env!(:replicated_agent, :refresh_interval)
      )

    # Keep the CRDT linked so supervision can restart it with this server.
    {:ok, crdt} = DeltaCrdt.start_link(DeltaCrdt.AWLWWMap, sync_interval: sync_interval)
    group = {:replicated_agent, name}
    :ok = :pg.join(group, crdt)

    if Node.alive?(), do: :net_kernel.monitor_nodes(true)
    send(self(), :refresh_neighbours)

    {:ok,
     %{
       name: name,
       group: group,
       crdt: crdt,
       neighbours: MapSet.new(),
       refresh_interval: refresh_interval
     }}
  end

  @impl true
  def handle_call({:get, key, default}, _from, state) do
    value = state.crdt |> DeltaCrdt.to_map() |> Map.get(key, default)
    {:reply, value, state}
  end

  def handle_call({:put, key, value}, _from, state) do
    DeltaCrdt.put(state.crdt, key, value)
    {:reply, :ok, state}
  end

  def handle_call({:delete, key}, _from, state) do
    DeltaCrdt.delete(state.crdt, key)
    {:reply, :ok, state}
  end

  def handle_call(:all, _from, state) do
    {:reply, DeltaCrdt.to_map(state.crdt), state}
  end

  def handle_call({:local_update, key, fun}, _from, state) do
    old_value = state.crdt |> DeltaCrdt.to_map() |> Map.get(key)
    new_value = fun.(old_value)
    DeltaCrdt.put(state.crdt, key, new_value)
    {:reply, :ok, state}
  end

  def handle_call(:status, _from, state) do
    peer_nodes =
      state.neighbours
      |> Enum.map(&node/1)
      |> Enum.uniq()
      |> Enum.sort()

    {:reply,
     %{
       name: state.name,
       local_node: node(),
       connected_nodes: Node.list(),
       replication_peers: MapSet.size(state.neighbours),
       peer_nodes: peer_nodes
     }, state}
  end

  @impl true
  def handle_info({:nodeup, _node}, state) do
    {:noreply, refresh_neighbours(state)}
  end

  def handle_info({:nodedown, _node}, state) do
    {:noreply, refresh_neighbours(state)}
  end

  def handle_info(:refresh_neighbours, state) do
    state = refresh_neighbours(state)
    Process.send_after(self(), :refresh_neighbours, state.refresh_interval)
    {:noreply, state}
  end

  defp refresh_neighbours(state) do
    connected_nodes = [node() | Node.list()]

    neighbours =
      state.group
      |> :pg.get_members()
      |> Enum.filter(fn pid ->
        pid != state.crdt and node(pid) in connected_nodes
      end)
      |> MapSet.new()

    if neighbours != state.neighbours do
      # Each replica sets its own neighbours, so this call only updates ours.
      :ok = DeltaCrdt.set_neighbours(state.crdt, MapSet.to_list(neighbours))
      %{state | neighbours: neighbours}
    else
      state
    end
  end
end
