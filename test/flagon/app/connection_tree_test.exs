defmodule Flagon.App.ConnectionTreeTest do
  use ExUnit.Case, async: true

  alias Flagon.App.ConnectionTree

  defp conn(folder, name, opts \\ []) do
    %{folder: folder, name: name, type: Keyword.get(opts, :type, :kdb), host: "h", port: 1}
  end

  test "places a root (folderless) server as a top-level leaf keyed by its name" do
    [node] = ConnectionTree.build([conn("", "local")], %{})
    assert node.id == {:server, "local"}
    assert node.children == []
    assert node.metadata.connection == "local"
  end

  test "treats a connection with no :folder key as a root server" do
    [node] = ConnectionTree.build([%{name: "local-kdb", type: :kdb, host: "localhost", port: 5001}], %{})
    assert node.id == {:server, "local-kdb"}
  end

  test "nests servers under their folder path" do
    nodes = ConnectionTree.build([conn("PROD/DDRM", "DDRMFX")], %{})

    assert [%{id: {:folder, "PROD"}, children: [prod_ddrm]}] = nodes
    assert prod_ddrm.id == {:folder, "PROD/DDRM"}
    assert [leaf] = prod_ddrm.children
    assert leaf.id == {:server, "PROD/DDRM/DDRMFX"}
  end

  test "keeps colliding leaf names distinct via their folder-qualified id" do
    nodes = ConnectionTree.build([conn("A", "RDB"), conn("B", "RDB")], %{})
    ids = nodes |> Enum.flat_map(& &1.children) |> Enum.map(& &1.id)
    assert {:server, "A/RDB"} in ids
    assert {:server, "B/RDB"} in ids
  end

  test "reflects connection status in the leaf label and metadata" do
    [node] = ConnectionTree.build([conn("", "local")], %{"local" => :connected})
    assert node.metadata.status == :connected
    assert String.contains?(node.label, "local")
  end

  test "builds from the repo's real server list without crashing" do
    path = Path.join(File.cwd!(), "servers_list.txt")

    if File.exists?(path) do
      nodes = path |> Flagon.Config.load_server_list() |> ConnectionTree.build(%{})
      assert length(nodes) > 0
      assert Enum.any?(nodes, &match?(%{id: {:folder, _}}, &1))
      assert Enum.any?(nodes, &match?(%{id: {:folder, "PROD"}}, &1))
    end
  end

  test "orders folders before servers, each alphabetically" do
    conns = [conn("", "zebra"), conn("", "alpha"), conn("Zfolder", "x"), conn("Afolder", "y")]
    nodes = ConnectionTree.build(conns, %{})
    kinds = Enum.map(nodes, fn %{id: id} -> id end)

    assert kinds == [
             {:folder, "Afolder"},
             {:folder, "Zfolder"},
             {:server, "alpha"},
             {:server, "zebra"}
           ]
  end
end
