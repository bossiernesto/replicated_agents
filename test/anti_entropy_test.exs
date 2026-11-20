defmodule ReplicatedAgent.AntiEntropyTest do
  use ExUnit.Case, async: false

  test "disconnected CRDT replicas preserve independent writes and converge after rejoin" do
    {:ok, first} = DeltaCrdt.start_link(DeltaCrdt.AWLWWMap, sync_interval: 25)
    {:ok, second} = DeltaCrdt.start_link(DeltaCrdt.AWLWWMap, sync_interval: 25)

    # Pretend the replicas are partitioned by giving each an empty neighbour list.
    DeltaCrdt.set_neighbours(first, [])
    DeltaCrdt.set_neighbours(second, [])

    DeltaCrdt.put(first, :only_on_first, 1)
    DeltaCrdt.put(second, :only_on_second, 2)

    assert DeltaCrdt.to_map(first) == %{only_on_first: 1}
    assert DeltaCrdt.to_map(second) == %{only_on_second: 2}

    # Reconnect them and let both replicas sync until they converge.
    DeltaCrdt.set_neighbours(first, [second])
    DeltaCrdt.set_neighbours(second, [first])

    assert_eventually(fn ->
      expected = %{only_on_first: 1, only_on_second: 2}
      DeltaCrdt.to_map(first) == expected and DeltaCrdt.to_map(second) == expected
    end)
  end

  defp assert_eventually(predicate, attempts \\ 100)

  defp assert_eventually(predicate, 0) do
    assert predicate.()
  end

  defp assert_eventually(predicate, attempts) do
    if predicate.() do
      :ok
    else
      Process.sleep(25)
      assert_eventually(predicate, attempts - 1)
    end
  end
end
