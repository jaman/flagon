defmodule Flagon.Config.ServerList do
  @moduledoc """
  Parses and serializes hierarchical KDB server lists.

  Two interchangeable formats are supported, both from qStudio:

    * **text** — one server per line, `FOLDER/PATH/LeafName@host:port[:user:password]`.
      The path before the final `/` is the folder hierarchy; the final segment is
      the server's display name. A line with no `/` is a root server.
    * **json** — an array of objects with `label` (leaf name), `tags` (the
      `/`-delimited folder path), `host`, `port`, `user`, `password` and `useTLS`.

  Both parse into the same normalized connection maps carrying a `:folder` path,
  so the rest of the application is agnostic to the source format.
  """

  @type t :: %{
          folder: String.t(),
          name: String.t(),
          type: :kdb,
          host: String.t(),
          port: non_neg_integer(),
          username: String.t() | nil,
          password: String.t() | nil,
          tls: boolean()
        }

  @spec parse_text(String.t()) :: [t()]
  def parse_text(text) do
    text
    |> String.split(["\r\n", "\n"])
    |> Enum.map(&String.trim/1)
    |> Enum.flat_map(&parse_text_line/1)
  end

  @spec to_text([t()]) :: String.t()
  def to_text(connections) do
    connections
    |> Enum.map(&connection_to_line/1)
    |> Enum.join("\n")
  end

  @spec parse_json(String.t()) :: [t()]
  def parse_json(json) do
    case Jason.decode(json) do
      {:ok, objects} when is_list(objects) -> Enum.map(objects, &connection_from_object/1)
      _ -> []
    end
  end

  @spec to_json([t()]) :: String.t()
  def to_json(connections) do
    connections
    |> Enum.map(&connection_to_object/1)
    |> Jason.encode!(pretty: true)
  end

  defp parse_text_line(""), do: []

  defp parse_text_line(line) do
    case String.split(line, "@", parts: 2) do
      [label, connection] -> build_from_text(label, connection)
      _ -> []
    end
  end

  defp build_from_text(label, connection) do
    case parse_connection_part(connection) do
      nil ->
        []

      fields ->
        {folder, name} = split_label(label)
        [Map.merge(%{folder: folder, name: name, type: :kdb}, fields)]
    end
  end

  defp split_label(label) do
    case String.split(label, "/") do
      [single] ->
        {"", single}

      segments ->
        {folders, [name]} = Enum.split(segments, -1)
        {Enum.join(folders, "/"), name}
    end
  end

  defp parse_connection_part(connection) do
    case String.split(connection, ":", parts: 4) do
      [host, port] -> with_port(host, port, nil, nil)
      [host, port, user] -> with_port(host, port, user, nil)
      [host, port, user, password] -> with_port(host, port, user, password)
      _ -> nil
    end
  end

  defp with_port(host, port, user, password) do
    case Integer.parse(port) do
      {parsed_port, ""} ->
        %{host: host, port: parsed_port, username: blank_to_nil(user), password: blank_to_nil(password), tls: false}

      _ ->
        nil
    end
  end

  defp connection_to_line(connection) do
    label =
      case folder_of(connection) do
        "" -> connection.name
        folder -> folder <> "/" <> connection.name
      end

    label <> "@" <> connection_part(connection)
  end

  defp connection_part(connection) do
    base = "#{connection.host}:#{connection.port}"

    case {connection[:username], connection[:password]} do
      {nil, _password} -> base
      {user, nil} -> base <> ":" <> user
      {user, password} -> base <> ":" <> user <> ":" <> password
    end
  end

  defp connection_from_object(object) do
    %{
      folder: folder_of(object),
      name: Map.get(object, "label", ""),
      type: :kdb,
      host: Map.get(object, "host"),
      port: Map.get(object, "port"),
      username: blank_to_nil(Map.get(object, "user")),
      password: blank_to_nil(Map.get(object, "password")),
      tls: Map.get(object, "useTLS", false)
    }
  end

  defp connection_to_object(connection) do
    folder = folder_of(connection)

    %{
      "host" => connection.host,
      "label" => connection.name,
      "password" => connection[:password] || "",
      "port" => connection.port,
      "tags" => folder,
      "uniqLabel" => folder <> "," <> connection.name,
      "useCustomizedAuth" => false,
      "useTLS" => connection[:tls] || false,
      "user" => connection[:username] || ""
    }
  end

  defp folder_of(%{folder: folder}) when is_binary(folder), do: folder
  defp folder_of(%{"tags" => tags}) when is_binary(tags), do: tags
  defp folder_of(_connection), do: ""

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value
end
