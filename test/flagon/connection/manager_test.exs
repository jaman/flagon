defmodule Flagon.Connection.ManagerTest do
  use ExUnit.Case, async: false

  alias Flagon.Connection.Manager

  test "keys connections by folder-qualified name so colliding leaf names coexist" do
    configs = [
      %{folder: "A", name: "RDB", type: :kdb, host: "h", port: 1},
      %{folder: "B", name: "RDB", type: :kdb, host: "h", port: 2}
    ]

    assert :ok = Manager.load_connections(configs)
    keys = Manager.list_connections() |> Enum.map(&elem(&1, 0))
    assert "A/RDB" in keys
    assert "B/RDB" in keys
  end

  test "switch/1 resolves a qualified id and rejects unknown ids" do
    Manager.load_connections([%{folder: "A", name: "RDB", type: :kdb, host: "h", port: 1}])
    assert :ok = Manager.switch("A/RDB")
    assert {:error, :unknown_connection} = Manager.switch("missing")
  end

  test "load_columns/3 errors when the connection is not connected (no eager crawl)" do
    Manager.load_connections([%{folder: "A", name: "RDB", type: :kdb, host: "h", port: 1}])
    assert {:error, :not_connected} = Manager.load_columns("A/RDB", ".", "trade")
  end
end
