defmodule Flagon.Schema do
  @moduledoc """
  Normalized schema representation for all backends.
  """

  @type node_type :: :connection | :namespace | :schema | :table | :column | :function | :variable
  @type schema_node :: %{
          id: term(),
          label: String.t(),
          type: node_type(),
          children: [node()] | :lazy,
          metadata: map(),
          icon: String.t() | nil
        }

  @spec to_tree_data([node()]) :: [map()]
  def to_tree_data(nodes) do
    Enum.map(nodes, &convert_node/1)
  end

  defp convert_node(%{children: :lazy} = node) do
    %{
      id: node.id,
      label: node.label,
      icon: icon_for(node),
      children: [],
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
  defp icon_for(%{type: :namespace}), do: "N"
  defp icon_for(%{type: :schema}), do: "S"
  defp icon_for(%{type: :table}), do: "T"
  defp icon_for(%{type: :column}), do: " "
  defp icon_for(%{type: :function}), do: "f"
  defp icon_for(%{type: :variable}), do: "v"
  defp icon_for(_), do: " "
end
