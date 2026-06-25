defmodule Flagon.Schema do
  @moduledoc """
  Normalized schema representation for all backends.
  """

  @type node_type :: :connection | :namespace | :schema | :table | :column | :function | :variable
  @type schema_node :: %{
          id: term(),
          label: String.t(),
          type: node_type(),
          children: [schema_node()] | :lazy,
          metadata: map(),
          icon: String.t() | nil
        }

  @spec to_tree_data([schema_node()]) :: [map()]
  def to_tree_data(nodes) do
    Enum.map(nodes, &convert_node/1)
  end

  @doc """
  Replaces the `children` of the node identified by `id` anywhere in a nested
  node list, leaving the rest untouched. Used to fill in a lazily-loaded node's
  children after they are fetched.
  """
  @spec put_node_children([schema_node()], term(), [schema_node()]) :: [schema_node()]
  def put_node_children(nodes, id, children) when is_list(nodes) do
    Enum.map(nodes, &put_in_node(&1, id, children))
  end

  defp put_in_node(%{id: node_id} = node, id, children) when node_id == id do
    %{node | children: children}
  end

  defp put_in_node(%{children: kids} = node, id, children) when is_list(kids) do
    %{node | children: Enum.map(kids, &put_in_node(&1, id, children))}
  end

  defp put_in_node(node, _id, _children), do: node

  @spec connection_node(String.t(), atom(), :connected | :disconnected | :connecting | :error, [schema_node()]) :: schema_node()
  def connection_node(name, type, status, children) do
    status_indicator =
      case status do
        :connected -> "●"
        :connecting -> "◌"
        :error -> "✗"
        _ -> "○"
      end

    type_label =
      case type do
        :kdb -> "KDB"
        :postgres -> "PG"
        :duckdb -> "Duck"
        other -> to_string(other)
      end

    %{
      id: {:conn, name},
      label: "#{status_indicator} #{name} (#{type_label})",
      type: :connection,
      children: children,
      metadata: %{connection: name, conn_type: type, status: status}
    }
  end

  @spec default_query_for(schema_node(), atom(), non_neg_integer()) :: String.t()
  def default_query_for(%{type: :table, metadata: meta}, conn_type, page_size) do
    case conn_type do
      :kdb ->
        ns = Map.get(meta, :namespace, "")
        table = Map.get(meta, :table, "")
        "#{page_size}#" <> qualified_kdb_name(ns, table)

      type when type in [:postgres, :duckdb] ->
        schema = Map.get(meta, :schema, "public")
        table = Map.get(meta, :table, "")
        "SELECT * FROM #{schema}.#{table} LIMIT #{page_size}"
    end
  end

  def default_query_for(_node, _conn_type, _page_size), do: ""

  defp qualified_kdb_name(".", name), do: name
  defp qualified_kdb_name(".root", name), do: name
  defp qualified_kdb_name("", name), do: name
  defp qualified_kdb_name(ns, name), do: "#{ns}.#{name}"

  defp convert_node(%{children: :lazy} = node) do
    %{
      id: node.id,
      label: node.label,
      icon: icon_for(node),
      children: [%{id: {:lazy, node.id}, label: "…", icon: " ", children: [], metadata: %{}}],
      metadata: Map.get(node, :metadata, %{})
    }
  end

  defp convert_node(%{children: children} = node) when is_list(children) do
    %{
      id: node.id,
      label: node.label,
      icon: icon_for(node),
      children: Enum.map(children, &convert_node/1),
      metadata: Map.get(node, :metadata, %{})
    }
  end

  defp icon_for(%{icon: icon}) when is_binary(icon), do: icon
  defp icon_for(%{type: :connection}), do: "⊞"
  defp icon_for(%{type: :namespace}), do: "N"
  defp icon_for(%{type: :schema}), do: "S"
  defp icon_for(%{type: :table}), do: "T"
  defp icon_for(%{type: :column}), do: " "
  defp icon_for(%{type: :function}), do: "f"
  defp icon_for(%{type: :variable}), do: "v"
  defp icon_for(_), do: " "
end
