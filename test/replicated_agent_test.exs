defmodule ReplicatedAgentTest do
  use ExUnit.Case, async: false

  test "named agents provide local get, put, all and delete" do
    start_supervised!({ReplicatedAgent, name: :test_settings})

    assert ReplicatedAgent.get(:test_settings, :missing, :default) == :default
    assert :ok = ReplicatedAgent.put(:test_settings, :theme, "dark")
    assert ReplicatedAgent.get(:test_settings, :theme) == "dark"
    assert ReplicatedAgent.all(:test_settings) == %{theme: "dark"}
    assert :ok = ReplicatedAgent.delete(:test_settings, :theme)
    assert ReplicatedAgent.all(:test_settings) == %{}
  end

  test "independent logical names remain isolated" do
    start_supervised!({ReplicatedAgent, name: :agent_one})
    start_supervised!({ReplicatedAgent, name: :agent_two})

    ReplicatedAgent.put(:agent_one, :key, "a")
    ReplicatedAgent.put(:agent_two, :key, "b")

    assert ReplicatedAgent.get(:agent_one, :key) == "a"
    assert ReplicatedAgent.get(:agent_two, :key) == "b"
  end

  test "local_update serializes on a single node but is not a global atomic update" do
    start_supervised!({ReplicatedAgent, name: :test_local_update})

    assert :ok = ReplicatedAgent.local_update(:test_local_update, :count, fn x -> (x || 0) + 1 end)
    assert :ok = ReplicatedAgent.local_update(:test_local_update, :count, fn x -> x + 1 end)
    assert ReplicatedAgent.get(:test_local_update, :count) == 2
  end

  test "status describes the local instance" do
    start_supervised!({ReplicatedAgent, name: :test_status})
    assert %{name: :test_status, replication_peers: 0} = ReplicatedAgent.status(:test_status)
  end
end
