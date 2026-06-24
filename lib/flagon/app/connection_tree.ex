defmodule Flagon.App.ConnectionTree do
  @moduledoc """
  Builds Drafter tree data from a flat connection list, nesting servers under
  their `folder` path. Folder branch nodes carry `id: {:folder, path}`; server
  leaf nodes carry `id: {:server, qualified_name}` so colliding leaf names stay
  distinct and selection yields a unique connection id.
  """

  alias Flagon.Config

  @type status :: :connected | :disconnected | :connecting | :error
  @type tree_node :: %{
          id: {:folder, String.t()} | {:server, String.t()},
          label: String.t(),
          icon: String.t(),
          children: [tree_node()],
          metadata: map()
        }

  @spec build([map()], %{optional(String.t()) => status()}) :: [tree_node()]
  def build(connections, statuses) do
    connections
    |> Enum.reduce(%{}, fn connection, acc -> insert(acc, segments(Map.get(connection, :folder)), connection) end)
    |> to_nodes(statuses, "")
  end

  defp segments(folder) when is_binary(folder) and folder != "", do: String.split(folder, "/")
  defp segments(_folder), do: []

  defp insert(level, [], connection) do
    Map.update(level, :servers, [connection], &[connection | &1])
  end

  defp insert(level, [segment | rest], connection) do
    Map.update(level, segment, insert(%{}, rest, connection), &insert(&1, rest, connection))
  end

  defp to_nodes(level, statuses, prefix) do
    folders =
      level
      |> Map.delete(:servers)
      |> Enum.sort_by(fn {segment, _sub} -> segment end)
      |> Enum.map(fn {segment, sub} -> folder_node(segment, sub, statuses, prefix) end)

    servers =
      level
      |> Map.get(:servers, [])
      |> Enum.sort_by(& &1.name)
      |> Enum.map(&server_node(&1, statuses))

    folders ++ servers
  end

  defp folder_node(segment, sub, statuses, prefix) do
    path = if prefix == "", do: segment, else: prefix <> "/" <> segment

    %{
      id: {:folder, path},
      label: segment,
      icon: "▸",
      children: to_nodes(sub, statuses, path),
      metadata: %{}
    }
  end

  defp server_node(connection, statuses) do
    id = Config.qualified_name(connection)
    status = Map.get(statuses, id, :disconnected)

    %{
      id: {:server, id},
      label: "#{status_indicator(status)} #{connection.name}",
      icon: type_icon(connection.type),
      children: [],
      metadata: %{connection: id, type: connection.type, status: status}
    }
  end

  defp status_indicator(:connected), do: "●"
  defp status_indicator(:connecting), do: "◌"
  defp status_indicator(:error), do: "✗"
  defp status_indicator(_status), do: "○"

  defp type_icon(:kdb), do: "K"
  defp type_icon(:postgres), do: "P"
  defp type_icon(:duckdb), do: "D"
  defp type_icon(_type), do: " "
end
