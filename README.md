# ReplicatedAgent — Elixir 1.20

ReplicatedAgent gives each node its own local Agent-like process and keeps those replicas in sync. It’s a small demo of **local-first, eventually consistent state**, with automatic node discovery and recovery when nodes reconnect.

- **Elixir:** 1.20.x (requires **Erlang/OTP 27+**)
- **libcluster:** 3.6.x, to connect BEAM nodes
- **delta_crdt:** 0.6.5, for the add-wins / last-write-wins map and replica sync
- **`:pg`:** to find each named Agent’s replica processes across connected nodes
- **OTP supervision:** to restart local processes if they crash

## Quick start

From the project directory, fetch dependencies and run the tests:

```bash
mix local.hex --force
mix deps.get
mix test
```

To try replication locally, open three terminals in the project directory and start one node in each:

```bash
# terminal 1
iex --name a@127.0.0.1 --cookie replicated -S mix

# terminal 2
iex --name b@127.0.0.1 --cookie replicated -S mix

# terminal 3
iex --name c@127.0.0.1 --cookie replicated -S mix
```

All three nodes need the same cookie. The local demo topology is configured in `config/dev.exs`.

On node A:

```elixir
Node.list()
ReplicatedAgent.put(:shared, :name, "from node A")
ReplicatedAgent.put(:shared, :only_a, 1)
ReplicatedAgent.status(:shared)
```

On node B:

```elixir
ReplicatedAgent.all(:shared)
ReplicatedAgent.put(:shared, :only_b, 2)
```

On node C:

```elixir
ReplicatedAgent.all(:shared)
# After anti-entropy: %{name: "from node A", only_a: 1, only_b: 2}
```

### Try stopping and restarting a node

1. Stop node B with `System.stop()` (or press Ctrl+C twice).
2. While B is down, write on A: `ReplicatedAgent.put(:shared, :during_partition, "seen later")`.
3. Start B again with the same `iex --name b@127.0.0.1 --cookie replicated -S mix` command.
4. Once the nodes reconnect, check `ReplicatedAgent.all(:shared)` on B for `:during_partition`.
5. For another quick test, write *different keys* on isolated A and C, reconnect them, and watch both values show up.

Stopping B is a **node failure**, not a network partition. To test a real partition while both sides stay up and accept writes, run nodes in separate network namespaces or containers and block their Erlang distribution traffic. You can also call `Node.disconnect/1`, but disable libcluster discovery while testing so it doesn’t immediately reconnect the nodes.

## API

```elixir
ReplicatedAgent.get(:shared, :key, :default)
ReplicatedAgent.put(:shared, :key, "new value")
ReplicatedAgent.delete(:shared, :key)
ReplicatedAgent.all(:shared)
ReplicatedAgent.status(:shared)

# This update only runs locally; don’t use it as a distributed counter.
ReplicatedAgent.local_update(:shared, :count, fn old -> (old || 0) + 1 end)

# You can start another named Agent on each node where you want a replica.
ReplicatedAgent.start_agent(:settings)
ReplicatedAgent.put(:settings, :theme, "dark")
```

Each dynamic Agent is a local OTP child. To replicate `:settings` across A, B, and C, call `start_agent(:settings)` on all three nodes. The built-in `:shared` Agent starts automatically on every node.

### Code structure

```text
mix.exs
config/{config,dev,test,prod}.exs
lib/replicated_agent.ex              # public Agent-like API
lib/replicated_agent/server.ex       # local state owner + :pg membership watcher
lib/replicated_agent/application.ex  # libcluster + registry + supervisors
 test/replicated_agent_test.exs       # local API tests
 test/anti_entropy_test.exs          # disconnected replicas reconcile
```

## How it works

For each named Agent, every node runs **one locally registered GenServer** and **one linked DeltaCrdt process**. The GenServer handles local API calls in order. Each CRDT process joins a `:pg` group named `{:replicated_agent, name}`. The GenServer checks that group regularly, and whenever a BEAM node connects or disconnects, to keep its list of replica processes up to date. DeltaCrdt handles the actual synchronization and anti-entropy.

`libcluster` connects the BEAM nodes; it doesn’t move the Agent state itself. `:pg` finds the **local and remote CRDT process IDs**, rather than remote registered names. That lets replicas find each other again after a process restarts.

### What to expect from consistency

- **Local availability:** a node can keep serving local reads and writes while other nodes are unavailable. There’s **no quorum requirement**.
- **Eventually consistent:** replicas catch up after the network recovers, as long as at least one surviving replica still has the state and anti-entropy has time to run.
- **Conflicting writes to one key:** `DeltaCrdt.AWLWWMap` resolves conflicts according to its own policy; it won’t automatically keep both values. This isn’t an atomic counter, lock, or transaction log.
- **`local_update/3` is local:** it can’t safely combine simultaneous read-modify-write operations from different nodes.
- **State lives in memory:** there’s **no disk persistence**. If every node loses its state, it’s gone. A replacement node needs a surviving replica to recover from.
- **Sync takes time:** a new or restarted replica may return incomplete data before it catches up. `status/1` shows connections; it **doesn’t guarantee** that synchronization is complete.
- **Names are local:** each node has its own process for a given name; using the same name on multiple nodes puts those processes in the same replica group.
- **The local setup is just a demo:** localhost EPMD and the example cookie aren’t safe for production. Use a protected network, keep the cookie secret, and configure a topology for your environment.

The tests cover the local API and check that replicas converge after a simulated disconnect. The three-terminal walkthrough lets you try libcluster and `:pg` with real BEAM nodes.

## Using ReplicatedAgent in another Elixir project

Add it to your app’s `mix.exs`. For a local checkout:

```elixir
defp deps do
  [
    {:replicated_agent, path: "../replicated_agent"}
  ]
end
```

If you’re using a Git repository instead, use a Git dependency:

```elixir
defp deps do
  [
    {:replicated_agent, git: "https://github.com/bossiernesto/replicated_agent.git"}
  ]
end
```

Then fetch the dependency:

```bash
mix deps.get
```

The dependency’s own config files aren’t loaded by your app, so set the library’s required options in your app’s `config/config.exs`:

```elixir
config :replicated_agent,
  topologies: [],
  sync_interval: 200,
  refresh_interval: 1_000
```

An empty topology is fine if you only want to use a local replica. To replicate across nodes, configure a `libcluster` topology for your environment; the localhost setup in this project’s `config/dev.exs` is just for its demo.

The library starts its own supervision tree, including the built-in `:shared` Agent. You don’t need to add its registry or supervisors to your app. Use it from your code like this:

```elixir
ReplicatedAgent.put(:shared, :greeting, "hello")
ReplicatedAgent.get(:shared, :greeting)
```

For another named Agent, call `ReplicatedAgent.start_agent(:settings)` on each node where you want a replica.

## Improvements

- Add CRDT-specific operations, such as `increment` or OR-set add/remove, instead of relying on generic callbacks.
- Persist state or snapshots so the whole cluster can recover.
- Add readiness checks and metrics for reconnection and sync health.
- Build a separate consensus-based option for strong consistency and atomic cluster-wide updates.
