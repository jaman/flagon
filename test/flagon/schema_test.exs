defmodule Flagon.SchemaTest do
  use ExUnit.Case, async: true

  alias Flagon.Schema

  test "to_tree_data renders a :lazy node with a placeholder child so it stays expandable" do
    nodes = [%{id: {:table, ".", "t"}, label: "t", type: :table, children: :lazy, metadata: %{}}]

    assert [tree] = Schema.to_tree_data(nodes)
    assert [%{id: {:lazy, {:table, ".", "t"}}}] = tree.children
  end

  test "put_node_children replaces a nested node's children by id" do
    nodes = [
      %{
        id: {:ns, "."},
        label: ".",
        type: :namespace,
        children: [%{id: {:table, ".", "t"}, label: "t", type: :table, children: :lazy, metadata: %{}}],
        metadata: %{}
      }
    ]

    cols = [%{id: {:col, "t", "a"}, label: "a", type: :column, children: [], metadata: %{}}]
    updated = Schema.put_node_children(nodes, {:table, ".", "t"}, cols)

    assert [%{children: [%{id: {:table, ".", "t"}, children: ^cols}]}] = updated
  end

  test "put_node_children leaves other nodes untouched" do
    nodes = [%{id: {:table, ".", "other"}, label: "other", type: :table, children: :lazy, metadata: %{}}]
    assert Schema.put_node_children(nodes, {:table, ".", "t"}, []) == nodes
  end
end
